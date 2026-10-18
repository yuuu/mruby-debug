module MRDebug
  # Shared by LineBreakpoint, MethodBreakpoint and WatchVarBreakpoint.
  # A breakpoint's number is its index in Session's list + 1, so `delete`
  # deactivates in place rather than removing (later numbers stay put).
  # Watches can't be deleted, so a WatchVarBreakpoint is always active.
  module Breakpoint
    def active?
      !@deactivated
    end

    def deactivate!
      @deactivated = true
    end

    # This breakpoint's number within `siblings` (the Session list it's in).
    def number_in(siblings)
      siblings.index(self) + 1
    end

    def numbered_line(index)
      "  ##{index} #{self}"
    end
  end
end
