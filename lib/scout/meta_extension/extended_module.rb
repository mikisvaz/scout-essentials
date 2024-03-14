module MetaExtension
  module ExtendedModule
    def extension_attr(*attrs)
      self.instance_variable_get("@extension_attrs").concat attrs
      attrs.each do |a|
        self.attr_accessor a
      end
    end

    class << self
      def extension_attrs
        @extension_attrs ||= []
      end
    end

    def included(mod)
      mod.instance_variable_set(:@extension_attrs, []) unless mod.instance_variables.include?(:@extension_attrs)
      mod.instance_variable_get(:@extension_attrs).concat self.instance_variable_get(:@extension_attrs)
    end

    def extended(obj)
      attrs = self.instance_variable_get("@extension_attrs")

      obj.instance_variable_set(:@extension_attrs, []) unless obj.instance_variables.include?(:@extension_attrs)
      obj.extension_types << self

      extension_attrs = obj.instance_variable_get(:@extension_attrs)
      extension_attrs.concat attrs
    end

    def setup(*args,&block)
      if block_given?
        obj, rest = block, args
      else
        obj, *rest = args
      end
      obj = block if obj.nil?
      obj.extend self unless self === obj
      attrs = self.instance_variable_get("@extension_attrs")

      return obj if attrs.nil? || attrs.empty?

      if rest.length == 1 && Hash === (rlast = rest.last) && 
          ((! (rlkey = rlast.keys.first).nil? && attrs.include?(rlkey.to_sym)) ||
           (! attrs.length != 1 ))

        pairs = rlast
      else
        pairs = attrs.zip(rest)
      end

      pairs.each do |name,value|
        obj.instance_variable_set("@#{name}", value)
      end

      obj
    end
  end
end
