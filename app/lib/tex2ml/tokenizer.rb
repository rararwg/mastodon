require 'strscan'

module Tex2ml
  class Tokenizer < StringScanner
    def tokenize
      exp = []

      while token = fetch_token
        exp << token
      end

      exp
    end

    def fetch_token
      skip(/\s+/)

      token = if scan(/\\mathbb\s*{[^}]+}/)
                if Tex2ml::Symbol.get(matched)
                  "#{Tex2ml::Symbol.get(matched)}"
                else
                  matched
                end
              elsif scan(/{\\bf [^}]+}/)
                matches = matched.match(/{\\bf ([^}]+)}/)
                symbol = Tex2ml::Symbol.get("\\mathbf{#{matches[1]}}")
                "#{symbol}" if symbol
              elsif scan(/\\\\\[\d+mm\]/)
                '\\\\' # matched
              elsif scan(/\\mbox\s*{[^\}]+}/)
                matched
              elsif scan(/\\Delta/)
                matched
              elsif scan(/\\vec\s*{[^\}]+}/)
                matched
              elsif scan(/\\hat\s*{[^\}]+}/)
                matched
              elsif scan(/\\textrm\s*{[^\}]+}/)
                matched
              elsif scan(/{\\rm [^}]+}/)
                matches = matched.match(/{\\rm ([^}]+)}/)
                matches[1]
              elsif scan(/\\[a-zA-Z]+\{(bmatrix|Bmatrix|matrix|vmatrix|Vmatrix|array|pmatrix|split)\*?\}/)
                matched
              elsif scan(/\\[a-zA-Z]+/)
                matched
              elsif scan(/\\\\/)
                matched
              elsif scan(/\\\[/)
                matched
              elsif scan(/\\\]/)
                matched
              elsif scan(/\\\{/)
                matched
              elsif scan(/\\[:;,]/)
                matched
              elsif scan(/\\/)
                matched
              elsif scan(/[a-zA-Z]/)
                matched
              elsif scan(/[0-9]+\.[0-9]+/)
                matched
              elsif scan(/[0-9]+/)
                matched
              elsif scan(/ /)
                matched
              elsif scan(/[\{\}\*]/)
                matched
              elsif scan(/./)
                matched
              end
      token
    end
  end
end
