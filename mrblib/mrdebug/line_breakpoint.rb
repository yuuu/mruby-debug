module MRDebug
  class LineBreakpoint
    include Breakpoint

    attr_reader :file, :line, :condition

    def initialize(file, line, condition = nil)
      @file = file
      @line = line
      @condition = condition
    end

    def match?(file, line)
      active? && @line == line && file[-@file.size, @file.size] == @file
    end

    def stop_banner(siblings, location)
      "#{Protocol::BREAKPOINT}#{number_in(siblings)}: #{location}"
    end

    def to_s
      condition ? "#{file}:#{line} if #{condition}" : "#{file}:#{line}"
    end
  end
end
