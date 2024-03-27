module Annotation
  module AnnotatedObject
    def annotations
      @annotations ||= []
    end

    def annotation_types
      @annotation_types ||= []
    end

    def annotation_hash
      attr_hash = {}
      @annotations.each do |name|
        attr_hash[name] = self.instance_variable_get("@#{name}")
      end if @annotations
      attr_hash
    end

    def annotation_info
      annotation_hash.merge(annotation_types: annotation_types, annotated_array: (AnnotatedArray === self))
    end

    def self.serialize(obj)
      Annotation.purge(obj.annotation_info.merge(literal: obj))
    end

    def serialize
      AnnotatedObject.serialize(self)
    end

    def annotation_id
      Misc.digest([self, annotation_info])
    end

    alias id annotation_id

    def annotate(other)
      annotation_types.each do |type|
        type.setup(other, annotation_hash)
      end
      other
    end

    def purge
      new = self.dup

      if new.instance_variables.include?(:@annotations)
        new.instance_variable_get(:@annotations).each do |a|
          var_name = "@#{a}".to_sym
          new.remove_instance_variable(var_name) if new.instance_variables.include? var_name
        end
        new.remove_instance_variable(:@annotations)
      end

      if new.instance_variables.include?(:@annotation_types)
        new.remove_instance_variable(:@annotation_types)
      end

      new
    end

    def make_array
      new = [self]
      self.annotate(new)
      new.extend AnnotatedArray
      new
    end
  end
end
