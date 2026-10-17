module MRDebug
  # Adds ANSI colors to the (mrdbg) text a device sends, on the *host*
  # side only: the device and Command output stay plain, because DapBridge
  # parses that text and a non-TTY reader must never see escapes.
  #
  # #feed takes arbitrary chunks (a socket read can split a line); it colors
  # each complete line and holds the partial tail back, except for the
  # prompt, which never ends in a newline and is colored as soon as whole.
  class Colorizer
    RESET = "\e[0m".freeze
    BOLD_GREEN = "\e[1;32m".freeze
    BOLD_YELLOW = "\e[1;33m".freeze
    BOLD_CYAN = "\e[1;36m".freeze
    GREEN = "\e[32m".freeze
    RED = "\e[31m".freeze
    CYAN = "\e[36m".freeze
    DIM = "\e[2m".freeze
    ERROR_PREFIXES = [Protocol::EVAL_ERROR, 'Invalid ', 'Cannot open ', 'Unknown ', Protocol::USAGE, 'No frame '].freeze

    # mode: 'always' / 'never' / anything else (auto: a TTY, unless
    # NO_COLOR is set or TERM is dumb). nil falls back to MRDEBUG_COLOR.
    def self.enabled?(io, mode = nil)
      mode ||= env('MRDEBUG_COLOR')
      return true if mode == 'always'
      return false if mode == 'never'
      return false if env('NO_COLOR') || env('TERM') == 'dumb'
      io.respond_to?(:tty?) && io.tty?
    end

    def self.env(name)
      value = defined?(ENV) ? ENV[name] : nil
      value && !value.empty? ? value : nil
    end

    def self.prefix?(str, prefix)
      str[0, prefix.size] == prefix
    end

    # One line, no newline. Unrecognized lines pass through unchanged.
    def self.colorize_line(line)
      list = list_line(line)
      return list if list
      if ERROR_PREFIXES.any? { |p| prefix?(line, p) }
        "#{RED}#{line}#{RESET}"
      elsif prefix?(line, Protocol::STOP)
        "#{BOLD_CYAN}#{line}#{RESET}"
      elsif prefix?(line, Protocol::BREAKPOINT) || prefix?(line, Protocol::WATCHPOINT)
        breakpoint_line(line)
      elsif prefix?(line, '#') && frame_number_end(line)
        n = frame_number_end(line)
        "#{CYAN}#{line[0, n]}#{RESET}#{line[n..-1]}"
      else
        line
      end
    end

    # "Breakpoint 1: f.rb:3" is a stop; "Breakpoint 1 added at ..." is a reply.
    def self.breakpoint_line(line)
      i = line.index(' ') + 1
      i += 1 while Command.digit?(line[i])
      color = line[i] == ':' ? BOLD_YELLOW : GREEN
      "#{color}#{line}#{RESET}"
    end

    # "#12 file:line" (bt/frame): the index of the space after "#<digits>".
    def self.frame_number_end(line)
      i = 1
      i += 1 while Command.digit?(line[i])
      i > 1 && line[i] == ' ' ? i : nil
    end

    # "=> 12  code" / "   12  code" (list): marker, dim number, highlighted code.
    def self.list_line(line)
      marker = line[0, 2]
      return nil unless (marker == '=>' || marker == '  ') && line[2] == ' '
      i = 3
      i += 1 while Command.digit?(line[i])
      return nil if i == 3 || line[i, 2] != '  '
      head = marker == '=>' ? "#{BOLD_GREEN}=>#{RESET}" : marker
      "#{head} #{DIM}#{line[3, i - 3]}#{RESET}  #{RubyHighlighter.highlight(line[(i + 2)..-1])}"
    end

    def initialize
      @buf = ''
    end

    def feed(chunk)
      @buf += chunk
      out = []
      while (nl = @buf.index("\n"))
        line = @buf[0, nl]
        @buf = @buf[(nl + 1)..-1]
        cr = line[-1] == "\r" ? "\r" : ''
        line = line[0, line.size - 1] unless cr.empty?
        out << self.class.colorize_line(line) << cr << "\n"
      end
      if @buf == Protocol::PROMPT
        out << "#{BOLD_GREEN}#{Protocol::PROMPT}#{RESET}"
        @buf = ''
      end
      out.join
    end

    # Whatever partial line is still held (the stream ended mid-line).
    def finish
      rest = @buf
      @buf = ''
      rest
    end
  end
end
