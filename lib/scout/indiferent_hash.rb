require_relative 'indiferent_hash/options'
require_relative 'indiferent_hash/case_insensitive'

module IndiferentHash

  def self.setup(hash)
    hash.extend IndiferentHash 
    hash
  end

  def merge(other)
    new = self.dup
    IndiferentHash.setup(new)
    other.each do |k,value|
      new[k] = value
    end
    new
  end

  def deep_merge(other)
    new = self.dup
    IndiferentHash.setup(new)
    other.each do |k,value|
      if new.include?(k) && IndiferentHash === new[k] && Hash === value
        new[k] = new[k].deep_merge(value)
      else
        new[k] = value
      end
    end
    new
  end

  def []=(key,value)
    delete(key)
    super(key,value)
  end

  def _default?
    @_default ||= self.default or self.default_proc
  end

  def [](key)
    res = super(key) 

    if ! (res.nil? || (_default? and not keys.include?(key)))
      IndiferentHash.setup(res) if Hash === res
      return res
    end

    res = case key
          when Symbol, Module
            super(key.to_s)
          when String
            super(key.to_sym)
          else
            res
          end
    IndiferentHash.setup(res) if Hash === res
    res
  end

  def values_at(*key_list)
    key_list.inject([]){|acc,key| acc << self[key]}
  end

  def include?(key)
    case key
    when Symbol, Module
      super(key) || super(key.to_s)
    when String
      super(key) || super(key.to_sym)
    else
      super(key)
    end
  end

  def delete(key)
    case key
    when Symbol, Module
      v = super(key) 
      v.nil? ? super(key.to_s) : v
    when String
      v = super(key)
      v.nil? ? super(key.to_sym) : v
    else
      super(key)
    end
  end

  def clean_version
    clean = {}
    each do |k,v|
      clean[k.to_s] = v unless clean.include? k.to_s
    end
    clean
  end

  def slice(*list)
    ext_list = []
    list.each do |e|
      case e
      when Symbol
        ext_list << e
        ext_list << e.to_s
      when String
        ext_list << e
        ext_list << e.to_sym
      else
        ext_list << e
      end
    end
    IndiferentHash.setup(super(*ext_list))
  end

  def keys_to_sym!
    string_keys = keys.select{|k| String === k}
    string_keys.each do |key|
      begin
        self[key.to_sym] = self.delete(key)
      rescue
        next
      end
    end
  end

  def keys_to_sym
    new = IndiferentHash.setup({})
    self.keys.each do |key|
      begin
        skey = key.is_a?(String) ? key.to_sym : key
      rescue
        skey = key
      end
      new[skey] = self[key]
    end
    new
  end

  def prety_print
    Misc.format_definition_list(self, sep: "\n")
  end

  def except(*list)
    full_list = list.dup

    list.each do |e|
      begin
        if String === e
          full_list << e.to_sym
        else
          full_list << e.to_s
        end
      rescue
        next
      end
    end

    super(*full_list)
  end
end

