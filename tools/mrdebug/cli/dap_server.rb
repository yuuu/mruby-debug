module MRDebug
  module CLI
    # Bridges a Content-Length-framed DAP client (e.g. vscode-rdbg's
    # "attach", pointed at this server's port) to a device already
    # connected via DeviceLink's plain-text (mrdbg) protocol. Route (b) from
    # the design notes: no JSON/DAP ever reaches the device, only this
    # host-side process speaks it. One client at a time; #run blocks for
    # its whole lifetime.
    class DapServer
      CONTENT_LENGTH = 'Content-Length: '.freeze
      HEADER_END = "\r\n\r\n".freeze

      # `server` is a bound TCPServer or UNIXServer; #run closes it once a
      # client is accepted.
      def initialize(device, server)
        @device = device
        @bridge = DapBridge.new(device)
        @server = server
      end

      def run
        client = @server.accept
        @server.close
        @out = MRDebug::Transport::Socket.new(client)
        @client_gone = false
        @buf = ''
        loop do
          drain_device_stops(client)
          ready, = IO.select([client, @device.io])
          next unless ready
          if ready.include?(@device.io) && !handle_device(client)
            # The device closed the connection: its program ended (or it
            # went away), so this debug session is over too.
            write_message(@bridge.terminated_notification)
            break
          end
          break if ready.include?(client) && !handle_client(client)
          break if @client_gone
        end
      ensure
        client.close if client
      end

      private

      # Any response chunk already fully buffered on the device side (e.g.
      # queued up while we were busy) is drained before the next select,
      # so a stop already sitting in the buffer isn't missed.
      def drain_device_stops(client)
        while @device.chunk_ready?
          send_stop(client) if @device.try_extract
        end
      end

      # Returns false on EOF (device connection closed).
      def handle_device(client)
        lines = @device.poll
        send_stop(client) if lines
        true
      rescue EOFError
        false
      end

      # Returns false on EOF (client disconnected).
      def handle_client(client)
        @buf += Transport.read_some(client)
        loop do
          msg, rest = extract_message(@buf)
          break unless msg
          @buf = rest
          request = Json.parse(msg)
          @bridge.handle(request).each { |m| write_message(m) }
        end
        true
      rescue EOFError
        false
      end

      def send_stop(client)
        @bridge.stop_messages(@device.stopped_by).each { |m| write_message(m) }
      end

      # Through Transport::Socket for its MSG_NOSIGNAL: VS Code closes its
      # end right after `disconnect`, and the device's EOF that follows
      # still sends `terminated` -- a plain write there is a SIGPIPE, which
      # would kill the bridge before it cleans up (e.g. its socket file).
      def write_message(msg)
        body = Json.generate(msg)
        @out.write("#{CONTENT_LENGTH}#{body.size}\r\n\r\n#{body}")
      rescue SystemCallError
        @client_gone = true
      end

      # [message_body, remaining_buf], or [nil, buf] if not fully buffered.
      def extract_message(buf)
        header_end = buf.index(HEADER_END)
        return [nil, buf] unless header_end
        len = content_length(buf[0, header_end])
        return [nil, buf] unless len
        body_start = header_end + HEADER_END.size
        return [nil, buf] if buf.size < body_start + len
        [buf[body_start, len], buf[(body_start + len)..-1]]
      end

      def content_length(header)
        idx = header.index(CONTENT_LENGTH)
        return nil unless idx
        rest = header[(idx + CONTENT_LENGTH.size)..-1]
        eol = rest.index("\r\n") || rest.size
        rest[0, eol].to_i
      end
    end
  end
end
