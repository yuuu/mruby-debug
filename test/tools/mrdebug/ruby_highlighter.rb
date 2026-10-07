HLT = MRDebug::RubyHighlighter

assert('RubyHighlighter colors keywords, strings, symbols, numbers and comments') do
  out = HLT.highlight("if x == 10 # hi")
  assert_equal "#{HLT::KEYWORD}if#{HLT::RESET} x == #{HLT::NUMBER}10#{HLT::RESET} #{HLT::COMMENT}# hi#{HLT::RESET}", out
  assert_equal "puts #{HLT::STRING}\"a # b\"#{HLT::RESET}", HLT.highlight('puts "a # b"')
  assert_equal "f(#{HLT::LITERAL}:sym#{HLT::RESET})", HLT.highlight('f(:sym)')
end

assert('RubyHighlighter leaves method names after a dot alone, and names def targets') do
  assert_equal "x.class", HLT.highlight('x.class')
  assert_equal "#{HLT::KEYWORD}def#{HLT::RESET} #{HLT::DEF_NAME}foo?#{HLT::RESET}", HLT.highlight('def foo?')
end

assert('RubyHighlighter handles escapes, unterminated strings, labels and ivars') do
  assert_equal "#{HLT::STRING}'a\\'b'#{HLT::RESET}", HLT.highlight("'a\\'b'")
  assert_equal "#{HLT::STRING}\"open#{HLT::RESET}", HLT.highlight('"open')
  assert_equal "{ #{HLT::LITERAL}k:#{HLT::RESET} 1 }".sub('1', "#{HLT::NUMBER}1#{HLT::RESET}"), HLT.highlight('{ k: 1 }')
  assert_equal "#{HLT::LITERAL}@a#{HLT::RESET} = #{HLT::CONSTANT}Foo#{HLT::RESET}", HLT.highlight('@a = Foo')
end

assert('RubyHighlighter keeps `1.times` and `1.5` apart') do
  assert_equal "#{HLT::NUMBER}1#{HLT::RESET}.times", HLT.highlight('1.times')
  assert_equal "#{HLT::NUMBER}1.5#{HLT::RESET}", HLT.highlight('1.5')
end
