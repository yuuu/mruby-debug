CLZ = MRDebug::Colorizer

assert('Colorizer.colorize_line colors stop banners, replies, errors and frames') do
  assert_equal "#{CLZ::BOLD_YELLOW}Breakpoint 1: a.rb:3#{CLZ::RESET}", CLZ.colorize_line('Breakpoint 1: a.rb:3')
  assert_equal "#{CLZ::GREEN}Breakpoint 1 added at a.rb:3#{CLZ::RESET}", CLZ.colorize_line('Breakpoint 1 added at a.rb:3')
  assert_equal "#{CLZ::BOLD_CYAN}Stop: a.rb:4#{CLZ::RESET}", CLZ.colorize_line('Stop: a.rb:4')
  assert_equal "#{CLZ::RED}eval error: NameError: x#{CLZ::RESET}", CLZ.colorize_line('eval error: NameError: x')
  assert_equal "#{CLZ::CYAN}#12#{CLZ::RESET} a.rb:3", CLZ.colorize_line('#12 a.rb:3')
  assert_equal 'plain output', CLZ.colorize_line('plain output')
  assert_equal '#nope', CLZ.colorize_line('#nope')
end

assert('Colorizer.colorize_line highlights list lines as Ruby') do
  cur = CLZ.colorize_line('=> 12  puts 1')
  assert_equal "#{CLZ::BOLD_GREEN}=>#{CLZ::RESET} #{CLZ::DIM}12#{CLZ::RESET}  puts #{MRDebug::RubyHighlighter::NUMBER}1#{MRDebug::RubyHighlighter::RESET}", cur
  assert_equal '  c -- continue', CLZ.colorize_line('  c -- continue')
end

assert('Colorizer#feed holds a partial line, colors the prompt, keeps CRLF') do
  c = CLZ.new
  assert_equal '', c.feed('Stop: a')
  assert_equal "#{CLZ::BOLD_CYAN}Stop: a.rb:1#{CLZ::RESET}\r\n", c.feed(".rb:1\r\n")
  assert_equal '', c.feed('(mrdbg')
  assert_equal "#{CLZ::BOLD_GREEN}(mrdbg) #{CLZ::RESET}", c.feed(') ')
  assert_equal 'tail', (c.feed('tail'); c.finish)
  assert_equal '', c.finish
end

assert('Colorizer.enabled? honors always/never, and rejects a non-TTY in auto') do
  assert_true CLZ.enabled?(nil, 'always')
  assert_false CLZ.enabled?(Object.new, 'never')
  assert_false CLZ.enabled?(Object.new, 'auto')
end

assert('Transport::Colored colors writes, passes reads through, flushes on close') do
  inner = MRDebug::Transport::Loopback.new(['c'])
  t = MRDebug::Transport::Colored.new(inner)
  t.write("Stop: a.rb:1\n")
  t.write('(mrdbg) ')
  assert_equal 'c', t.gets
  t.write('half')
  t.close
  assert_equal ["#{CLZ::BOLD_CYAN}Stop: a.rb:1#{CLZ::RESET}\n", "#{CLZ::BOLD_GREEN}(mrdbg) #{CLZ::RESET}", 'half'], inner.output
  assert_false t.detach_on_close?
end
