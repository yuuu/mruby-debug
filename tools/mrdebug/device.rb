module MRDebug
  # Fallback for a port that's wanted but unspecified (bare listen_tcp,
  # `mrdbg` with no args). Matches rdbg's convention.
  DEFAULT_PORT = 4711

  # MRDEBUG_PORT's value for "no socket, use the local console".
  CONSOLE = 'console'.freeze

  # A new Session driven by `ui`, made the current one.
  def self.start_session(ui)
    session = Session.new
    session.ui = ui
    self.session = session
    session
  end

  # Opens a Session, blocks for the CLI to connect, wires it to LocalConsole.
  def self.listen_tcp(port = default_port, host = '0.0.0.0')
    notice("mrdebug: waiting for a debugger on port #{port}")
    start_session(UI::LocalConsole.new(Transport::TCP.listen(port, host)))
  end

  def self.listen_unix(path)
    notice("mrdebug: waiting for a debugger on #{path}")
    start_session(UI::LocalConsole.new(Transport::Unix.listen(path)))
  end

  # The (mrdbg) prompt on this process's own STDIN/STDOUT -- no socket, no CLI.
  def self.attach_stdio
    start_session(UI::LocalConsole.new(stdio_transport))
  end

  # Stdio, colored when STDOUT is a TTY (the Colored decorator is host-only).
  def self.stdio_transport
    stdio = Transport::Stdio.new
    Transport.const_defined?(:Colored) ? Transport::Colored.wrap(stdio) : stdio
  end

  # MRDebug.break calls this whenever a binding.debugger hit finds no
  # session (the first one, or after a client went away -- MRDebug.detach):
  # MRDEBUG_SOCK -> Unix listener; MRDEBUG_PORT=console -> the local
  # console; any other MRDEBUG_PORT -> TCP listener on it. With neither,
  # a build that has a local console opens it -- a host (Transport::Stdio),
  # or a device built with the mrdebug-console gem (UI::Console) -- and any
  # other device build listens on DEFAULT_PORT. Either way a device script
  # needs nothing but binding.debugger. On R2P2, MRDEBUG_PORT comes from
  # /etc/config.yml's `env: mrdebug_port:` or the shell's `export`.
  def self.autostart
    sock = default_sock
    return listen_unix(sock) if sock

    port = env_value('MRDEBUG_PORT')
    return attach_local if port == CONSOLE
    return listen_tcp(default_port) if port || !local_by_default?
    attach_local
  end

  def self.local_by_default?
    Transport.const_defined?(:Stdio) || UI.const_defined?(:Console)
  end

  # The debugger on this process's own console. Overridden by the
  # mrdebug-console gem (the device's raw console, via picoruby-editor).
  def self.attach_local
    return attach_stdio if Transport.const_defined?(:Stdio)
    notice("mrdebug: no local console in this build (add the mrdebug-console gem); " \
           "listening on port #{DEFAULT_PORT} instead")
    listen_tcp(DEFAULT_PORT)
  end

  # MRDEBUG_PORT as a port number; DEFAULT_PORT when it's unset, blank, or
  # not a number (e.g. `console`).
  def self.default_port
    port = env_value('MRDEBUG_PORT')
    port && Command.digits?(port) ? port.to_i : DEFAULT_PORT
  end

  # A one-line status on the device's own console (stderr where there is
  # one), e.g. while a listener blocks for a client.
  def self.notice(msg)
    if defined?(STDERR)
      STDERR.write("#{msg}\n")
    else
      puts msg
    end
  end

  # nil (as if unset) when UNIXServer doesn't exist, e.g. picoruby-socket.
  def self.default_sock
    return nil unless defined?(UNIXServer)
    env_value('MRDEBUG_SOCK')
  end
end
