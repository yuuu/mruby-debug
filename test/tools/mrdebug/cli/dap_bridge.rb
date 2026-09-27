def dap_bridge_test_remote
  session = MRDebug::Session.new
  session.on_line('/device/foo.rb', 1, binding)
  MRDebug::RemoteSession.new(session)
end

assert('DapBridge.initialize handshake: capabilities + initialized event') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  msgs = bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'initialize')

  assert_equal 2, msgs.size
  assert_equal true, msgs[0]['success']
  assert_equal true, msgs[0]['body']['supportsConfigurationDoneRequest']
  assert_equal 'event', msgs[1]['type']
  assert_equal 'initialized', msgs[1]['event']
  assert_false bridge.handshake_done?
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge attach/launch are both accepted as a no-op before configurationDone') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  %w[attach launch].each do |cmd|
    msgs = bridge.handle('seq' => 1, 'type' => 'request', 'command' => cmd)
    assert_equal 1, msgs.size
    assert_true msgs[0]['success']
  end
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge configurationDone completes the handshake and reports an entry stop') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  msgs = bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  assert_true bridge.handshake_done?
  assert_equal 2, msgs.size
  assert_true msgs[0]['success']
  assert_equal 'stopped', msgs[1]['event']
  assert_equal 'entry', msgs[1]['body']['reason']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge rejects continue/next before configurationDone') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  msgs = bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'continue')
  assert_false msgs[0]['success']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge setBreakpoints normalizes an absolute client path to a basename') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)

  request = {
    'seq' => 1, 'type' => 'request', 'command' => 'setBreakpoints',
    'arguments' => {
      'source' => { 'path' => '/Users/dev/workspace/foo.rb' }, # VS Code's absolute path
      'breakpoints' => [{ 'line' => 10 }, { 'line' => 20 }],
    },
  }
  msgs = bridge.handle(request)

  assert_true msgs[0]['success']
  assert_equal [10, 20], msgs[0]['body']['breakpoints'].map { |bp| bp['line'] }
  # The device's own LineBreakpoint suffix-matches against the basename,
  # not the client's full absolute path (see LineBreakpoint#match?).
  assert_equal 2, remote.breakpoints.select(&:active?).size
  assert_equal 'foo.rb', remote.breakpoints[0].file
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge setBreakpoints replaces the prior set for the same file') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  base_request = {
    'seq' => 1, 'type' => 'request', 'command' => 'setBreakpoints',
    'arguments' => { 'source' => { 'path' => 'foo.rb' }, 'breakpoints' => [{ 'line' => 10 }] },
  }
  bridge.handle(base_request)

  second_request = {
    'seq' => 2, 'type' => 'request', 'command' => 'setBreakpoints',
    'arguments' => { 'source' => { 'path' => 'foo.rb' }, 'breakpoints' => [{ 'line' => 99 }] },
  }
  bridge.handle(second_request)

  active = remote.breakpoints.select(&:active?)
  assert_equal 1, active.size
  assert_equal 99, active[0].line
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge continue/next/stepIn drive @remote and just ack -- no event of their own') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  %w[continue next stepIn].each do |cmd|
    msgs = bridge.handle('seq' => 2, 'type' => 'request', 'command' => cmd)
    assert_equal 1, msgs.size
    assert_true msgs[0]['success']
  end
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge#stop_messages/#terminated_notification build unprompted events') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)

  msgs = bridge.stop_messages('Stop: foo.rb:3')
  assert_equal 1, msgs.size
  assert_equal 'event', msgs[0]['type']
  assert_equal 'stopped', msgs[0]['event']
  assert_equal 'Stop: foo.rb:3', msgs[0]['body']['text']

  terminated = bridge.terminated_notification
  assert_equal 'terminated', terminated['event']
ensure
  MRDebug::Hook.uninstall
end

def dap_req(bridge, command, args = nil)
  req = { 'seq' => 1, 'type' => 'request', 'command' => command }
  req['arguments'] = args if args
  bridge.handle(req)
end

def dap_set_bps(bridge, path, lines)
  dap_req(bridge, 'setBreakpoints', 'source' => { 'path' => path },
          'breakpoints' => lines.map { |l| { 'line' => l } })[0]
end

def dap_set_fn_bps(bridge, names)
  dap_req(bridge, 'setFunctionBreakpoints', 'breakpoints' => names.map { |n| { 'name' => n } })[0]
end

assert('DapBridge setBreakpoints reports bridge ids and verifies from the device reply') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  bps = dap_set_bps(bridge, 'foo.rb', [10, 0])['body']['breakpoints']

  assert_equal [1, 2], bps.map { |bp| bp['id'] }
  assert_true bps[0]['verified']
  # Line 0 is refused by the device (`break` says "Invalid line number").
  assert_false bps[1]['verified']
  assert_equal 'Invalid line number', bps[1]['message']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge setFunctionBreakpoints adds method breakpoints and replaces the prior set') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  msg = dap_set_fn_bps(bridge, ['Foo#bar', 'Foo::Baz.qux', 'helper'])
  assert_true msg['success']
  assert_equal [true, true, true], msg['body']['breakpoints'].map { |bp| bp['verified'] }
  assert_equal ['Foo#bar', 'Foo::Baz.qux', 'helper'], remote.breakpoints.map(&:to_s)

  dap_set_fn_bps(bridge, ['Other#run'])
  assert_equal ['Other#run'], remote.breakpoints.select(&:active?).map(&:to_s)
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge setFunctionBreakpoints refuses a name that is not a method spec') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  # "foo.rb:3" would otherwise reach `break` as a line location.
  bps = dap_set_fn_bps(bridge, ['foo.rb:3'])['body']['breakpoints']
  assert_false bps[0]['verified']
  assert_true bps[0]['message'].include?('Not a method name')
  assert_equal 0, remote.breakpoints.size
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge keeps line and function breakpoints in step with the device\'s shared numbering') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  dap_set_bps(bridge, 'foo.rb', [10])  # device #1
  dap_set_fn_bps(bridge, ['Foo#bar'])  # device #2
  dap_set_bps(bridge, 'foo.rb', [20])  # deletes #1, adds #3

  active = remote.breakpoints.select(&:active?).map(&:to_s)
  assert_equal ['Foo#bar', 'foo.rb:20'], active
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge stop reasons follow the banner and report the hit breakpoint id') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  line_id = dap_set_bps(bridge, 'foo.rb', [10])['body']['breakpoints'][0]['id']
  fn_id = dap_set_fn_bps(bridge, ['Foo#bar'])['body']['breakpoints'][0]['id']
  dap_req(bridge, 'configurationDone')

  body = bridge.stop_messages('Breakpoint 1: foo.rb:10')[0]['body']
  assert_equal 'breakpoint', body['reason']
  assert_equal [line_id], body['hitBreakpointIds']

  body = bridge.stop_messages('Breakpoint 2: Foo#bar')[0]['body']
  assert_equal 'function breakpoint', body['reason']
  assert_equal [fn_id], body['hitBreakpointIds']

  assert_equal 'data breakpoint', bridge.stop_messages('Watchpoint 1: foo.rb:4')[0]['body']['reason']

  dap_req(bridge, 'next')
  assert_equal 'step', bridge.stop_messages('Stop: foo.rb:5')[0]['body']['reason']
  # A plain stop after continue can only be another binding.debugger.
  dap_req(bridge, 'continue')
  assert_equal 'breakpoint', bridge.stop_messages('Stop: foo.rb:9')[0]['body']['reason']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge holds breakpoints set while running until the next stop') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  dap_req(bridge, 'configurationDone')
  dap_req(bridge, 'continue')

  bps = dap_set_bps(bridge, 'foo.rb', [10])['body']['breakpoints']
  assert_false bps[0]['verified']
  dap_set_fn_bps(bridge, ['Foo#bar'])
  # Superseded before it was ever applied.
  dap_set_bps(bridge, 'foo.rb', [30])
  assert_equal 0, remote.breakpoints.size # nothing reached the device yet

  msgs = bridge.stop_messages('Stop: foo.rb:9')
  changed = msgs.select { |m| m['event'] == 'breakpoint' }
  assert_equal 2, changed.size
  assert_true changed.all? { |m| m['body']['reason'] == 'changed' && m['body']['breakpoint']['verified'] }
  assert_equal 'stopped', msgs[-1]['event']
  assert_equal ['Foo#bar', 'foo.rb:30'], remote.breakpoints.select(&:active?).map(&:to_s).sort
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge threads reports a single fixed thread') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')
  msgs = bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'threads')
  assert_equal [{ 'id' => 1, 'name' => 'main' }], msgs[0]['body']['threads']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge disconnect drops every breakpoint, lets the device run and reports terminated') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  dap_set_bps(bridge, 'foo.rb', [10])
  dap_set_fn_bps(bridge, ['Foo#bar'])
  dap_req(bridge, 'configurationDone')

  msgs = dap_req(bridge, 'disconnect')
  assert_true msgs[0]['success']
  assert_equal 'terminated', msgs[1]['event']
  assert_equal [], remote.breakpoints.select(&:active?)
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge reports stepOut as not supported yet') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  msgs = bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'stepOut')
  assert_false msgs[0]['success']
  assert_true msgs[0]['message'].include?('not supported yet')
ensure
  MRDebug::Hook.uninstall
end

def dap_bridge_stopped(bnd)
  session = MRDebug::Session.new
  session.on_line('/device/foo.rb', 1, bnd)
  bridge = MRDebug::CLI::DapBridge.new(MRDebug::RemoteSession.new(session))
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')
  bridge
end

def dap_evaluate(bridge, expr, extra = {})
  args = { 'expression' => expr, 'frameId' => 0 }
  extra.each { |k, v| args[k] = v }
  bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'evaluate', 'arguments' => args)[0]
end

assert('DapBridge initialize advertises conditional breakpoints and hover evaluation') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  body = bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'initialize')[0]['body']
  assert_true body['supportsConditionalBreakpoints']
  assert_true body['supportsEvaluateForHovers']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge evaluate returns the inspected value in the requested frame') do
  dap_eval_x = 21
  bridge = dap_bridge_stopped(binding)

  msg = dap_evaluate(bridge, 'dap_eval_x * 2')
  assert_true msg['success']
  assert_equal '42', msg['body']['result']
  assert_equal 0, msg['body']['variablesReference']

  # No frameId (e.g. an evaluate before any stackTrace) means frame 0.
  msg = bridge.handle('seq' => 3, 'type' => 'request', 'command' => 'evaluate',
                      'arguments' => { 'expression' => 'dap_eval_x' })[0]
  assert_equal '21', msg['body']['result']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge evaluate turns a raised exception into success:false') do
  bridge = dap_bridge_stopped(binding)
  msg = dap_evaluate(bridge, 'dap_eval_undefined_name', 'context' => 'hover')
  assert_false msg['success']
  assert_equal 'eval error: ', msg['message'][0, 12]
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge evaluate does not mistake a value that merely looks like an error for one') do
  bridge = dap_bridge_stopped(binding)
  msg = dap_evaluate(bridge, "'NameError: x'")
  assert_true msg['success']
  assert_equal '"NameError: x"', msg['body']['result']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge evaluate rejects a frame the device does not have') do
  bridge = dap_bridge_stopped(binding)
  msg = dap_evaluate(bridge, '1', 'frameId' => 999)
  assert_false msg['success']
  assert_equal 'No frame #999', msg['message']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge evaluate rejects a multi-line expression rather than splitting the command') do
  bridge = dap_bridge_stopped(binding)
  msg = dap_evaluate(bridge, "1\n2")
  assert_false msg['success']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge scopes reports one Locals scope keyed by frame id + 1') do
  bridge = dap_bridge_stopped(binding)
  msg = bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'scopes',
                      'arguments' => { 'frameId' => 0 })[0]
  assert_true msg['success']
  scopes = msg['body']['scopes']
  assert_equal 1, scopes.size
  assert_equal 'Locals', scopes[0]['name']
  assert_equal 1, scopes[0]['variablesReference']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge variables lists the frame\'s locals via info locals') do
  dap_var_num = 7
  dap_var_str = 'a = b'
  bridge = dap_bridge_stopped(binding)
  msg = bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'variables',
                      'arguments' => { 'variablesReference' => 1 })[0]
  assert_true msg['success']
  vars = msg['body']['variables']
  num = vars.find { |v| v['name'] == 'dap_var_num' }
  str = vars.find { |v| v['name'] == 'dap_var_str' }
  assert_equal '7', num['value']
  assert_equal 0, num['variablesReference']
  # Split on the first " = " only, so a value containing one survives.
  assert_equal '"a = b"', str['value']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge setBreakpoints forwards a condition, treating "" as none') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  request = {
    'seq' => 1, 'type' => 'request', 'command' => 'setBreakpoints',
    'arguments' => {
      'source' => { 'path' => 'foo.rb' },
      'breakpoints' => [{ 'line' => 10, 'condition' => 'x > 1' }, { 'line' => 20, 'condition' => '' }],
    },
  }
  msgs = bridge.handle(request)
  assert_true msgs[0]['success']
  assert_equal 'x > 1', remote.breakpoints[0].condition
  assert_nil remote.breakpoints[1].condition
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge stackTrace reports the backtrace, innermost frame first') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  msgs = bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'stackTrace')

  assert_true msgs[0]['success']
  frames = msgs[0]['body']['stackFrames']
  assert_true frames.size > 0
  assert_equal '/device/foo.rb', frames[0]['source']['path']
  assert_equal 'foo.rb', frames[0]['source']['name']
  assert_equal 1, frames[0]['line']
  assert_equal msgs[0]['body']['totalFrames'], frames.size
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge source fetches a real file VS Code has no local copy of, by the path a stackTrace frame reported') do
  session = MRDebug::Session.new
  session.on_line(__FILE__, 1, binding)
  remote = MRDebug::RemoteSession.new(session)
  bridge = MRDebug::CLI::DapBridge.new(remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  request = {
    'seq' => 2, 'type' => 'request', 'command' => 'source',
    'arguments' => { 'source' => { 'path' => __FILE__ } },
  }
  msgs = bridge.handle(request)

  assert_true msgs[0]['success']
  assert_true msgs[0]['body']['content'].include?('DapBridge source fetches a real file')
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge source reports a read failure for a path that does not exist on the device') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  request = {
    'seq' => 2, 'type' => 'request', 'command' => 'source',
    'arguments' => { 'source' => { 'path' => '/device/foo.rb' } },
  }
  msgs = bridge.handle(request)

  assert_true msgs[0]['success'] # the DAP request itself succeeds
  assert_equal 'Cannot open /device/foo.rb', msgs[0]['body']['content']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge reports an unsupported command instead of raising') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')
  msgs = bridge.handle('seq' => 2, 'type' => 'request', 'command' => 'restart')
  assert_false msgs[0]['success']
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge converts a raised exception into a success:false response') do
  remote = dap_bridge_test_remote
  bridge = MRDebug::CLI::DapBridge.new(remote)
  bridge.handle('seq' => 1, 'type' => 'request', 'command' => 'configurationDone')

  request = {
    'seq' => 2, 'type' => 'request', 'command' => 'setBreakpoints',
    'arguments' => { 'source' => { 'path' => 'foo.rb' }, 'breakpoints' => 'not-an-array' },
  }
  msgs = bridge.handle(request)
  assert_false msgs[0]['success']
  assert_true msgs[0]['message'].size > 0
ensure
  MRDebug::Hook.uninstall
end

assert('DapBridge#handle_message round-trips full JSON request/response text') do
  bridge = MRDebug::CLI::DapBridge.new(dap_bridge_test_remote)
  request_json = MRDebug::CLI::Json.generate(
    'seq' => 1, 'type' => 'request', 'command' => 'initialize'
  )
  responses = bridge.handle_message(request_json)

  assert_equal 2, responses.size
  parsed = MRDebug::CLI::Json.parse(responses[0])
  assert_true parsed['success']
  assert_equal 'response', parsed['type']
ensure
  MRDebug::Hook.uninstall
end
