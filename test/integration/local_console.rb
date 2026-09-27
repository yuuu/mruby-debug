# Exercises MRDebug::UI::LocalConsole through a Transport::Loopback instead
# of real stdio.

def with_session(session)
  MRDebug.session = session
  yield
ensure
  MRDebug::Hook.uninstall
end

assert('LocalConsole, driven by a Loopback transport, evaluates print and resumes on continue') do
  transport = MRDebug::Transport::Loopback.new(['p x', 'c'])
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(transport)

  line = nil
  with_session(session) do
    x = 41
    line = __LINE__; binding.debugger
    x # keep x reachable after the stop, for symmetry with other integration files
  end

  assert_equal [
    "Stop: #{__FILE__}:#{line}\n",
    '(mrdbg) ',
    "41\n",
    '(mrdbg) ',
  ], transport.output
ensure
  MRDebug::Hook.uninstall
end

assert('LocalConsole treats a nil #gets (transport EOF/disconnect) as continue, not an error') do
  transport = MRDebug::Transport::Loopback.new # empty queue: #gets returns nil immediately
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(transport)

  line = nil
  with_session(session) do
    line = __LINE__; binding.debugger
  end

  assert_equal ["Stop: #{__FILE__}:#{line}\n", '(mrdbg) '], transport.output
ensure
  MRDebug::Hook.uninstall
end

local_console_next_inner_line = __LINE__ + 1
def local_console_next_inner(x)
  x + 1
end

local_console_next_debugger_line = __LINE__ + 2
def local_console_next_outer(x)
  binding.debugger
  local_console_next_inner(x)
end
local_console_next_call_line = local_console_next_debugger_line + 1

assert('LocalConsole processes a whole piped-in command sequence across a next and a continue') do
  transport = MRDebug::Transport::Loopback.new(['p x', 'n', 'p x', 'c'])
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(transport)

  with_session(session) do
    local_console_next_outer(7)
  end

  assert_equal [
    "Stop: #{__FILE__}:#{local_console_next_debugger_line}\n",
    '(mrdbg) ',
    "7\n",
    '(mrdbg) ',
    "Stop: #{__FILE__}:#{local_console_next_call_line}\n",
    '(mrdbg) ',
    "7\n",
    '(mrdbg) ',
  ], transport.output
ensure
  MRDebug::Hook.uninstall
end

local_console_frame_inner_line = __LINE__ + 2
def local_console_frame_inner(x)
  binding.debugger
  x + 1
end

local_console_frame_outer_line = __LINE__ + 2
def local_console_frame_outer(x)
  local_console_frame_inner(x * 2)
end

assert('LocalConsole up/down/frame select a caller frame, and print evaluates against it') do
  transport = MRDebug::Transport::Loopback.new(
    ['p x', 'up', 'p x', 'list', 'down', 'p x', 'frame 1', 'frame', 'down', 'down', 'frame 99', 'c']
  )
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(transport)

  result = nil
  with_session(session) do
    result = local_console_frame_outer(10)
  end
  assert_equal 21, result

  out = transport.output.reject { |l| l == '(mrdbg) ' }
  assert_equal "Stop: #{__FILE__}:#{local_console_frame_inner_line}\n", out[0]
  assert_equal "20\n", out[1]
  assert_equal "#1 #{__FILE__}:#{local_console_frame_outer_line}\n", out[2]
  assert_equal "10\n", out[3]
  # list follows the selected frame: its marked line is the caller's call site.
  listing = out[4, 11]
  assert_true listing.include?("=> #{local_console_frame_outer_line}    local_console_frame_inner(x * 2)\n")
  rest = out[15..-1]
  assert_equal [
    "#0 #{__FILE__}:#{local_console_frame_inner_line}\n",
    "20\n",
    "#1 #{__FILE__}:#{local_console_frame_outer_line}\n",
    "#1 #{__FILE__}:#{local_console_frame_outer_line}\n",
    "#0 #{__FILE__}:#{local_console_frame_inner_line}\n",
    "Already at the innermost frame\n",
    "No frame #99\n",
  ], rest
ensure
  MRDebug::Hook.uninstall
end

# A Loopback that behaves like a socket: losing the peer should end the
# session so the next binding.debugger can wait for a new client.
class LocalConsoleSocketLikeLoopback < MRDebug::Transport::Loopback
  attr_reader :closed

  def initialize(input_lines = [], fail_writes: false)
    super(input_lines)
    @fail_writes = fail_writes
    @closed = false
  end

  def write(str)
    raise IOError, 'peer closed' if @fail_writes
    super
  end

  def close
    @closed = true
  end

  def detach_on_close?
    true
  end
end

# MRDebug.break stops again after a detach; autostart is stubbed to hand out
# the queued sessions (then none) so no real stdio or socket is touched.
def local_console_with_sessions(sessions)
  saved_autostart = MRDebug.method(:autostart)
  started = []
  MRDebug.define_singleton_method(:autostart) do
    s = sessions.shift
    if s
      started << s
      MRDebug.session = s
    end
  end
  MRDebug.instance_variable_set(:@session, nil)
  yield started
ensure
  MRDebug.define_singleton_method(:autostart) { saved_autostart.call }
  MRDebug.instance_variable_set(:@session, nil)
  MRDebug::Hook.uninstall
end

assert('LocalConsole on a socket-like transport: EOF closes it and detaches the session') do
  gone = LocalConsoleSocketLikeLoopback.new # EOF straight away
  gone_session = MRDebug::Session.new
  gone_session.ui = MRDebug::UI::LocalConsole.new(gone)

  local_console_with_sessions([gone_session]) do |started|
    binding.debugger
    assert_equal [gone_session], started
    assert_true gone.closed
    assert_nil MRDebug.session
  end
end

assert('LocalConsole treats a failing write like EOF: detached, no exception reaches the script') do
  broken = LocalConsoleSocketLikeLoopback.new(['c'], fail_writes: true)
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(broken)

  local_console_with_sessions([session]) do
    binding.debugger
    assert_true broken.closed
    assert_nil MRDebug.session
  end
end

assert('binding.debugger stops again for the next client after the previous one went away') do
  gone = LocalConsoleSocketLikeLoopback.new
  gone_session = MRDebug::Session.new
  gone_session.ui = MRDebug::UI::LocalConsole.new(gone)

  fresh = LocalConsoleSocketLikeLoopback.new(['c'])
  fresh_session = MRDebug::Session.new
  fresh_session.ui = MRDebug::UI::LocalConsole.new(fresh)

  local_console_with_sessions([gone_session, fresh_session]) do |started|
    line = __LINE__; binding.debugger
    assert_equal [gone_session, fresh_session], started
    # The same stop, shown to the client that connected next.
    assert_equal "Stop: #{__FILE__}:#{line}\n", fresh.output[0]
    assert_false fresh.closed
    assert_true MRDebug.session.equal?(fresh_session)
  end
end

local_console_finish_inner_line = __LINE__ + 2
def local_console_finish_inner(x)
  binding.debugger
  x + 1
end

local_console_finish_middle_line = __LINE__ + 2
def local_console_finish_middle(x)
  r = local_console_finish_inner(x)
  r * 2
end

local_console_finish_outer_line = __LINE__ + 2
def local_console_finish_outer(x)
  v = local_console_finish_middle(x)
  v + 100
end

assert('LocalConsole finish stops at the call site in the caller, before its result is assigned') do
  transport = MRDebug::Transport::Loopback.new(['finish', 'p r', 'finish', 'p v', 'c'])
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(transport)

  result = nil
  with_session(session) do
    result = local_console_finish_outer(1)
  end
  assert_equal 104, result

  assert_equal [
    "Stop: #{__FILE__}:#{local_console_finish_inner_line}\n",
    "Stop: #{__FILE__}:#{local_console_finish_middle_line}\n",
    "nil\n",
    "Stop: #{__FILE__}:#{local_console_finish_outer_line}\n",
    "nil\n",
  ], transport.output.reject { |l| l == '(mrdbg) ' }
ensure
  MRDebug::Hook.uninstall
end

assert('LocalConsole finish after up returns from the selected frame, not just the innermost one') do
  transport = MRDebug::Transport::Loopback.new(['up', 'finish', 'c'])
  session = MRDebug::Session.new
  session.ui = MRDebug::UI::LocalConsole.new(transport)

  with_session(session) do
    local_console_finish_outer(1)
  end

  assert_equal [
    "Stop: #{__FILE__}:#{local_console_finish_inner_line}\n",
    "#1 #{__FILE__}:#{local_console_finish_middle_line}\n",
    "Stop: #{__FILE__}:#{local_console_finish_outer_line}\n",
  ], transport.output.reject { |l| l == '(mrdbg) ' }
ensure
  MRDebug::Hook.uninstall
end
