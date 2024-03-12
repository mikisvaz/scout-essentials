module MetaExtension
  module ExtendedObject
    def extension_attrs
      @extension_attrs ||= []
    end

    def extension_types
      @extension_types ||= []
    end

    def extension_attr_hash
      attr_hash = {}
      @extension_attrs.each do |name|
        attr_hash[name] = self.instance_variable_get("@#{name}")
      end
      attr_hash
    end

    def extension_info
      extension_attr_hash.merge(extension_types: extension_types)
    end

    def extended_digest
      Misc.digest([self, extension_info])
    end

    def annotate(other)
      extension_types.each do |type|
        type.setup(other, extension_attr_hash)
      end
      other
    end

    def purge
      new = self.dup

      if new.instance_variables.include?(:@extension_attrs)
        new.instance_variable_get(:@extension_attrs).each do |a|
          var_name = "@#{a}".to_sym
          new.remove_instance_variable(var_name) if new.instance_variables.include? var_name
        end
        new.remove_instance_variable("@extension_attrs")
      end

      if new.instance_variables.include?(:@extension_types)
        new.remove_instance_variable("@extension_types")
      end

      new
    end
  end
end
