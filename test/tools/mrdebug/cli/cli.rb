assert('CLI::Options flags an unrecognized argument as invalid') do
  options = MRDebug::CLI::Options.parse(['foo.rb:42'])
  assert_equal 'foo.rb:42', options.invalid
  assert_false options.help
  assert_false options.version
  assert_nil options.unsupported
  assert_nil MRDebug::CLI::Options.parse([]).invalid
  assert_equal '--bogus', MRDebug::CLI::Options.parse(['--bogus']).invalid
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

assert('CLI.start rejects an unknown argument with usage, no Session') do
  transport = MRDebug::Transport::Loopback.new
  assert_false MRDebug::CLI.start(['foo.rb:10'], transport)
  out = transport.output.join
  assert_true out.include?('unknown argument: foo.rb:10')
  assert_true out.include?('Usage: mrdbg')
end

assert('CLI.start --version prints the gem version') do
  transport = MRDebug::Transport::Loopback.new
  assert_true MRDebug::CLI.start(['--version'], transport)
  assert_equal "mrdbg #{MRDebug::VERSION}\n", transport.output.join
end

assert('CLI::Options parses --color in both spellings') do
  assert_equal 'always', MRDebug::CLI::Options.parse(['--color', 'always']).color
  assert_equal 'never', MRDebug::CLI::Options.parse(['--color=never']).color
  assert_nil MRDebug::CLI::Options.parse([]).color
end
