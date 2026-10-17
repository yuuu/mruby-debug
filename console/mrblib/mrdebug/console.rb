require 'editor'
require 'io/console'

module MRDebug
  module UI
    # The (mrdbg) prompt read directly off the device's own console (raw
    # STDIN/STDOUT via picoruby-io-console), using picoruby-editor's
    # Editor::Line for line editing/history -- the on-device counterpart to
    # LocalConsole (tools/mrdebug/ui/local_console.rb), which is Transport-
    # driven and host-only.
    class Console < Base
      def initialize
        # On by default (a serial terminal can't be probed for ANSI support,
        # so there is no TTY check); MRDEBUG_COLOR=never or NO_COLOR turns it
        # off. The prompt itself stays plain: Editor::Line sizes it by
        # character count.
        mode = Colorizer.env('MRDEBUG_COLOR')
        @color = mode == 'always' || (mode != 'never' && Colorizer.env('NO_COLOR').nil?)
        @editor = Class.new(Editor::Line) do
          def initialize
            @height, @width = 24, 80
            @buffer = Editor::Buffer.new
            @history = [[""]]
            @history_index = 0
            @prev_cursor_y = 0
            self.prompt = Protocol::PROMPT
          end
        end.new
      end

      def on_stop(session)
        say session.stop_banner
        session.display_lines.each { |expr, result| say "#{expr} = #{result}" }

        prev_term = ENV['TERM']
        ENV['TERM'] = 'dumb'
        STDIN.raw!
        @editor.start do |editor, buffer, c|
          case c
          when 10, 13 # Enter
            line = buffer.dump.chomp
            editor.feed_at_bottom
            editor.save_history
            buffer.clear
            output, action = Command.dispatch(session, line)
            output.each { |l| say l }
            break if action == :resume
          end
        end
      ensure
        STDIN.cooked!
        ENV['TERM'] = prev_term
      end

      private

      def say(line)
        puts @color ? Colorizer.colorize_line(line) : line
      end
    end
  end

  # Replaces tools/mrdebug/device.rb's attach_local (this gem loads later,
  # as a dependent): what MRDEBUG_PORT=console selects on a device.
  def self.attach_local
    session = Session.new
    session.ui = UI::Console.new
    self.session = session
    session
  end
end
