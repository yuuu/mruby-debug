module MRDebug
  module UI
    # The (mrdbg) prompt, driven by a Transport -- avoids the old
    # picoruby-editor multi-command-in-one-read bug by construction.
    class LocalConsole < Base
      def initialize(transport = Transport::Stdio.new)
        @transport = transport
      end

      def on_stop(session)
        return lost(session) unless say("#{session.stop_banner}\n")
        session.display_lines.each do |expr, result|
          return lost(session) unless say("#{expr} = #{result}\n")
        end
        loop do
          return lost(session) unless say('(mrdbg) ')
          line = hear
          return lost(session) if line.nil?
          output, action = Command.dispatch(session, line)
          output.each { |l| return lost(session) unless say("#{l}\n") }
          return if action == :resume
        end
      end

      private

      # I/O failures (EPIPE, a reset connection, ...) mean the client is
      # gone, same as EOF -- never an error to raise into the debuggee.
      def say(str)
        @transport.write(str)
        true
      rescue StandardError
        false
      end

      def hear
        @transport.gets
      rescue StandardError
        nil
      end

      # The client is gone: resume and let the script run on. A socket
      # transport also ends the session (MRDebug.detach), so the next
      # binding.debugger waits for a new client instead of finding this
      # dead one again.
      def lost(session)
        return unless @transport.detach_on_close?
        begin
          @transport.close
        rescue StandardError
          nil
        end
        MRDebug.detach(session)
        nil
      end
    end
  end
end
