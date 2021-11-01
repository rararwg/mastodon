module Tex2ml
  class Element
    attr_accessor :element
    def initialize(parent, tag, attributes = {})
      @element = Ox::Element.new(tag)
      attributes.each do |key, value|
        @element[key] = value
      end
      @parent = parent.is_a?(Tex2ml::Element) ? parent.element : parent
      @parent << @element
    end

    def tag=(tag)
      @element.value = tag
    end

    def text=(value)
      @element << Ox::Raw.new(value)
    end

    def set_attribute(key, value)
      @element[key] = value
    end
  end
end
