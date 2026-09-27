module MRDebug
  module Transport
    # The (mrdbg) prompt's I/O contract -- not a wire protocol (DAP, rdbg, ...).
    class Base
      def gets
        raise NotImplementedError, "#{self.class} must implement #gets"
      end

      def write(str)
        raise NotImplementedError, "#{self.class} must implement #write"
      end

      def close
      end

      # Whether losing the peer should end the session (MRDebug.detach), so
      # the next binding.debugger can take a new one. True for a listening
      # socket; false for stdio, where EOF just means the input ran out.
      def detach_on_close?
        false
      end

      protected

      # Not String#chomp -- mruby-string-ext misbehaves under mrbtest.
      def strip_eol(line)
        len = line.size
        len -= 1 if len > 0 && line[len - 1] == "\n"
        len -= 1 if len > 0 && line[len - 1] == "\r"
        line[0, len]
      end
    end
  end
end
