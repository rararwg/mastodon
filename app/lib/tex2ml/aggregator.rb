module Tex2ml
  class Aggregator
    OPERATORS = '+-*/=[]_^{}()'.freeze

    OPENING_BRACES = '{'.freeze
    CLOSING_BRACES = '}'.freeze
    OPENING_BRACKET = '['.freeze
    CLOSING_BRACKET = ']'.freeze
    OPENING_PARENTHESIS = '('.freeze
    CLOSING_PARENTHESIS = ')'.freeze

    BACKSLASH = '\\\\'.freeze
    AMPERSAND = '&'.freeze
    DASH = '-'.freeze

    SUB_SUP = '_^'.freeze
    SUBSCRIPT = '_'.freeze
    SUPERSCRIPT = '^'.freeze

    # Added prefix LATEX_ to avoid ruby reserved words
    LATEX_LEFT = '\\left'.freeze
    LATEX_RIGHT = '\\right'.freeze
    LATEX_OVER = '\\over'.freeze
    LATEX_HLINE = '\\hline'.freeze
    LATEX_BEGIN = '\\begin'.freeze
    LATEX_FRAC = '\\frac'.freeze
    LATEX_ROOT = '\\root'.freeze
    LATEX_SQRT = '\\sqrt'.freeze

    def initialize(tokens)
      @tokens = tokens
    end

    def aggregate(tokens = @tokens)
      aggregated = []

      loop do
        begin
          token = next_item_or_group(tokens)
          raise StopIteration if token.nil?

          if token.is_a?(Array)
            aggregated << token
          elsif token == OPENING_BRACKET
            previous = nil
            previous = aggregated[-1] if aggregated.any?
            begin
              g = group(tokens, opening: OPENING_BRACKET, closing: CLOSING_BRACKET)
              if previous == LATEX_SQRT
                root = tokens.shift
                raise StopIteration if root.nil?

                if root == OPENING_BRACES
                  begin
                    root = group(tokens)
                  rescue EmptyGroupError
                    root = ''
                  end
                end
                aggregated[-1] = LATEX_ROOT
                aggregated << root
              end
              aggregated << g
            rescue EmptyGroupError
              next if previous == LATEX_SQRT

              aggregated += [OPENING_BRACKET, CLOSING_BRACKET]
            end
          elsif LIMITS.include?(token)
            raise StopIteration if tokens.shift.nil?

            a = next_item_or_group(tokens)
            aggregated += [token, a]
          elsif token == '\\limits'
            previous = aggregated.pop
            raise StopIteration if tokens.shift.nil?

            a = next_item_or_group(tokens)
            raise StopIteration if tokens.shift.nil?

            b = next_item_or_group(tokens)
            aggregated += [token, previous, a, b]
          elsif token && SUB_SUP.include?(token)
            aggregated = process_sub_sup(aggregated, token, tokens)
          elsif token.start_with?(LATEX_BEGIN) || MATRICES.include?(token)
            aggregated += environment(token, tokens)
          elsif token == LATEX_OVER
            numerator = aggregated
            aggregated = []
            aggregated << LATEX_FRAC
            aggregated << numerator
            aggregated << aggregate(tokens)
          else
            aggregated << token
          end
        rescue EmptyGroupError
          aggregated += [OPENING_BRACES, CLOSING_BRACES]
          next
        rescue StopIteration
          aggregated << token unless token.nil?
          break
        end
      end

      aggregated
    end

    def environment(token, tokens)
      env = if token.start_with?(LATEX_BEGIN)
              token[7..-2]
            else
              token[1..token.size]
            end

      alignment = nil
      content = []
      row = []
      has_rowline = false

      loop do
        begin
          token = next_item_or_group(tokens)
          raise StopIteration if token.nil?

          if token.is_a? Array
            begin
              if env == 'array' && token.all? { |x| 'lcr|'.include?(x) }
                alignment = token
              else
                row << process_row(token)
              end
            rescue TypeError
              row << token
            end
          elsif token == "\\end{#{env}}"
            break
          elsif token == AMPERSAND
            row << token
          elsif token == BACKSLASH
            row = group_columns(row) if row.include?(AMPERSAND)
            row.insert(0, LATEX_HLINE) if has_rowline
            content << row
            row = []
            has_rowline = false
          elsif token == LATEX_HLINE
            has_rowline = true
          elsif token == OPENING_BRACKET && content.empty?
            begin
              alignment = group(tokens, opening: OPENING_BRACKET, closing: CLOSING_BRACKET)
            rescue EmptyGroupError
              next
            end
          elsif token == DASH
            next_token = tokens.shift
            raise StopIteration if next_token.nil?

            row << if next_token == "\\end{#{env}}"
                    token
                  else
                    [token, next_token]
                  end
          elsif SUB_SUP.include?(token)
            row = process_sub_sup(row, token, tokens)
          elsif token.start_with?(LATEX_BEGIN)
            row += environment(token, tokens)
          else
            row << token
          end
        rescue EmptyGroupError
          row << []
          next
        rescue StopIteration
          break
        end
      end

      if row.any?
        row = group_columns(row) if row.include?(AMPERSAND)
        row.insert(0, LATEX_HLINE) if has_rowline
        content << row
      end

      content = content.pop while content.size == 1 && content.first.is_a?(Array)

      return ["\\#{env}", alignment.join, content] if alignment

      ["\\#{env}", content]
    end

    def group(tokens, opening: OPENING_BRACES, closing: CLOSING_BRACES, delimiter: nil)
      g = []

      if delimiter
        g << delimiter
        g << tokens.shift
      end

      loop do
        begin
          token = tokens.shift
          raise StopIteration if token.nil?

          if token == closing && delimiter.nil?
            break if g.any?

            raise EmptyGroupError
          elsif token == opening
            begin
              g << group(tokens)
            rescue EmptyGroupError
              g += [[]]
            end
          elsif token == LATEX_LEFT
            g << group(tokens, delimiter: token)
          elsif token == LATEX_RIGHT
            g << token
            _token = tokens.shift
            raise StopIteration if _token.nil?

            g << _token
            break
          else
            g << token
          end
        rescue StopIteration
          break
        end
      end

      if delimiter
        right = g.index(LATEX_RIGHT)
        raise ExtraLeftOrMissingRight if right.nil?

        content = g[2..right - 1]
        g_ = g
        g_ = g[0..1] + [aggregate(content)] + g[right..g.size] if content.any?

        return g_
      end

      aggregate(g)
    end

    def group_columns(row)
      grouped = [[]]
      row.each do |item|
        if item == AMPERSAND
          grouped << []
        else
          grouped[-1] << item
        end
      end

      grouped.map { |item| item.size > 1 ? item : item.pop }
    end

    def next_item_or_group(tokens)
      token = tokens.shift
      raise StopIteration if token.nil?

      return group(tokens) if token == OPENING_BRACES

      return group(tokens, delimiter: token) if token == LATEX_LEFT

      token
    end

    def find_opening_parenthesis(tokens)
      closing = 0

      tokens.map.with_index { |x, i| [i, x] }.reverse.each do |index, token|
        if token == CLOSING_PARENTHESIS
          closing += 1
        elsif token == OPENING_PARENTHESIS
          return index if closing == 0

          closing -= 1
        end
      end
      raise ExtraLeftOrMissingRight
    end

    def process_row(tokens)
      row = []
      content = []

      tokens.each do |token|
        if token == AMPERSAND
          next
        elsif token == BACKSLASH
          content << row if row.any?
          row = []
        else
          row << token
        end
      end

      content << row if row.any?

      content = content.pop while content.size == 1 && content.first.is_a?(Array)

      content
    end

    def process_sub_sup(aggregated, token, tokens)
      begin
        previous = aggregated.pop
        raise IndexError if previous.nil?

        if previous.is_a?(String) && OPERATORS.include?(previous)
          if (previous == CLOSING_PARENTHESIS) && aggregated.include?(OPENING_PARENTHESIS)
            index = find_opening_parenthesis(aggregated)
            aggregated = aggregated[0, index] + [token] + [aggregated[index..aggregated.size] + [previous]]
          else
            aggregated += [previous, token]
          end
          return aggregated
        end

        begin
          next_token = next_item_or_group(tokens)
          if aggregated.size >= 2
            if aggregated[-2] == SUBSCRIPT && token == SUPERSCRIPT
              aggregated[-2] = SUB_SUP
              aggregated += [previous, next_token]
            elsif (aggregated[-2] == SUPERSCRIPT) && (token == SUBSCRIPT)
              aggregated[-2] = SUB_SUP
              aggregated += [next_token, previous]
            else
              aggregated += [token, previous, next_token]
            end
          else
            aggregated += [token, previous, next_token]
          end
        rescue EmptyGroupError
          aggregated += [token, previous, []]
        end
      rescue IndexError
        next_token = next_item_or_group(tokens)
        aggregated += [token, '', next_token]
      end

      aggregated
    end
  end

  class EmptyGroupError < StandardError; end
  class ExtraLeftOrMissingRight < StandardError; end
  class MissingSuperScriptOrSubscript < StandardError; end
  class StopIteration < StandardError; end
end
