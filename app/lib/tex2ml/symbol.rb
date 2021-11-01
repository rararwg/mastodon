require 'singleton'
module Tex2ml
  class Symbol
    include Singleton

    def self.get(symbol)
      instance.symbols[symbol]
    end

    def symbols
      @symbols ||= Tex2ml::SYMBOLS
    end

  end
end
