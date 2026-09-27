module MRDebug
  # Fallback for a port that's wanted but unspecified (bare listen_tcp,
  # `mrdbg` with no args). Matches rdbg's convention.
  DEFAULT_PORT = 4711

  # MRDEBUG_PORT's value for "no socket, use the local console".
  CONSOLE = 'console'.freeze

  # Opens a Session, blocks for the CLI to connect, wires it to LocalConsole.
  def self.listen_tcp(port = default_port, host = '0.0.0.0')
    notice("mrdebug: waiting for a debugger on port #{port}")
    session = Session.new
    session.ui = UI::LocalConsole.new(Transport::TCP.listen(port, host))
    self.session = session
    session
  end

  def self.listen_unix(path)
    notice("mrdebug: waiting for a debugger on #{path}")
    session = Session.new
    session.ui = UI::LocalConsole.new(Transport::Unix.listen(path))
    self.session = session
    session
  end

  # The (mrdbg) prompt on this process's own STDIN/STDOUT -- no socket, no CLI.
  def self.attach_stdio
    session = Session.new
    session.ui = UI::LocalConsole.new
    self.session = session
    session
  end

  # MRDebug.break calls this whenever a binding.debugger hit finds no
  # session (the first one, or after a client went away -- MRDebug.detach):
  # MRDEBUG_SOCK -> Unix listener; MRDEBUG_PORT=console -> the local
  # console; any other MRDEBUG_PORT -> TCP listener on it. With neither, a
  # host build (which has a terminal: Transport::Stdio) opens the local
  # console, and a device build listens on DEFAULT_PORT -- so a device
  # script needs nothing but binding.debugger. On R2P2, MRDEBUG_PORT comes
  # from /etc/config.yml's `env: mrdebug_port:` or the shell's `export`.
  def self.autostart
    sock = default_sock
    return listen_unix(sock) if sock

    port = env_value('MRDEBUG_PORT')
    return attach_local if port == CONSOLE
    return listen_tcp(default_port) if port || !local_by_default?
    attach_local
  end

  def self.local_by_default?
    Transport.const_defined?(:Stdio)
  end

  # The debugger on this process's own console. Overridden by the
  # mrdebug-console gem (the device's raw console, via picoruby-editor).
  def self.attach_local
    return attach_stdio if local_by_default?
    notice("mrdebug: no local console in this build (add the mrdebug-console gem); " \
           "listening on port #{DEFAULT_PORT} instead")
    listen_tcp(DEFAULT_PORT)
  end

  # MRDEBUG_PORT as a port number; DEFAULT_PORT when it's unset, blank, or
  # not a number (e.g. `console`).
  def self.default_port
    port = env_value('MRDEBUG_PORT')
    port && digits?(port) ? port.to_i : DEFAULT_PORT
  end

  def self.digits?(str)
    i = 0
    while i < str.size
      return false unless str[i] >= '0' && str[i] <= '9'
      i += 1
    end
    true
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

  # nil when mruby-env is absent or the value is blank.
  def self.env_value(name)
    value = defined?(ENV) ? ENV[name] : nil
    value && !value.empty? ? value : nil
  end
end
