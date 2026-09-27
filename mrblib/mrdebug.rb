# mrdebug: a debugger core for mruby. Everything but the VM hook itself
# (src/hook.c, src/frame.c) lives on the Ruby side.
module MRDebug
  VERSION = '0.0.1'

  def self.session
    @session
  end

  def self.session=(session)
    @session = session
    MRDebug::Hook.install(session)
  end

  # Overridden on host builds (tools/mrdebug/device.rb); a no-op otherwise.
  def self.autostart
  end

  # Drops `session` once its UI has lost its client (see LocalConsole):
  # the hook comes off so the program runs at full speed, and the next
  # binding.debugger autostarts a fresh session -- e.g. waits for a new
  # connection. Safe from inside a stop: Hook.uninstall only clears state,
  # and the callback's own tail then leaves the hook disarmed.
  def self.detach(session)
    return unless @session.equal?(session)
    @session = nil
    MRDebug::Hook.uninstall
  end

  def self.break(bnd)
    while true
      autostart if @session.nil?
      return unless @session
      file, line = bnd.source_location
      MRDebug::Hook.enter(file, line, bnd)
      # Still attached: an ordinary resume. Detached during this stop (the
      # client went away): stop here again for whoever connects next,
      # rather than running past the binding.debugger it was waiting at.
      return unless @session.nil?
    end
  end
end
