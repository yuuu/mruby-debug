module MRDebug
  # This gem's own Ruby source files (and mrdebug-console's), so Session
  # can exclude them from tracing. Hardcoded, not discovered via Dir.glob (a
  # PicoRuby target may have no filesystem) -- update FILES when the file
  # list changes; spec/own_source_spec.rb fails until it matches.
  module OwnSource
    FILES = [
      'mrblib/mrdebug.rb',
      'mrblib/binding.rb',
      'mrblib/mrdebug/breakpoint.rb',
      'mrblib/mrdebug/command.rb',
      'mrblib/mrdebug/display_expression.rb',
      'mrblib/mrdebug/line_breakpoint.rb',
      'mrblib/mrdebug/method_breakpoint.rb',
      'mrblib/mrdebug/own_source.rb',
      'mrblib/mrdebug/protocol.rb',
      'mrblib/mrdebug/session.rb',
      'mrblib/mrdebug/transport.rb',
      'mrblib/mrdebug/transport/loopback.rb',
      'mrblib/mrdebug/ui.rb',
      'mrblib/mrdebug/watch_var_breakpoint.rb',
      'tools/mrdebug/cli/cli.rb',
      'tools/mrdebug/cli/dap_bridge.rb',
      'tools/mrdebug/cli/dap_server.rb',
      'tools/mrdebug/cli/device_link.rb',
      'tools/mrdebug/cli/json.rb',
      'tools/mrdebug/cli/main.rb',
      'tools/mrdebug/cli/options.rb',
      'tools/mrdebug/colorizer.rb',
      'tools/mrdebug/device.rb',
      'tools/mrdebug/remote_session.rb',
      'tools/mrdebug/ruby_highlighter.rb',
      'tools/mrdebug/transport/colored.rb',
      'tools/mrdebug/transport/socket.rb',
      'tools/mrdebug/transport/stdio.rb',
      'tools/mrdebug/ui/local_console.rb',
      'console/mrblib/mrdebug/console.rb',
    ]

    # Suffix match, same idiom as LineBreakpoint#match? -- the VM reports
    # absolute paths, and this list only knows relative ones.
    def self.file?(file)
      FILES.any? { |suffix| file[-suffix.size, suffix.size] == suffix }
    end
  end
end
