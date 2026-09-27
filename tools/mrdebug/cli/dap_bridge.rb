module MRDebug
  module CLI
    # A DAP request handler on top of a @remote (a RemoteSession for the
    # same-process interim demo, or a DeviceLink for a real TCP-connected
    # device -- see device_link.rb). #handle takes a parsed request Hash
    # and returns response/event Hashes, so it's testable without a
    # socket; #handle_message wraps that with Json for raw text.
    # evaluate/scopes/variables are plain (mrdbg) commands sent through
    # @remote.command -- `frame N` to select the DAP frame, then `p expr` /
    # `info locals` -- with their text output parsed back here, so a frame's
    # locals never need a structured encoding on the wire. stepOut isn't
    # handled yet (no `finish` command). A device path never resolves as a
    # local file, so VS Code always needs `source` (device: `cat`) to
    # actually show the source.
    # continue/next/stepIn only ack
    # here; the *next* stop (or termination) is reported later via
    # #stop_messages/#terminated_notification, once whoever is
    # actually watching @remote (DapServer, for a real device) observes it
    # -- @remote's own resume methods no longer block waiting for it.
    #
    # Breakpoints are `break`/`delete` commands too. DAP ids are the
    # bridge's own; each maps to the device number parsed from the
    # "Breakpoint N added at ..." reply (line and method breakpoints share
    # one number sequence on the device). A running device reads no
    # commands, so breakpoints set while running are held and applied at
    # the next stop, reported by `breakpoint` `changed` events.
    class DapBridge
      CAPABILITIES = {
        'supportsConfigurationDoneRequest' => true,
        'supportsConditionalBreakpoints' => true,
        'supportsFunctionBreakpoints' => true,
        'supportsEvaluateForHovers' => true,
      }.freeze

      def initialize(remote)
        @remote = remote
        @seq = 0
        @handshake_done = false
        @running = false
        @last_resume = nil
        @next_bp_id = 0
        @line_bps = {}     # file => [[dap_id, device_number | nil], ...]
        @function_bps = [] # [[dap_id, device_number | nil], ...]
        @pending = []      # [[:line, file, requested, ids] | [:function, nil, requested, ids], ...]
      end

      def handshake_done?
        @handshake_done
      end

      # request_json -> Array of response/event JSON strings.
      def handle_message(request_json)
        request = Json.parse(request_json)
        handle(request).map { |msg| Json.generate(msg) }
      end

      # request Hash -> Array of response/event Hashes, in the order they
      # should be sent.
      def handle(request)
        @handshake_done ? handle_stop_request(request) : handle_handshake_request(request)
      rescue => e
        [error_response(request, e)]
      end

      # Unprompted events for the caller to send whenever it observes
      # @remote stop on its own (e.g. DapServer polling a DeviceLink after
      # a continue/next/stepIn), given that stop's banner line: `breakpoint`
      # changes for anything set while running (applied now, the device
      # being back at its prompt), then the `stopped` event itself.
      def stop_messages(banner)
        @running = false
        msgs = apply_pending
        reason, hit_ids = stop_reason(banner.to_s)
        msgs << stopped_event(reason, banner, hit_ids)
        msgs
      end

      # An unprompted `terminated` event, likewise.
      def terminated_notification
        terminated_event
      end

      private

      def next_seq
        @seq += 1
        @seq
      end

      def response(request, body = {}, success: true, message: nil)
        msg = {
          'seq' => next_seq,
          'type' => 'response',
          'request_seq' => request['seq'],
          'success' => success,
          'command' => request['command'],
          'body' => body,
        }
        msg['message'] = message if message
        msg
      end

      def error_response(request, err)
        response(request, {}, success: false, message: "#{err.class}: #{err.message}")
      end

      def event(name, body = {})
        { 'seq' => next_seq, 'type' => 'event', 'event' => name, 'body' => body }
      end

      def not_supported(request)
        response(request, {}, success: false,
                 message: "#{request['command']}: not supported yet")
      end

      def handle_handshake_request(request)
        case request['command']
        when 'initialize'
          [response(request, CAPABILITIES), event('initialized')]
        when 'attach', 'launch'
          [response(request)]
        when 'setBreakpoints'
          [response(request, set_breakpoints_body(request))]
        when 'setFunctionBreakpoints'
          [response(request, set_function_breakpoints_body(request))]
        when 'configurationDone'
          @handshake_done = true
          [response(request), stopped_event('entry')]
        else
          [response(request, {}, success: false,
                     message: "unexpected before configurationDone: #{request['command']}")]
        end
      end

      def handle_stop_request(request)
        case request['command']
        when 'continue'
          resume(:continue) { @remote.run_mode! }
          [response(request, { 'allThreadsContinued' => true })]
        when 'next'
          resume(:next) { @remote.next_mode! }
          [response(request)]
        when 'stepIn'
          resume(:step) { @remote.step_mode! }
          [response(request)]
        when 'stackTrace'
          [response(request, stack_trace_body)]
        when 'source'
          [response(request, source_body(request))]
        when 'evaluate'
          [evaluate_response(request)]
        when 'scopes'
          [response(request, scopes_body(request))]
        when 'variables'
          [response(request, variables_body(request))]
        when 'stepOut'
          [not_supported(request)]
        when 'setBreakpoints'
          [response(request, set_breakpoints_body(request))]
        when 'setFunctionBreakpoints'
          [response(request, set_function_breakpoints_body(request))]
        when 'threads'
          [response(request, { 'threads' => [{ 'id' => 1, 'name' => 'main' }] })]
        when 'disconnect'
          # Let the device run free, like debug gem: drop every breakpoint
          # (no client is left to stop for), then continue. A running
          # device reads nothing; closing the connection is what lets its
          # later stops fall through (LocalConsole returns on EOF).
          unless @running
            @remote.command('delete')
            resume(:continue) { @remote.run_mode! }
          end
          @pending = []
          [response(request), terminated_event]
        else
          [response(request, {}, success: false, message: "unsupported command: #{request['command']}")]
        end
      end

      def stopped_event(reason, text = nil, hit_ids = nil)
        body = { 'reason' => reason, 'threadId' => 1, 'allThreadsStopped' => true }
        body['text'] = text if text
        body['hitBreakpointIds'] = hit_ids if hit_ids
        event('stopped', body)
      end

      def resume(kind)
        yield
        @running = true
        @last_resume = kind
      end

      # [DAP reason, hitBreakpointIds | nil] for a stop banner (see
      # Session#stop_banner): "Breakpoint N: ...", "Watchpoint N: ...", or
      # "Stop: ..." -- the last is a step, or binding.debugger when the
      # device was let run with continue.
      def stop_reason(banner)
        if banner[0, 11] == 'Breakpoint '
          n = banner[11..-1].to_i
          fn = @function_bps.find { |_, num| num == n }
          return ['function breakpoint', [fn[0]]] if fn
          @line_bps.each_value do |entries|
            hit = entries.find { |_, num| num == n }
            return ['breakpoint', [hit[0]]] if hit
          end
          return ['breakpoint', nil]
        end
        return ['data breakpoint', nil] if banner[0, 11] == 'Watchpoint '
        [@last_resume == :continue ? 'breakpoint' : 'step', nil]
      end

      def terminated_event
        event('terminated')
      end

      # Replaces the full breakpoint set for one file: deactivate its
      # existing breakpoints, then re-add the requested lines. Normalizes
      # to a basename first -- VS Code's absolute path won't suffix-match
      # the device's short running path otherwise (dap/06's lesson).
      def set_breakpoints_body(request)
        args = request['arguments'] || {}
        file = basename(((args['source'] || {})['path']).to_s)
        requested = args['breakpoints'] || []
        ids = requested.map { new_bp_id }
        results = @running ? defer(:line, file, requested, ids) : apply_line(file, requested, ids)
        { 'breakpoints' => results }
      end

      # Replaces every function breakpoint, as DAP's request does. Only a
      # method spec (`Foo#bar` / `Foo.bar` / `bar`) is accepted -- anything
      # else would reach `break` as a line location.
      def set_function_breakpoints_body(request)
        requested = (request['arguments'] || {})['breakpoints'] || []
        ids = requested.map { new_bp_id }
        results = @running ? defer(:function, nil, requested, ids) : apply_function(requested, ids)
        { 'breakpoints' => results }
      end

      def new_bp_id
        @next_bp_id += 1
      end

      # Held until the next stop. A later request for the same file (or
      # the function set) supersedes an earlier held one.
      def defer(kind, key, requested, ids)
        @pending = @pending.reject { |k, f, _, _| k == kind && f == key }
        @pending << [kind, key, requested, ids]
        ids.map { |id| { 'id' => id, 'verified' => false, 'message' => 'Set when the program next stops' } }
      end

      def apply_pending
        msgs = []
        @pending.each do |kind, key, requested, ids|
          results = kind == :line ? apply_line(key, requested, ids) : apply_function(requested, ids)
          results.each { |bp| msgs << event('breakpoint', 'reason' => 'changed', 'breakpoint' => bp) }
        end
        @pending = []
        msgs
      end

      def apply_line(file, requested, ids)
        (@line_bps[file] || []).each { |_, n| @remote.command("delete #{n}") if n }
        entries = []
        results = []
        requested.each_with_index do |bp, i|
          n, message = add_breakpoint("#{file}:#{bp['line']}", condition_of(bp))
          entries << [ids[i], n]
          results << bp_result(ids[i], n, message, bp['line'])
        end
        @line_bps[file] = entries
        results
      end

      def apply_function(requested, ids)
        @function_bps.each { |_, n| @remote.command("delete #{n}") if n }
        @function_bps = []
        results = []
        requested.each_with_index do |bp, i|
          name = MRDebug::Command.trim(bp['name'].to_s)
          if MRDebug::Command.parse_method_spec(name)
            n, message = add_breakpoint(name, condition_of(bp))
          else
            n = nil
            message = "Not a method name: #{name} (expected Class#method, Class.method or method)"
          end
          @function_bps << [ids[i], n]
          results << bp_result(ids[i], n, message)
        end
        results
      end

      # [device_number, nil] or [nil, the device's reply as the reason].
      def add_breakpoint(location, condition)
        return [nil, 'Multi-line conditions are not supported'] if condition && condition.index("\n")
        out = @remote.command(condition ? "break #{location} if #{condition}" : "break #{location}")
        n = added_number(out[0].to_s)
        n ? [n, nil] : [nil, out.join("\n")]
      end

      # "Breakpoint N added at ..." -> N, else nil.
      def added_number(line)
        return nil unless line[0, 11] == 'Breakpoint '
        rest = line[11..-1]
        sp = rest.index(' ')
        return nil unless sp && rest[sp, 10] == ' added at '
        rest[0, sp].to_i
      end

      def bp_result(id, number, message, line = nil)
        result = { 'id' => id, 'verified' => !number.nil? }
        result['line'] = line if line
        result['message'] = message if message
        result
      end

      # VS Code sends "" once a condition is cleared in its UI.
      def condition_of(bp)
        cond = bp['condition']
        cond.nil? || cond.empty? ? nil : cond
      end

      # frame ids are backtrace indexes (0 = innermost/current) -- the same
      # numbering `frame N` takes, so evaluate/scopes/variables can select
      # a frame by its id directly.
      def stack_trace_body
        frames = @remote.backtrace
        stack_frames = []
        i = 0
        while i < frames.size
          file, line = frames[i]
          stack_frames << {
            'id' => i,
            'name' => i == 0 ? 'top' : "frame #{i}",
            'line' => line,
            'column' => 1,
            'source' => { 'name' => basename(file), 'path' => file },
          }
          i += 1
        end
        { 'stackFrames' => stack_frames, 'totalFrames' => stack_frames.size }
      end

      # VS Code falls back to a `source` request whenever it can't open a
      # stackTrace frame's `source.path` as a local file (the device's own
      # path, e.g. "./dap_test.rb", never exists on the host) -- @remote's
      # `source` fetches it over the wire instead (device: `cat`).
      def source_body(request)
        path = ((request['arguments'] || {})['source'] || {})['path']
        { 'content' => @remote.source(path) }
      end

      # `p expr` in the requested frame. A failed evaluation is a
      # success:false response, which is also what keeps VS Code from
      # showing a hover for an identifier that doesn't evaluate.
      def evaluate_response(request)
        args = request['arguments'] || {}
        expr = args['expression'].to_s
        if expr.index("\n")
          return response(request, {}, success: false,
                          message: 'multi-line expressions are not supported')
        end
        error = select_frame(args['frameId'])
        return response(request, {}, success: false, message: error) if error

        out = @remote.command("p #{expr}")
        text = out.join("\n")
        if eval_error?(out)
          response(request, {}, success: false, message: text)
        else
          response(request, { 'result' => text, 'variablesReference' => 0 })
        end
      end

      def eval_error?(out)
        first = out[0].to_s
        prefix = MRDebug::Command::EVAL_ERROR_PREFIX
        first[0, prefix.size] == prefix || first == MRDebug::Command::NO_BINDING ||
          first[0, 6] == 'Usage:'
      end

      # One "Locals" scope per frame. variablesReference must be > 0, so
      # it's the frame id + 1.
      def scopes_body(request)
        frame_id = ((request['arguments'] || {})['frameId'] || 0).to_i
        { 'scopes' => [{ 'name' => 'Locals', 'presentationHint' => 'locals',
                         'variablesReference' => frame_id + 1, 'expensive' => false }] }
      end

      # `info locals` in the frame a scopes response named, one
      # "name = value" line each; anything else ("No local variables", ...)
      # is skipped. Values aren't expandable (variablesReference 0).
      def variables_body(request)
        ref = ((request['arguments'] || {})['variablesReference'] || 0).to_i
        variables = []
        error = select_frame(ref - 1)
        raise error if error

        @remote.command('info locals').each do |line|
          sep = line.index(' = ')
          next unless sep
          variables << { 'name' => line[0, sep], 'value' => line[(sep + 3)..-1],
                         'variablesReference' => 0 }
        end
        { 'variables' => variables }
      end

      # `frame N` for a DAP frame id (nil = the innermost frame). Returns
      # nil on success, or the device's error line (e.g. "No frame #9").
      def select_frame(frame_id)
        n = frame_id.nil? ? 0 : frame_id.to_i
        out = @remote.command("frame #{n}")
        first = out[0].to_s
        first[0, 1] == '#' ? nil : first
      end

      def basename(path)
        slash = path.rindex('/')
        slash ? path[(slash + 1), path.size - slash - 1] : path
      end
    end
  end
end
