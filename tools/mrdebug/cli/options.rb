module MRDebug
  module CLI
    # --port/--sock-path take a value, so parsing walks argv by index
    # instead of a plain #each.
    #
    # `--open` is rdbg's flag, and makes this a launch: vscode-rdbg's
    # `launch` request, given `rdbgPath: mrdbg`, runs
    #   mrdbg --command --open --stop-at-load --host=H --port=P -- ruby app.rb
    # where --host/--port are where *it* will attach (the DAP side), not the
    # device -- so a launch moves them to dap_host/dap_port, and the device
    # address comes from the environment instead (CLI.launch_dap).
    class Options
      attr_reader :file, :line, :help, :version, :host, :port, :sock_path, :dap_port, :unsupported, :color,
                  :launch, :dap_host, :command

      DEFAULT_HOST = '127.0.0.1'
      VALUE_FLAGS = %w[--host --port --sock-path --dap-port --color].freeze

      def self.parse(argv)
        new(argv)
      end

      def initialize(argv)
        @file = '(remote)'
        @line = 1
        @help = false
        @version = false
        @host = DEFAULT_HOST
        @port = nil
        @sock_path = nil
        @dap_port = nil
        @unsupported = nil
        @color = nil
        @launch = false
        @dap_host = DEFAULT_HOST
        @command = []

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
        @dap_host = @host
        @dap_port = @port
        @host = DEFAULT_HOST
        @port = nil
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
        when '--serial'
          @unsupported ||= arg
        else
          @file, @line = parse_location(arg) unless arg[0, 1] == '-'
        end
      end

      def assign(name, value)
        case name
        when '--host' then @host = value
        when '--port' then @port = value.to_i
        when '--sock-path' then @sock_path = value
        when '--dap-port' then @dap_port = value.to_i
        when '--color' then @color = value
        end
      end

      # `[<file>:]<line>`
      def parse_location(arg)
        colon = arg.rindex(':')
        return [arg, 1] unless colon
        [arg[0, colon], arg[(colon + 1)..-1].to_i]
      end
    end
  end
end
