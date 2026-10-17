module MRDebug
  class WatchVarBreakpoint
    include Breakpoint

    UNSET = Object.new

    attr_reader :expr

    def initialize(expr)
      @expr = expr
      @last_value = UNSET
    end

    # True the first time it's checked, and again whenever the evaluated
    # value differs from the previous check.
    def changed?(bnd)
      current = safe_eval(bnd)
      changed = @last_value == UNSET || current != @last_value
      @last_value = current
      changed
    end

    def stop_banner(siblings, location)
      "#{Protocol::WATCHPOINT}#{number_in(siblings)}: #{location}"
    end

    def to_s
      "watch: #{expr}"
    end

    private

    def safe_eval(bnd)
      bnd.eval(expr)
    rescue Exception => e
      MRDebug.error_text(e)
    end
  end
end
