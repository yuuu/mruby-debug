module MRDebug
  module CLI
    # --port/--sock-path take a value, so parsing walks argv by index
    # instead of a plain #each. Anything unrecognized lands in #invalid.
    class Options
      attr_reader :help, :version, :host, :dap_port, :unsupported, :invalid, :color
      # CLI.connect_auto fills one of these in from MRDEBUG_SOCK/MRDEBUG_PORT.
      attr_accessor :port, :sock_path

      DEFAULT_HOST = '127.0.0.1'

      def self.parse(argv)
        new(argv)
      end

      def initialize(argv)
        @help = false
        @version = false
        @host = DEFAULT_HOST
        @port = nil
        @sock_path = nil
        @dap_port = nil
        @unsupported = nil
        @invalid = nil
        @color = nil

        i = 0
        while i < argv.size
          arg = argv[i]
          case arg
          when '--help', '-h'
            @help = true
          when '--version'
            @version = true
          when '--host'
            i += 1
            @host = argv[i]
          when '--port'
            i += 1
            @port = argv[i].to_i
          when '--sock-path'
            i += 1
            @sock_path = argv[i]
          when '--dap-port'
            i += 1
            @dap_port = argv[i].to_i
          when '--color'
            i += 1
            @color = argv[i]
          when '--serial'
            i += 1
            @unsupported ||= arg
          when '--open', '-O'
            @unsupported ||= arg
          else
            if arg[0, 8] == '--color='
              @color = arg[8..-1]
            else
              @invalid ||= arg
            end
          end
          i += 1
        end
      end
    end
  end
end
