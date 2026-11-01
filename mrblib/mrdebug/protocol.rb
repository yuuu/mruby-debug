module MRDebug
  # The (mrdbg) text protocol's fixed strings: what Command and the stop
  # banners print, and what DeviceLink, DapBridge and Colorizer parse back
  # on the host. Readers match on these constants, so a wording change here
  # reaches every one of them.
  module Protocol
    # Never newline-terminated, which is what lets DeviceLink use it as an
    # end-of-response marker.
    PROMPT = '(mrdbg) '.freeze

    # "Breakpoint N: <where>" is a stop banner; "Breakpoint N added at
    # <where>" is `break`'s reply.
    BREAKPOINT = 'Breakpoint '.freeze
    ADDED_AT = ' added at '.freeze
    WATCHPOINT = 'Watchpoint '.freeze
    STOP = 'Stop: '.freeze

    USAGE = 'Usage: '.freeze

    # debug gem's wording. Also what lets DapBridge tell a failed
    # `evaluate` apart from a value whose #inspect merely looks like an error.
    EVAL_ERROR = 'eval error: '.freeze
    NO_BINDING = 'No binding available for this breakpoint'.freeze
  end
end
