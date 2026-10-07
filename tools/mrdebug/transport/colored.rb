module MRDebug
  module Transport
    # Decorates another Transport, coloring what is written to it (see
    # Colorizer). Reads, #close and #detach_on_close? pass straight through.
    class Colored < Base
      # inner itself unless colors are on for STDOUT (a TTY by default).
      def self.wrap(inner, mode = nil)
        Colorizer.enabled?(STDOUT, mode) ? new(inner) : inner
      end

      def initialize(inner, colorizer = Colorizer.new)
        @inner = inner
        @colorizer = colorizer
      end

      def gets
        @inner.gets
      end

      def write(str)
        text = @colorizer.feed(str)
        @inner.write(text) unless text.empty?
      end

      def close
        rest = @colorizer.finish
        @inner.write(rest) unless rest.empty?
        @inner.close
      end

      def detach_on_close?
        @inner.detach_on_close?
      end
    end
  end
end
