module MetaExtension
  def self.extended(base)
    meta = class << base; self; end

    base.class_variable_set(:@@extension_attrs, []) unless base.class_variables.include?(:@@extension_attrs)

    meta.define_method(:extension_attr) do |*attrs|
      self.class_variable_get("@@extension_attrs").concat attrs
      attrs.each do |a|
        self.attr_accessor a
      end
    end

    meta.define_method(:extended) do |obj|
      attrs = self.class_variable_get("@@extension_attrs")

      obj.instance_variable_set(:@extension_attrs, []) unless obj.instance_variables.include?(:@extension_attrs)
      extension_attrs = obj.instance_variable_get(:@extension_attrs)
      extension_attrs.concat attrs
    end

    meta.define_method(:setup) do |*args,&block|
      if block_given?
        obj, rest = block, args
      else
        obj, *rest = args
      end
      obj = block if obj.nil?
      obj.extend base unless base === obj
      obj.extension_types << base

      attrs = self.class_variable_get("@@extension_attrs")

      return if attrs.nil? || attrs.empty?

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

    base.define_method(:extension_types) do 
      @extension_types ||= []
    end

    base.define_method(:extension_attr_hash) do 
      attr_hash = {}
      @extension_attrs.each do |name|
        attr_hash[name] = self.instance_variable_get("@#{name}")
      end
      attr_hash
    end

    base.define_method(:annotate) do |other|
      attr_values = @extension_attrs.collect do |a|
        self.instance_variable_get("@#{a}")
      end
      base.setup(other, *attr_values)
    end

    base.define_method(:purge) do
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

  def self.is_extended?(obj)
    obj.respond_to?(:extension_attr_hash)
  end

  def self.purge(obj)
    case obj
    when nil
      nil
    when Array
      obj.collect{|e| purge(e) }
    when Hash
      new = {}
      obj.each do |k,v|
        new[k] = purge(v)
      end
      new
    else
      is_extended?(obj) ? obj.purge : obj
    end
  end
end
