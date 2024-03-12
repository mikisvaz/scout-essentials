require_relative 'meta_extension/array'
require_relative 'meta_extension/extended_object'
require_relative 'meta_extension/extended_module'

module MetaExtension

  def self.setup(obj, extension_types, extension_attr_hash)
    extension_types = [extension_types] unless Array === extension_types
    extension_types.each do |type|
      type = Kernel.const_get(type) if String === type
      type.setup(obj, extension_attr_hash)
    end
    obj
  end

  def self.extended(base)
    base.instance_variable_set(:@extension_attrs, []) unless base.instance_variables.include?(:@extension_attrs)
    base.include MetaExtension::ExtendedObject
    base.extend MetaExtension::ExtendedModule
  end

  def self.is_extended?(obj)
    obj.respond_to?(:extension_attr_hash)
  end

  def self.purge(obj)
    case obj
    when nil
      nil
    when Array
      obj = obj.purge if is_extended?(obj)
      obj.collect{|e| purge(e) }
    when Hash
      new = {}
      obj.each do |k,v|
        new[purge(k)] = purge(v)
      end
      new
    else
      is_extended?(obj) ? obj.purge : obj
    end
  end
end
