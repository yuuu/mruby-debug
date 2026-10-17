module MRDebug
  class DisplayExpression
    attr_reader :expr

    def initialize(expr)
      @expr = expr
    end

    def result(bnd)
      bnd.eval(expr).inspect
    rescue Exception => e
      MRDebug.error_text(e)
    end
  end
end
