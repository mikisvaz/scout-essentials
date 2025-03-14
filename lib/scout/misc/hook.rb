module Hook
  def self.extended(hook_class)
    hook_class.class_variable_set(:@@prev_methods, hook_class.methods)
  end

  def self.apply(hook_class, base_class)
    base_class.class_variable_set(:@@hooks, []) unless base_class.class_variables.include?([])
    base_class.class_variable_get(:@@hooks).push hook_class

    hook_class.singleton_methods.each do |method_name|
      next unless base_class.singleton_methods.include? method_name
      orig_name = ("orig_" + method_name.to_s).to_sym
      if not base_class.singleton_methods.include?(orig_name)
        base_class.singleton_class.alias_method orig_name, method_name
        base_class.define_singleton_method method_name do |*args|
          base_class.class_variable_get(:@@hooks).each do |hook|
            next if hook.respond_to?(:claim) and not hook.claim(*args)
            if hook.respond_to?(method_name)
              return hook.send(method_name, *args)
            end
          end
          return base_class.send(orig_name, *args)
        end
      end
    end

    hook_class.instance_methods.each do |method_name|
      next unless base_class.instance_methods.include? method_name
      orig_name = ("orig_" + method_name.to_s).to_sym
      if not base_class.instance_methods.include?(orig_name)
        base_class.alias_method orig_name, method_name
        base_class.define_method method_name do |*args|
          base_class.class_variable_get(:@@hooks).each do |hook|
            next if hook.respond_to?(:claim) and not hook.claim(self, *args)
            if hook.instance_methods.include?(method_name)
              return hook.instance_method(method_name).bind(self).call *args
              #return self.instance_exec *args, &hook.instance_method(method_name)
            end
          end
          return self.send(orig_name, *args)
        end
      end
    end
  end
end
