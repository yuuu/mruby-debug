module MRDebug
  module CLI
    # `transport` is the CLI's own I/O (Stdio by default, swappable for a
    # Loopback in tests); --port/--sock-path hand off to #relay instead,
    # which talks to real STDIN/STDOUT directly. Returns false when it
    # couldn't do what was asked (a failed connection, an unsupported
    # flag), which the `mrdbg` binary turns into a nonzero exit status --
    # what lets a VS Code preLaunchTask notice the bridge never came up.
    def self.start(argv, transport = MRDebug::Transport::Stdio.new)
      options = Options.parse(argv)

      if options.help
        transport.write("#{usage}\n")
      elsif options.version
        transport.write("mrdbg #{MRDebug::VERSION}\n")
      elsif options.util
        return util(options.util, transport)
      elsif options.launch
        return launch_dap(options, transport)
      elsif options.port && options.dap_port
        return connect_dap(options, transport)
      elsif options.port
        return connect_tcp(options, transport)
      elsif options.sock_path
        return connect_unix(options, transport) if defined?(UNIXSocket)
        transport.write("#{unsupported_message('--sock-path')}\n")
        return false
      elsif options.unsupported
        transport.write("#{unsupported_message(options.unsupported)}\n")
        return false
      elsif options.invalid
        transport.write("mrdbg: unknown argument: #{options.invalid}\n#{usage}\n")
        return false
      else
        return connect_auto(options, transport)
      end
      true
    end

    # No --port/--sock-path: MRDEBUG_SOCK, else MRDEBUG_HOST:MRDEBUG_PORT
    # (127.0.0.1, 4711 by default). An explicit --host wins over
    # MRDEBUG_HOST, and --color still applies.
    def self.connect_auto(options, transport)
      sock = MRDebug.default_sock
      if sock
        options.sock_path = sock
        connect_unix(options, transport)
      else
        options.host = default_host unless options.host_given?
        options.port = MRDebug.default_port
        connect_tcp(options, transport)
      end
    end

    def self.default_host
      MRDebug.env_value('MRDEBUG_HOST') || Options::DEFAULT_HOST
    end

    def self.usage
      "Usage: mrdbg [options]\n" \
      "  (no args)         connect to MRDEBUG_SOCK, else MRDEBUG_HOST (127.0.0.1):\n" \
      "                     MRDEBUG_PORT (#{MRDebug::DEFAULT_PORT})\n" \
      "  --port PORT        connect to a device listening on 127.0.0.1:PORT\n" \
      "  --host HOST --port PORT   connect to a device listening on HOST:PORT\n" \
      "                     (e.g. a real board's IP over WiFi; default HOST is 127.0.0.1)\n" \
      "  --sock-path PATH   connect to a device listening on a Unix socket\n" \
      "  --port PORT --dap-port DAP_PORT   bridge a DAP client (e.g. VS Code's\n" \
      "                     vscode-rdbg, attach) on DAP_PORT to a device on PORT\n" \
      "  --open [--port=DAP_PORT | --sock-path=PATH]   the same, run by vscode-rdbg's\n" \
      "                     launch (rdbgPath), on a Unix socket unless given a port;\n" \
      "                     the device is found as with no args\n" \
      "  --color auto|always|never   color the output (default auto: only on a TTY;\n" \
      "                     NO_COLOR disables, MRDEBUG_COLOR sets the default)\n" \
      "  --serial DEV       (not supported yet)\n" \
      '  --help, --version'
    end

    def self.unsupported_message(flag)
      if flag == '--sock-path'
        '--sock-path: not supported on this build -- no UNIXSocket. Use --port instead.'
      else
        "#{flag}: not supported yet -- no serial transport exists. Use --port " \
        'or --sock-path against a device that called MRDebug.listen_tcp/listen_unix.'
      end
    end

    def self.connect_tcp(options, transport)
      connect_and_relay("#{options.host}:#{options.port}", options, transport) do
        MRDebug::Transport::TCP.connect(options.host, options.port)
      end
    end

    def self.connect_unix(options, transport)
      connect_and_relay(options.sock_path, options, transport) do
        MRDebug::Transport::Unix.connect(options.sock_path)
      end
    end

    # Connects via the block (to `target`, for messages) and relays until
    # the device closes. False if the connection failed.
    def self.connect_and_relay(target, options, transport)
      remote = yield
      transport.write("Connected to #{target}\n")
      relay(remote.io, transport, STDIN, STDOUT, colorizer_for(options))
      true
    rescue => e
      transport.write("connect #{target} failed: #{MRDebug.error_text(e)}\n")
      false
    ensure
      remote.close if remote
    end

    # Bridges a DAP client (VS Code's vscode-rdbg, attach) on options.dap_port
    # to a device already listening on options.host:options.port
    # (MRDebug.listen_tcp). Blocks the whole session (one DAP client,
    # matching vscode-rdbg's typical single attach).
    def self.connect_dap(options, transport)
      dap_port = options.dap_port
      link = MRDebug::Transport::TCP.connect(options.host, options.port)
      serve_dap(link, "#{options.host}:#{options.port}", -> { TCPServer.new('0.0.0.0', dap_port) }, transport) do
        transport.write("DAP bridge listening on #{options.dap_port}; waiting for a client to attach...\n")
      end
      true
    rescue => e
      transport.write("dap bridge failed: #{MRDebug.error_text(e)}\n")
      false
    end

    # The same bridge, run by vscode-rdbg's `launch` with `rdbgPath` set to
    # mrdbg (see Options): the device is found as `mrdbg` with no args finds
    # it (launch.json's `env`), and readiness is rdbg's two stderr lines,
    # which vscode-rdbg waits for before attaching to the address the first
    # one names. It also gives up on any stderr containing "Error", showing
    # it to the user -- so failures are reported that way.
    #
    # The DAP side is TCP when launch.json's debugPort is a port, else a
    # Unix socket: the path debugPort names (--sock-path), or, with no
    # debugPort at all (vscode-rdbg's default off Windows), a fresh one.
    def self.launch_dap(options, transport, err = STDERR)
      bound = nil # the socket file, once created, to remove on the way out
      if options.dap_port
        unless options.dap_port > 0
          report(err, 'Error: mrdbg needs a fixed TCP port in launch.json\'s debugPort (e.g. "localhost:12345")')
          return false
        end
        dap_port = options.dap_port
        listen = -> { TCPServer.new('0.0.0.0', dap_port) }
        via = "TCP/IP (#{options.dap_host}:#{dap_port})"
      else
        unless defined?(UNIXServer)
          report(err, 'Error: mrdbg needs a TCP debugPort in launch.json (e.g. "localhost:12345"): ' \
                      'no Unix sockets on this build')
          return false
        end
        sock = options.dap_sock_path || gen_sock_path
        listen = lambda do
          server = UNIXServer.new(sock)
          bound = sock
          server
        end
        via = "UNIX domain socket (#{sock})"
      end
      unless options.command.empty?
        transport.write("mrdbg: not running `#{options.command.join(' ')}` -- " \
                        "the program must already be waiting in binding.debugger\n")
      end
      link, where = connect_device
      serve_dap(link, where, listen, transport) do
        report(err, "DEBUGGER: Debugger can attach via #{via}")
        report(err, 'DEBUGGER: wait for debugger connection...')
      end
      true
    rescue => e
      report(err, "Error: mrdbg could not bridge to the device: #{MRDebug.error_text(e)}")
      false
    ensure
      File.delete(bound) if bound && File.exist?(bound)
    end

    # A Unix socket path nothing uses yet, for the DAP side -- like rdbg's
    # own, in XDG_RUNTIME_DIR, else TMPDIR, else /tmp. Also printed by
    # `--util=gen-sockpath`, which vscode-rdbg runs first when launching
    # into a terminal (`useTerminal`).
    def self.gen_sock_path
      dir = MRDebug.env_value('XDG_RUNTIME_DIR') || MRDebug.env_value('TMPDIR') || '/tmp'
      dir = dir[0, dir.size - 1] if dir.size > 1 && dir[-1] == '/'
      pid = defined?(Process) && Process.respond_to?(:pid) ? Process.pid : 0
      base = "#{dir}/mrdbg-#{pid}"
      path = base
      n = 0
      while File.exist?(path)
        n += 1
        path = "#{base}-#{n}"
      end
      path
    end

    # rdbg's `--util=NAME` helpers that vscode-rdbg runs; only gen-sockpath.
    def self.util(name, transport)
      if name == 'gen-sockpath'
        transport.write("#{gen_sock_path}\n")
        return true
      end
      transport.write("--util=#{name}: not supported\n")
      false
    end

    # [link, description] for MRDEBUG_SOCK, else MRDEBUG_HOST:MRDEBUG_PORT.
    def self.connect_device
      sock = MRDebug.default_sock
      return [MRDebug::Transport::Unix.connect(sock), sock] if sock
      host = default_host
      port = MRDebug.default_port
      [MRDebug::Transport::TCP.connect(host, port), "#{host}:#{port}"]
    end

    # Waits for the device's entry stop, opens the DAP listener (`listen`,
    # returning a TCPServer or UNIXServer), yields (to announce that it's
    # ready), then serves one DAP client.
    def self.serve_dap(link, where, listen, transport)
      device = DeviceLink.new(link.io)
      transport.write("Connected to device at #{where}\n")
      device.wait_for_entry
      server = DapServer.new(device, listen.call)
      yield
      server.run
      transport.write("(dap session ended)\n")
    ensure
      link.close
    end

    def self.report(io, line)
      io.write("#{line}\n")
      io.flush if io.respond_to?(:flush)
    end

    def self.colorizer_for(options, out = STDOUT)
      MRDebug::Colorizer.enabled?(out, options.color) ? MRDebug::Colorizer.new : nil
    end

    # Raw byte pump (the device's prompt has no trailing newline, so
    # #gets would block forever). Stops watching local_in on EOF rather
    # than ending the relay -- only the device closing its end does that.
    def self.relay(remote_io, transport, local_in = STDIN, local_out = STDOUT, colorizer = nil)
      local_open = true
      loop do
        watch = local_open ? [remote_io, local_in] : [remote_io]
        ready, = IO.select(watch)
        next unless ready
        if ready.include?(remote_io)
          drain(remote_io, local_out, colorizer)
        end
        if local_open && ready.include?(local_in)
          begin
            remote_io.write(MRDebug::Transport.read_some(local_in))
          rescue EOFError
            local_open = false
          end
        end
      end
    rescue EOFError
      local_out.write(colorizer.finish) if colorizer
      transport.write("\n(connection closed)\n")
    end

    # A ready select() doesn't mean one read drains it all.
    def self.drain(io, out, colorizer = nil)
      loop do
        chunk = MRDebug::Transport.read_some(io)
        out.write(colorizer ? colorizer.feed(chunk) : chunk)
        out.flush
        break unless IO.select([io], nil, nil, 0)
      end
    end
  end
end
