module MRDebug
  # Single-line Ruby syntax highlighting with ANSI colors. A hand-rolled
  # scanner, not Regexp (mruby may have none), and no mruby-string-ext
  # methods (see CLAUDE.md). It sees one line at a time, so a string or
  # heredoc spanning lines is only colored where it starts.
  module RubyHighlighter
    RESET = "\e[0m".freeze
    KEYWORD = "\e[35m".freeze
    LITERAL = "\e[36m".freeze
    STRING = "\e[32m".freeze
    NUMBER = "\e[33m".freeze
    CONSTANT = "\e[93m".freeze
    DEF_NAME = "\e[34m".freeze
    COMMENT = "\e[90m".freeze

    KEYWORDS = %w[
      alias and begin break case class def defined? do else elsif end ensure
      for if in module next not or redo rescue retry return super then undef
      unless until when while yield
    ].freeze
    LITERALS = %w[nil true false self __FILE__ __LINE__ __method__].freeze

    def self.highlight(code)
      out = []
      i = 0
      size = code.size
      prev_word = nil
      prev_char = nil
      while i < size
        c = code[i]
        if c == ' ' || c == "\t"
          out << c
          i += 1
          next
        elsif c == '#'
          out << paint(COMMENT, code[i..-1])
          break
        elsif c == '"' || c == "'" || c == '`'
          j = string_end(code, i)
          out << paint(STRING, code[i, j - i])
          i = j
        elsif c == ':' && code[i + 1] == ':'
          out << '::'
          i += 2
        elsif c == ':' && (alpha?(code[i + 1]) || code[i + 1] == '"')
          j = code[i + 1] == '"' ? string_end(code, i + 1) : word_end(code, i + 1)
          out << paint(LITERAL, code[i, j - i])
          i = j
        elsif digit?(c)
          j = number_end(code, i)
          out << paint(NUMBER, code[i, j - i])
          i = j
        elsif (c == '@' || c == '$') && (alpha?(code[i + 1]) || code[i + 1] == '@')
          j = i + 1
          j += 1 while code[j] == '@'
          j = word_end(code, j)
          out << paint(LITERAL, code[i, j - i])
          i = j
        elsif alpha?(c)
          j = word_end(code, i)
          word = code[i, j - i]
          if code[j] == ':' && code[j + 1] != ':' && prev_char != '.' && !KEYWORDS.include?(word)
            word += ':'
            j += 1
          end
          out << paint_word(word, prev_char, prev_word)
          prev_word = word
          i = j
          prev_char = code[i - 1]
          next
        else
          out << c
          i += 1
        end
        prev_word = nil
        prev_char = c
      end
      out.join
    end

    def self.paint(color, text)
      "#{color}#{text}#{RESET}"
    end

    # A word right after `.` is a method name, never a keyword.
    def self.paint_word(word, prev_char, prev_word)
      return paint(DEF_NAME, word) if prev_word == 'def'
      return word if prev_char == '.'
      return paint(LITERAL, word) if word[-1] == ':'
      return paint(KEYWORD, word) if KEYWORDS.include?(word)
      return paint(LITERAL, word) if LITERALS.include?(word)
      return paint(CONSTANT, word) if Command.upper?(word[0])
      word
    end

    def self.alpha?(c)
      Command.lower?(c) || Command.upper?(c) || c == '_'
    end

    def self.digit?(c)
      Command.digit?(c)
    end

    # Identifier chars, plus one trailing ?/! (not part of `!=` / `?x`).
    def self.word_end(code, i)
      i += 1 while alpha?(code[i]) || digit?(code[i])
      i += 1 if (code[i] == '?' || code[i] == '!') && code[i + 1] != '='
      i
    end

    # Index just past the closing quote (or the end of the line).
    def self.string_end(code, i)
      quote = code[i]
      i += 1
      while i < code.size
        return i + 1 if code[i] == quote
        i += 1 if code[i] == "\\"
        i += 1
      end
      code.size
    end

    # `1.times` must not swallow the `.`; `1.5` and `0xff` stay whole.
    def self.number_end(code, i)
      while i < code.size
        c = code[i]
        if alpha?(c) || digit?(c)
          i += 1
        elsif c == '.' && digit?(code[i + 1])
          i += 1
        else
          break
        end
      end
      i
    end
  end
end
