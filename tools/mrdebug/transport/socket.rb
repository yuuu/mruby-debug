module MRDebug
  module Transport
    # #sysread avoids an ESPIPE from #write's internal lseek; picoruby-socket
    # only has #readpartial. Writes go through send(MSG_NOSIGNAL) where
    # mruby-socket has it: a plain write to a peer-closed socket raises
    # SIGPIPE on POSIX, killing the debuggee instead of raising EPIPE.
    # picoruby-socket has no such flag (its POSIX port still gets SIGPIPE;
    # lwIP on a device has no signals).
    class Socket < Base
      attr_reader :io

      def initialize(io)
        @io = io
        @buf = ''
        @read_method = io.respond_to?(:sysread) ? :sysread : :readpartial
        @send_flags = nosignal_flags(io)
      end

      def gets
        loop do
          nl = @buf.index("\n")
          if nl
            line = @buf[0, nl]
            @buf = @buf[(nl + 1)..-1]
            return strip_eol(line)
          end
          @buf += @io.__send__(@read_method, 4096)
        end
      rescue EOFError
        return nil if @buf.empty?
        line = @buf
        @buf = ''
        strip_eol(line)
      end

      def write(str)
        @send_flags ? @io.send(str, @send_flags) : @io.write(str)
      end

      def close
        @io.close
      end

      def detach_on_close?
        true
      end

      private

      # Not io.respond_to?(:send) -- every object has Kernel#send.
      def nosignal_flags(io)
        return nil unless defined?(::Socket) && ::Socket.const_defined?(:MSG_NOSIGNAL)
        return nil unless defined?(::BasicSocket) && io.is_a?(::BasicSocket)
        ::Socket::MSG_NOSIGNAL
      end
    end

    class TCP < Socket
      def self.listen(port, host = '0.0.0.0')
        server = TCPServer.new(host, port)
        io = server.accept
        server.close
        new(io)
      end

      def self.connect(host, port)
        new(TCPSocket.new(host, port))
      end
    end

    class Unix < Socket
      def self.listen(path)
        File.delete(path) if File.exist?(path)
        server = UNIXServer.new(path)
        io = server.accept
        server.close
        new(io)
      end

      def self.connect(path)
        new(UNIXSocket.new(path))
      end
    end
  end
end
