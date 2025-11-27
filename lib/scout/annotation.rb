require_relative 'annotation/array'
require_relative 'annotation/annotated_object'
require_relative 'annotation/annotation_module'

module Annotation

  def self.setup(obj, annotation_types, annotation_hash)
    return nil if obj.nil?
    annotation_types = annotation_types.split("|") if String === annotation_types
    annotation_types = [annotation_types] unless Array === annotation_types
    annotation_types.each do |type|
      begin
        type = Kernel.const_get(type) if String === type
        type.setup(obj, annotation_hash)
      rescue NameError
        Log.warn "Annotation #{type} not defined"
      end
    end
    obj
  end

  def self.extended(base)
    base.instance_variable_set(:@annotations, []) unless base.instance_variables.include?(:@annotations)
    base.include Annotation::AnnotatedObject
    base.extend Annotation::AnnotationModule
  end

  def self.is_annotated?(obj)
    obj.instance_variables.include?(:@annotation_types) && obj.respond_to?(:purge)
  end

  def self.purge(obj)
    case obj
    when nil
      nil
    when Array
      obj = obj.purge if is_annotated?(obj)
      obj.collect{|e| purge(e) }
    when Hash
      new = {}
      obj.each do |k,v|
        new[purge(k)] = purge(v)
      end
      new
    else
      is_annotated?(obj) ? obj.purge : obj
    end
  end
end
