module CaseInsensitiveHash

  def self.setup(hash)
    hash.extend CaseInsensitiveHash
  end

  def downcase_keys
    @downcase_keys ||= begin
                         down = {} 
                         keys.collect{|key| 
                           down[key.to_s.downcase] = key 
                         }
                         down
                       end
  end

  def [](key, *rest)
    value = super(key, *rest)
    return value unless value.nil?
    key_downcase = key.to_s.downcase
    super(downcase_keys[key_downcase])
  end

  def values_at(*keys)
    keys.collect do |key|
      self[key]
    end
  end
  
end
