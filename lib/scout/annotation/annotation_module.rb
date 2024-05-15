module Annotation
  module AnnotationModule
    def annotation(*attrs)
      self.instance_variable_get("@annotations").concat attrs
      attrs.each do |a|
        self.attr_accessor a
      end
    end

    def annotations
      @annotations ||= []
    end

    def included(mod)
      mod.instance_variable_set(:@annotations, []) unless mod.instance_variables.include?(:@annotations)
      mod.instance_variable_get(:@annotations).concat self.instance_variable_get(:@annotations)
    end

    def extended(obj)
      attrs = self.instance_variable_get("@annotations")

      obj.instance_variable_set(:@annotations, []) unless obj.instance_variables.include?(:@annotations)
      obj.annotation_types << self

      annotations = obj.instance_variable_get(:@annotations)
      annotations.concat attrs
    end

    def setup(*args,&block)
      if block_given?
        obj, rest = block, args
      else
        obj, *rest = args
      end
      obj = block if obj.nil?
      return nil if obj.nil?
      obj.extend self unless self === obj
      attrs = self.instance_variable_get("@annotations")

      return obj if attrs.nil? || attrs.empty?

      if rest.length == 1 && Hash === (rlast = rest.last) && 
          ((! (rlkey = rlast.keys.first).nil? && attrs.include?(rlkey.to_sym)) ||
           (! attrs.length != 1 ))

        pairs = rlast
      else
        pairs = attrs.zip(rest)
      end

      pairs.each do |name,value|
        next if name.to_sym === :annotation_types
        obj.instance_variable_set("@#{name}", value) unless value.nil?
      end

      obj
    end
  end
end
