
# .listen blocks on #accept in one call, so it needs a second process and
# isn't tested here. connect() against a listening backlog succeeds
# before #accept is called, so .connect and Socket#gets/#write/#close can
# be, both ends set up in order within one test.

assert('Transport::TCP.connect reaches a listening TCPServer; Socket#gets/#write round-trip over it') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]

  client = MRDebug::Transport::TCP.connect('127.0.0.1', port)
  device = MRDebug::Transport::TCP.new(server.accept)

  client.write("break foo.rb:1\n")
  assert_equal 'break foo.rb:1', device.gets

  device.write("(mrdbg) ")
  device.write("Breakpoint 1 added\n")
  assert_equal '(mrdbg) Breakpoint 1 added', client.gets
ensure
  client.close if client
  device.close if device
  server.close
end

assert('Transport::Socket#gets strips CRLF, same as Stdio') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]

  client = TCPSocket.new('127.0.0.1', port)
  device = MRDebug::Transport::TCP.new(server.accept)

  client.write("n\r\n")
  assert_equal 'n', device.gets
ensure
  client.close if client
  device.close if device
  server.close
end

assert('Transport::Socket#write does not choke on bytes #gets already buffered ahead (regression: Errno::ESPIPE)') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]

  client = TCPSocket.new('127.0.0.1', port)
  device = MRDebug::Transport::TCP.new(server.accept)

  client.write("break foo.rb:1\ncontinue\n")

  assert_equal 'break foo.rb:1', device.gets
  device.write("Breakpoint 1 added\n")
  assert_equal 'continue', device.gets
ensure
  client.close if client
  device.close if device
  server.close
end

assert('Transport::Socket#gets returns nil once the peer closes') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]

  client = TCPSocket.new('127.0.0.1', port)
  device = MRDebug::Transport::TCP.new(server.accept)
  client.close

  assert_nil device.gets
ensure
  device.close if device
  server.close
end

assert('Transport::Unix.connect reaches a listening UNIXServer; Socket#gets/#write round-trip over it') do
  path = '/tmp/mrdebug-test-unix-socket-transport.sock'
  File.delete(path) if File.exist?(path)
  server = UNIXServer.new(path)

  client = MRDebug::Transport::Unix.connect(path)
  device = MRDebug::Transport::Unix.new(server.accept)

  client.write("continue\n")
  assert_equal 'continue', device.gets
ensure
  client.close if client
  device.close if device
  server.close if server
  File.delete(path) if path && File.exist?(path)
end

assert('Transport::Socket#write to a peer-closed socket raises instead of killing the process (SIGPIPE)') do
  server = TCPServer.new('127.0.0.1', 0)
  port = server.addr[1]

  client = TCPSocket.new('127.0.0.1', port)
  device = MRDebug::Transport::TCP.new(server.accept)
  client.close
  client = nil

  # The first write after the peer closed can still succeed (it's what
  # draws the RST); a later one fails. Without MSG_NOSIGNAL that failure
  # is SIGPIPE, which would take down mrbtest itself.
  raised = false
  begin
    5.times { device.write("Stop: foo.rb:1\n") }
  rescue StandardError
    raised = true
  end
  assert_true raised
  assert_true device.detach_on_close?
ensure
  client.close if client
  device.close if device
  server.close
end
