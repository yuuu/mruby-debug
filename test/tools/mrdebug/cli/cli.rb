assert('CLI::Options parses a bare file:line') do
  options = MRDebug::CLI::Options.parse(['foo.rb:42'])
  assert_equal 'foo.rb', options.file
  assert_equal 42, options.line
  assert_false options.help
  assert_false options.version
  assert_nil options.unsupported
end

assert('CLI::Options defaults file/line when none is given') do
  options = MRDebug::CLI::Options.parse([])
  assert_equal '(remote)', options.file
  assert_equal 1, options.line
end

assert('CLI::Options treats a location with no colon as line 1') do
  options = MRDebug::CLI::Options.parse(['just_a_file.rb'])
  assert_equal 'just_a_file.rb', options.file
  assert_equal 1, options.line
end

assert('CLI::Options recognizes --help/--version') do
  assert_true MRDebug::CLI::Options.parse(['--help']).help
  assert_true MRDebug::CLI::Options.parse(['-h']).help
  assert_true MRDebug::CLI::Options.parse(['--version']).version
end

assert('CLI::Options flags a connection flag as unsupported') do
  assert_equal '--serial', MRDebug::CLI::Options.parse(['--serial', '/dev/ttyUSB0']).unsupported
  assert_nil MRDebug::CLI::Options.parse(['--serial', '/dev/ttyUSB0']).port
end

assert('CLI::Options parses --port') do
  options = MRDebug::CLI::Options.parse(['--port', '4711'])
  assert_equal 4711, options.port
  assert_nil options.unsupported
end

assert('CLI::Options parses --sock-path') do
  options = MRDebug::CLI::Options.parse(['--sock-path', '/tmp/mrdebug.sock'])
  assert_equal '/tmp/mrdebug.sock', options.sock_path
  assert_nil options.unsupported
end

assert('CLI.start --help writes usage and never opens a Session') do
  transport = MRDebug::Transport::Loopback.new
  assert_true MRDebug::CLI.start(['--help'], transport)
  assert_equal 1, transport.output.size
  assert_true transport.output[0].include?('Usage: mrdbg')
ensure
  MRDebug::Hook.uninstall
end

assert('CLI.start with a connection flag reports it as unsupported, no Session') do
  transport = MRDebug::Transport::Loopback.new
  assert_false MRDebug::CLI.start(['--serial', '/dev/ttyUSB0'], transport)
  assert_equal 1, transport.output.size
  assert_true transport.output[0].include?('not supported yet')
ensure
  MRDebug::Hook.uninstall
end

assert('CLI.start --port reports a connection failure instead of stalling on stdin') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  server.close # nothing listens at `port` from here on

  transport = MRDebug::Transport::Loopback.new
  assert_false MRDebug::CLI.start(['--port', port.to_s], transport)

  out = transport.output.join
  assert_true out.include?("connect 127.0.0.1:#{port} failed")
end

assert('CLI.start --sock-path reports a connection failure instead of stalling on stdin') do
  transport = MRDebug::Transport::Loopback.new
  assert_false MRDebug::CLI.start(['--sock-path', '/tmp/mrdebug-cli-test-no-such.sock'], transport)

  out = transport.output.join
  assert_true out.include?('connect /tmp/mrdebug-cli-test-no-such.sock failed')
end

assert('CLI.start with no args auto-connects to MRDEBUG_PORT and reports failure instead of stalling') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  server.close # nothing listens at `port` from here on

  saved_port = ENV['MRDEBUG_PORT']
  saved_sock = ENV['MRDEBUG_SOCK']
  ENV.delete('MRDEBUG_SOCK')
  ENV['MRDEBUG_PORT'] = port.to_s

  transport = MRDebug::Transport::Loopback.new
  assert_false MRDebug::CLI.start([], transport)

  out = transport.output.join
  assert_true out.include?("connect 127.0.0.1:#{port} failed")
ensure
  if saved_port.nil? then ENV.delete('MRDEBUG_PORT') else ENV['MRDEBUG_PORT'] = saved_port end
  if saved_sock.nil? then ENV.delete('MRDEBUG_SOCK') else ENV['MRDEBUG_SOCK'] = saved_sock end
  MRDebug::Hook.uninstall
end

assert('CLI.start --port --dap-port reports a failure to reach the device as false') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  server.close # nothing listens at `port` from here on

  transport = MRDebug::Transport::Loopback.new
  assert_false MRDebug::CLI.start(['--port', port.to_s, '--dap-port', '0'], transport)
  assert_true transport.output.join.include?('dap bridge failed')
end

assert('CLI.start with no args runs a demo session against RemoteSession end to end') do
  transport = MRDebug::Transport::Loopback.new(['print 1 + 1', 'continue'])
  MRDebug::CLI.start(['foo.rb:10'], transport)

  out = transport.output.join
  assert_true out.include?('Stop: foo.rb:10')
  assert_true out.include?('2')
  assert_true out.include?('session ended')
ensure
  MRDebug::Hook.uninstall
end

assert('CLI.start demo session resumes on step/next same as a real Session would') do
  transport = MRDebug::Transport::Loopback.new(['n'])
  MRDebug::CLI.start(['foo.rb:1'], transport)
  assert_true transport.output.join.include?('session ended')
ensure
  MRDebug::Hook.uninstall
end

assert('CLI.run_demo_session wires RemoteSession, not the Session, into LocalConsole') do
  transport = MRDebug::Transport::Loopback.new(['continue'])
  MRDebug::CLI.run_demo_session(MRDebug::CLI::Options.new(['x.rb:5']), transport)
  assert_true transport.output.join.include?('Stop: x.rb:5')
ensure
  MRDebug::Hook.uninstall
end

assert('CLI::Options parses --color in both spellings') do
  assert_equal 'always', MRDebug::CLI::Options.parse(['--color', 'always']).color
  assert_equal 'never', MRDebug::CLI::Options.parse(['--color=never']).color
  assert_nil MRDebug::CLI::Options.parse([]).color
end

assert('CLI::Options accepts --flag=value for flags that take a value') do
  options = MRDebug::CLI::Options.parse(['--host=10.0.0.2', '--port=4712', '--dap-port=12345'])
  assert_equal '10.0.0.2', options.host
  assert_equal 4712, options.port
  assert_equal 12345, options.dap_port
  assert_equal '/tmp/x.sock', MRDebug::CLI::Options.parse(['--sock-path=/tmp/x.sock']).sock_path
end

assert('CLI::Options --open (vscode-rdbg launch) takes --host/--port as the DAP side') do
  argv = ['--command', '--open', '--stop-at-load', '--host=localhost', '--port=12345',
          '--', 'ruby', 'app.rb']
  options = MRDebug::CLI::Options.parse(argv)
  assert_true options.launch
  assert_equal 'localhost', options.dap_host
  assert_equal 12345, options.dap_port
  assert_nil options.port
  assert_equal ['ruby', 'app.rb'], options.command
  assert_equal '(remote)', options.file # nothing after -- is a location
  assert_nil options.unsupported
end

def cli_test_with_env(vars)
  saved = {}
  vars.each_key { |k| saved[k] = ENV[k] }
  vars.each { |k, v| if v.nil? then ENV.delete(k) else ENV[k] = v end }
  yield
ensure
  saved.each { |k, v| if v.nil? then ENV.delete(k) else ENV[k] = v end }
end

assert('CLI.launch_dap without a TCP debugPort fails with an Error line on stderr') do
  transport = MRDebug::Transport::Loopback.new
  err = MRDebug::Transport::Loopback.new
  options = MRDebug::CLI::Options.parse(['--command', '--open', '--', 'ruby', 'app.rb'])
  assert_false MRDebug::CLI.launch_dap(options, transport, err)
  assert_equal 'Error: ', err.output.join[0, 7]
  assert_true err.output.join.include?('debugPort')
end

assert('CLI.launch_dap finds the device from MRDEBUG_HOST/MRDEBUG_PORT and reports failure as Error') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]
  server.close # nothing listens at `port` from here on

  transport = MRDebug::Transport::Loopback.new
  err = MRDebug::Transport::Loopback.new
  options = MRDebug::CLI::Options.parse(['--open', '--port=12345'])
  cli_test_with_env('MRDEBUG_SOCK' => nil, 'MRDEBUG_HOST' => '127.0.0.1', 'MRDEBUG_PORT' => port.to_s) do
    assert_false MRDebug::CLI.launch_dap(options, transport, err)
  end
  out = err.output.join
  assert_equal 'Error: ', out[0, 7]
  assert_true out.include?('could not bridge to the device')
  assert_false out.include?('DEBUGGER: wait for debugger connection')
end

assert('CLI.default_host is MRDEBUG_HOST, else 127.0.0.1') do
  cli_test_with_env('MRDEBUG_HOST' => '192.168.0.10') do
    assert_equal '192.168.0.10', MRDebug::CLI.default_host
  end
  cli_test_with_env('MRDEBUG_HOST' => nil) do
    assert_equal '127.0.0.1', MRDebug::CLI.default_host
  end
end
