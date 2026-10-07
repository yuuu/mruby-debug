MRuby::Gem::Specification.new('mrdebug-console') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Yuhei Okazaki'
  spec.summary = 'On-device interactive (mrdbg) console for mrdebug on PicoRuby'

  spec.add_dependency 'mrdebug', gemdir: File.expand_path('..', spec.dir)
  spec.add_dependency 'picoruby-editor', core: 'picoruby-editor'
  spec.add_dependency 'picoruby-io-console', core: 'picoruby-io-console'

  # The host-side colorizer, reused on the device's own console (opt-in via
  # MRDEBUG_COLOR=always, since the serial terminal may not speak ANSI).
  # Added here rather than in ../mrbgem.rake so a firmware without this gem
  # doesn't carry it.
  spec.rbfiles += %w[ruby_highlighter.rb colorizer.rb]
                    .map { |f| File.join(File.expand_path('..', spec.dir), 'tools', 'mrdebug', f) }
end
