module MRDebug
  module CLI
    # --port/--sock-path take a value, so parsing walks argv by index
    # instead of a plain #each. Anything unrecognized lands in #invalid.
    #
    # `--open` is rdbg's flag, and makes this a launch: vscode-rdbg's
    # `launch` request, given `rdbgPath: mrdbg`, runs
    #   mrdbg --command --open --stop-at-load --host=H --port=P -- ruby app.rb
    # where --host/--port are where *it* will attach (the DAP side), not the
    # device -- so a launch moves them to dap_host/dap_port, and the device
    # address comes from the environment instead (CLI.launch_dap). With no
    # TCP debugPort it passes no --host/--port, only --sock-path=PATH (a
    # debugPort that's a path) or nothing, and attaches over a Unix socket:
    # a launch moves --sock-path to dap_sock_path the same way.
    class Options
      attr_reader :help, :version, :dap_port, :unsupported, :invalid, :color,
                  :launch, :dap_host, :dap_sock_path, :command, :util
      # CLI.connect_auto fills these in from MRDEBUG_SOCK/MRDEBUG_HOST/
      # MRDEBUG_PORT.
      attr_accessor :port, :sock_path
      attr_writer :host

      DEFAULT_HOST = '127.0.0.1'
      VALUE_FLAGS = %w[--host --port --sock-path --dap-port --color --util --serial].freeze

      def self.parse(argv)
        new(argv)
      end

      def initialize(argv)
        @help = false
        @version = false
        @host = nil
        @port = nil
        @sock_path = nil
        @dap_port = nil
        @unsupported = nil
        @invalid = nil
        @color = nil
        @launch = false
        @dap_host = DEFAULT_HOST
        @dap_sock_path = nil
        @command = []
        @util = nil

        i = 0
        while i < argv.size
          arg = argv[i]
          if arg == '--'
            @command = argv[(i + 1)..-1]
            break
          end
          name, value = split_value(arg)
          if VALUE_FLAGS.include?(name)
            unless value
              i += 1
              value = argv[i]
            end
            assign(name, value)
          else
            parse_flag(arg)
          end
          i += 1
        end

        return unless @launch
        @dap_host = host
        @dap_port = @port
        @dap_sock_path = @sock_path
        @host = nil
        @port = nil
        @sock_path = nil
      end

      def host
        @host || DEFAULT_HOST
      end

      # True when --host was given, so CLI.connect_auto leaves it alone
      # rather than reading MRDEBUG_HOST.
      def host_given?
        !@host.nil?
      end

      private

      # `--flag=value` -> [flag, value], else [arg, nil]: rdbg passes
      # --host=/--port=/--sock-path= this way, so either spelling works.
      def split_value(arg)
        eq = arg.index('=')
        return [arg, nil] unless eq && arg[0, 2] == '--'
        [arg[0, eq], arg[(eq + 1)..-1]]
      end

      def parse_flag(arg)
        case arg
        when '--help', '-h'
          @help = true
        when '--version'
          @version = true
        when '--open', '-O'
          @launch = true
        when '--command', '--stop-at-load'
          # rdbg's; a launch never starts the program itself.
        else
          @invalid ||= arg
        end
      end

      def assign(name, value)
        case name
        when '--host' then @host = value
        when '--port' then @port = value.to_i
        when '--sock-path' then @sock_path = value
        when '--dap-port' then @dap_port = value.to_i
        when '--color' then @color = value
        when '--util' then @util = value
        when '--serial' then @unsupported ||= name
        end
      end
    end
  end
end
