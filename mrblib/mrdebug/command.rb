module MRDebug
  module Command
    VERBS = {
      'c' => :continue, 'continue' => :continue,
      's' => :step, 'step' => :step,
      'n' => :next, 'next' => :next,
      'fin' => :finish, 'finish' => :finish,
      'b' => :break, 'break' => :break,
      'd' => :delete, 'delete' => :delete,
      'l' => :list, 'list' => :list,
      'p' => :print, 'print' => :print,
      'bt' => :backtrace, 'backtrace' => :backtrace, 'where' => :backtrace,
      'f' => :frame, 'frame' => :frame,
      'up' => :up,
      'down' => :down,
      'cat' => :cat,
      'i' => :info, 'info' => :info,
      'display' => :display,
      'watch' => :watch,
      'h' => :help, 'help' => :help,
    }

    # Lines of context shown before/after the target line by `list`.
    LIST_CONTEXT = 5

    # [verb, label, short, long] per command, in `help`'s listing order.
    # Modeled on mruby-bin-debugger's (mrdb) help_msg_list: `help` prints
    # every label/short pair, `help <cmd>` (any alias) prints `long`.
    HELP = [
      [:backtrace, 'bt, backtrace, where', 'Show the call stack', [
        'Usage: backtrace',
        '',
        'Show the call stack, innermost frame first (#0 is the stop itself).',
      ]],
      [:break, 'b[reak]', 'Set breakpoint', [
        'Usage: break [file:]line [if expr]',
        '       break Class#method | Class.method | method [if expr]',
        '',
        'Set breakpoint at specified line or method.',
        'If \'[file:]line\' is specified, break at start of code for that line (in a file).',
        'The file name matches by suffix; it defaults to the current file.',
        'If \'Class#method\' is specified, break on entering that instance method',
        '(subclasses and includers included); \'Class.method\' for a singleton method,',
        'bare \'method\' for a method of any class.',
        'With \'if expr\', stop only when expr is truthy.',
        'With no argument, list breakpoints.',
      ]],
      [:cat, 'cat', 'Show a whole source file', [
        'Usage: cat [file]',
        '',
        'Print the whole source file (the current file with no argument).',
      ]],
      [:continue, 'c[ontinue]', 'Continue program being debugged', [
        'Usage: continue',
        '',
        'Continue program stopped by a breakpoint.',
      ]],
      [:delete, 'd[elete]', 'Delete breakpoints', [
        'Usage: delete [bpno]',
        '',
        'Delete the breakpoint numbered bpno.',
        'To delete all breakpoints, give no argument.',
      ]],
      [:display, 'display', 'Print expression at every stop', [
        'Usage: display expr',
        '',
        'Evaluate and print the value of the mruby expression every time the program stops.',
      ]],
      [:down, 'down', 'Select the callee frame', [
        'Usage: down [N]',
        '',
        'Move the selected frame N frames back toward the stop (N defaults to 1).',
      ]],
      [:finish, 'fin[ish]', 'Run until the selected frame returns', [
        'Usage: finish',
        '',
        'Continue until the selected frame returns, and stop at the next line run',
        'in its caller. Breakpoints are not checked on the way.',
      ]],
      [:frame, 'f[rame]', 'Select or show a frame', [
        'Usage: frame [N]',
        '',
        'Select frame N (numbered as by \'backtrace\'), or show the selected frame.',
        '\'print\' and \'list\' follow the selected frame; execution resumes from the stop.',
      ]],
      [:help, 'h[elp]', 'Print this help', [
        'Usage: help [command]',
        '',
        'With no arguments, help displays a short list of commands.',
        'With a command name as help argument, help displays how to use that command.',
      ]],
      [:info, 'i[nfo]', 'Show local variables', [
        'Usage: info [locals]',
        '',
        'Show the local variables of the selected frame, one \'name = value\' per line.',
      ]],
      [:list, 'l[ist]', 'List specified line', [
        'Usage: list',
        '       list line',
        '       list filename:line',
        '',
        "Print #{LIST_CONTEXT} lines on either side of a line of a source file.",
        '',
        'With no argument, list prints around the selected frame\'s current line.',
        'With filename, list prints lines in the specified source file.',
      ]],
      [:next, 'n[ext]', 'Step program, stepping over calls', [
        'Usage: next [N]',
        '',
        'Step program until it reaches a different source line in the same or a shallower frame.',
        'Repeat N times (N defaults to 1).',
      ]],
      [:print, 'p[rint]', 'Print value of expression', [
        'Usage: print expr',
        '',
        'It evaluates and prints the value of the mruby expression in the selected frame.',
      ]],
      [:step, 's[tep]', 'Step program until it reaches a different source line', [
        'Usage: step [N]',
        '',
        'Step program until it reaches a different source line, entering calls.',
        'Repeat N times (N defaults to 1).',
      ]],
      [:up, 'up', 'Select the caller frame', [
        'Usage: up [N]',
        '',
        'Move the selected frame N frames toward the caller (N defaults to 1).',
      ]],
      [:watch, 'watch', 'Stop when an expression changes', [
        'Usage: watch [expr]',
        '',
        'Stop when the value of the mruby expression changes.',
        'With no argument, list watches.',
      ]],
    ]

    NO_POSITION = 'No current position (not stopped anywhere yet)'.freeze
    NO_FILESYSTEM = 'Source listing is not available (no filesystem access in this build)'.freeze
    INVALID_LINE = 'Invalid line number'.freeze

    # Verbs that hand control back to the debuggee (see .resume). Every
    # other verb maps to a `<verb>_cmd(session, arg)` returning output lines.
    RESUMING = [:continue, :step, :next, :finish]

    # Parses one command line and dispatches it against `session`.
    # Returns [output_lines, :stay | :resume]; never prints (the UI does).
    def self.dispatch(session, line)
      verb, arg = split(line)
      # An empty line just prompts again (never resumes by accident).
      return [[], :stay] if verb.empty?
      cmd = VERBS[verb]
      return [["unknown command: #{line}"], :stay] unless cmd
      return resume(session, cmd, arg) if RESUMING.include?(cmd)
      [__send__(:"#{cmd}_cmd", session, arg), :stay]
    end

    def self.resume(session, cmd, arg)
      case cmd
      when :continue then session.run_mode!
      when :step then session.step_mode!(parse_count(arg))
      when :next then session.next_mode!(parse_count(arg))
      when :finish
        return [[NO_POSITION], :stay] if session.location.nil?
        session.finish_mode!
      end
      [[], :resume]
    end

    # Character classes, by hand: nil-safe (a past-the-end String#[] is
    # nil), and no Regexp (mruby may have none).
    def self.space?(c)
      c == ' ' || c == "\t" || c == "\n" || c == "\r"
    end

    def self.digit?(c)
      !c.nil? && c >= '0' && c <= '9'
    end

    def self.lower?(c)
      !c.nil? && c >= 'a' && c <= 'z'
    end

    def self.upper?(c)
      !c.nil? && c >= 'A' && c <= 'Z'
    end

    def self.word_char?(c)
      lower?(c) || upper?(c) || digit?(c) || c == '_'
    end

    def self.digits?(str)
      return false if str.empty?
      i = 0
      while i < str.size
        return false unless digit?(str[i])
        i += 1
      end
      true
    end

    # Not String#strip -- mruby-string-ext methods misbehave under mrbtest.
    def self.trim(str)
      i = 0
      i += 1 while i < str.size && space?(str[i])
      j = str.size - 1
      j -= 1 while j >= i && space?(str[j])
      str[i, j - i + 1]
    end

    def self.blank?(str)
      str.nil? || trim(str).size == 0
    end

    # Blank or non-positive defaults to 1.
    def self.parse_count(arg)
      return 1 if blank?(arg)
      n = trim(arg).to_i
      n > 0 ? n : 1
    end

    def self.split(line)
      verb, arg = trim(line).split(' ', 2)
      [verb || '', arg]
    end

    def self.break_cmd(session, arg)
      return list_breakpoints(session) if blank?(arg)

      location, condition = split_condition(arg)
      spec = parse_method_spec(location)
      if spec
        n = session.add_method_breakpoint(spec[0], spec[1], spec[2], condition)
      else
        file, ln = parse_location(session.file, location)
        return [INVALID_LINE] unless ln && ln > 0
        n = session.add_breakpoint(file, ln, condition)
      end
      ["#{Protocol::BREAKPOINT}#{n}#{Protocol::ADDED_AT}#{session.breakpoints[n - 1]}"]
    end

    # "Foo#bar" / "Foo::Bar#bar" / "Foo.bar" / "bar" -> [class_name|nil,
    # method_name, singleton?]. nil when it isn't a method spec (fall back
    # to a line breakpoint).
    def self.parse_method_spec(loc)
      sep = loc.index('#') || loc.rindex('.')
      return (method_name?(loc) ? [nil, loc, false] : nil) unless sep
      cname = loc[0, sep]
      mname = loc[(sep + 1)..-1]
      return nil unless const_path?(cname) && method_name?(mname)
      [cname, mname, loc[sep] == '.']
    end

    # "Foo" or "Foo::Bar::Baz": each segment starts A-Z, rest word chars.
    def self.const_path?(str)
      return false if str.empty?
      str.split('::').all? { |seg| const_name?(seg) }
    end

    def self.const_name?(seg)
      upper?(seg[0]) && word_rest?(seg, 1)
    end

    # Starts a-z or _, rest word chars, optional trailing ! ? =.
    def self.method_name?(str)
      return false unless lower?(str[0]) || str[0] == '_'
      last = str.size - 1
      tail = str[last]
      stop = (tail == '!' || tail == '?' || tail == '=') ? last : str.size
      word_rest?(str, 1, stop)
    end

    def self.word_rest?(str, from, upto = nil)
      upto ||= str.size
      i = from
      while i < upto
        return false unless word_char?(str[i])
        i += 1
      end
      true
    end

    # Splits "<location> if <condition>" at the first " if ". Returns
    # [location, nil] when there's no such clause.
    def self.split_condition(arg)
      idx = arg.index(' if ')
      return [arg, nil] unless idx
      [trim(arg[0, idx]), trim(arg[(idx + 4)..-1])]
    end

    # `[<file>:]<line>`: split at the last ':', else current_file is used.
    def self.parse_location(current_file, arg)
      colon = arg.rindex(':')
      return [current_file, arg.to_i] unless colon
      file = arg[0, colon]
      file = current_file if file.empty?
      [file, arg[(colon + 1)..-1].to_i]
    end

    def self.list_breakpoints(session)
      lines = []
      session.breakpoints.each_with_index do |bp, i|
        lines << bp.numbered_line(i + 1) if bp.active?
      end
      lines.empty? ? ['No breakpoints set'] : lines
    end

    def self.delete_cmd(session, arg)
      if blank?(arg)
        session.clear_breakpoints
        return ['Deleted all breakpoints']
      end
      n = arg.to_i
      if n > 0 && session.remove_breakpoint(n)
        ["Deleted breakpoint ##{n}"]
      else
        ["No breakpoint ##{arg}"]
      end
    end

    def self.help_cmd(_session, arg)
      if blank?(arg)
        lines = ['Commands']
        HELP.each { |_, label, short, _| lines << "  #{label} -- #{short}" }
        return lines
      end
      name = trim(arg)
      verb = VERBS[name]
      HELP.each { |v, _, _, long| return long if v == verb }
      ["Invalid command \"#{name}\". Try \"help\"."]
    end

    def self.display_cmd(session, arg)
      return ["#{Protocol::USAGE}display <expression>"] if blank?(arg)
      n = session.add_display(arg)
      ["#{n}: #{arg}"]
    end

    def self.list_cmd(session, arg)
      loc = session.location
      return [NO_POSITION] if loc.nil?

      file, line = loc
      unless blank?(arg)
        file, line = parse_location(file, arg)
        return [INVALID_LINE] unless line && line > 0
      end
      source_listing(file, line)
    end

    def self.source_listing(file, line)
      all_lines, error = source_lines(file)
      return [error] if error
      return ["Line #{line} is out of range for #{file} (#{all_lines.size} lines)"] if line > all_lines.size

      first = line - LIST_CONTEXT
      first = 1 if first < 1
      last = line + LIST_CONTEXT
      last = all_lines.size if last > all_lines.size

      out = []
      i = first
      while i <= last
        marker = i == line ? '=>' : '  '
        out << "#{marker} #{i}  #{all_lines[i - 1]}"
        i += 1
      end
      out
    end

    # [lines, nil], or [nil, why it can't be read]. defined?(File) guards a
    # firmware build with no mruby-io linked in. Not String#lines/#each_line
    # -- mruby-string-ext, unsafe under mrbtest.
    def self.source_lines(file)
      return [nil, NO_FILESYSTEM] unless defined?(File)
      text = read_file(file)
      return [nil, "Cannot open #{file}"] if text.nil?
      [text.split("\n"), nil]
    end

    # Not File.read -- PicoRuby's picoruby-vfs File class has no such class
    # method, only the instance #read File.open yields here. nil on failure.
    def self.read_file(file)
      File.open(file) { |f| f.read }
    rescue Exception
      nil
    end

    def self.watch_cmd(session, arg)
      return list_watches(session) if blank?(arg)
      n = session.add_watch(arg)
      ["Watch #{n}: #{arg}"]
    end

    def self.list_watches(session)
      lines = []
      session.watches.each_with_index { |w, i| lines << w.numbered_line(i + 1) }
      lines.empty? ? ['No watches set'] : lines
    end

    def self.print_cmd(session, arg)
      return ["#{Protocol::USAGE}p <expression>"] if blank?(arg)
      bnd = session.binding
      return [Protocol::NO_BINDING] if bnd.nil?
      begin
        [bnd.eval(arg).inspect]
      rescue Exception => e
        # Exception, not StandardError: a bad expression can raise SyntaxError.
        ["#{Protocol::EVAL_ERROR}#{MRDebug.error_text(e)}"]
      end
    end

    # `info` / `info locals`: the selected frame's locals, "name = value"
    # each (DapBridge's `variables` splits on the first " = ").
    def self.info_cmd(session, arg)
      sub = blank?(arg) ? 'locals' : trim(arg)
      return ["Unknown info subcommand: #{sub}"] unless sub == 'locals' || sub == 'l'
      bnd = session.binding
      return [Protocol::NO_BINDING] if bnd.nil?

      names = bnd.local_variables.select { |name| local_name?(name.to_s) }
      return ['No local variables'] if names.empty?
      names.map { |name| "#{name} = #{inspect_local(bnd, name)}" }
    end

    # PicoRuby's compiler lists hidden locals too (an empty name, for one),
    # which local_variable_get then rejects -- keep only names a script
    # could have written: a-z, _ or non-ASCII first.
    def self.local_name?(str)
      return false if str.empty?
      lower?(str[0]) || str[0] == '_' || str.getbyte(0) >= 0x80
    end

    def self.inspect_local(bnd, name)
      bnd.local_variable_get(name).inspect
    rescue Exception => e
      "#{Protocol::EVAL_ERROR}#{MRDebug.error_text(e)}"
    end

    def self.backtrace_cmd(session, _arg)
      frames = session.backtrace
      return ['No frame information available'] if frames.empty?
      lines = []
      frames.each_with_index { |(file, line), i| lines << "##{i} #{file}:#{line}" }
      lines
    end

    # `frame` alone shows the selected frame; `frame N` selects frame N
    # (numbered as by `bt`).
    def self.frame_cmd(session, arg)
      return [NO_POSITION] if session.location.nil?
      return [frame_line(session.frame_index, session.location)] if blank?(arg)

      n = trim(arg)
      return ["Invalid frame number: #{n}"] unless digits?(n)
      loc = session.select_frame(n.to_i)
      return ["No frame ##{n}"] if loc.nil?
      [frame_line(session.frame_index, loc)]
    end

    def self.up_cmd(session, arg)
      move_frame(session, parse_count(arg))
    end

    def self.down_cmd(session, arg)
      move_frame(session, -parse_count(arg))
    end

    # up (delta > 0) moves toward callers, down (delta < 0) back toward
    # the stop. Clamped at either end, like debug gem's up/down.
    def self.move_frame(session, delta)
      return [NO_POSITION] if session.location.nil?
      from = session.frame_index
      to = from + delta
      to = 0 if to < 0
      loc = session.select_frame(to)
      while loc.nil? && to > from
        to -= 1
        loc = session.select_frame(to)
      end
      return [delta > 0 ? 'Already at the outermost frame' : 'Already at the innermost frame'] if to == from
      [frame_line(to, loc)]
    end

    def self.frame_line(n, loc)
      "##{n} #{loc[0]}:#{loc[1]}"
    end

    # Unlike list_cmd, this is the whole file, unwindowed and with no line
    # numbers -- DapBridge's `source` handling wants raw source text (a
    # remote file VS Code has no local copy of), not a human-facing listing.
    def self.cat_cmd(session, arg)
      loc = session.location
      file = blank?(arg) ? (loc && loc[0]) : trim(arg)
      return [NO_POSITION] if file.nil?
      lines, error = source_lines(file)
      error ? [error] : lines
    end
  end
end
