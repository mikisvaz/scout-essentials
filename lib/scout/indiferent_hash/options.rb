module IndiferentHash
  def self.add_defaults(options, defaults = {})
    options = string2hash options if String === options
    IndiferentHash.setup(options)

    defaults = string2hash defaults if String === defaults

    defaults.each do |key, value|
      next if options.include?(key)

      options[key] = value 
    end

    options
  end

  def self.process_options(hash, *keys)
    IndiferentHash.setup(hash)

    defaults = keys.pop if Hash === keys.last
    hash = IndiferentHash.add_defaults hash, defaults if defaults

    if keys.length == 1
      hash.include?(keys.first.to_sym) ? hash.delete(keys.first.to_sym) : hash.delete(keys.first.to_s) 
    else
      keys.collect do |key| hash.include?(key.to_sym) ? hash.delete(key.to_sym) : hash.delete(key.to_s) end
    end
  end

  def self.pull_keys(hash, prefix)
    IndiferentHash.setup(hash)
    new = hash.include?("#{prefix}_options") ? hash.delete("#{prefix}_options") : {}
    prefix = prefix.to_s
    hash.keys.each do |key|
      if key.to_s =~ /#{ prefix }_(.*)/
        case
        when String === key
          new[$1] = hash.delete key
        when Symbol === key
          new[$1.to_sym] = hash.delete key
        end
      else
        if key.to_s == prefix.to_s
          new[key] = hash.delete key
        end
      end
    end

    IndiferentHash.setup(new)
  end

  def self.zip2hash(list1, list2)
    hash = {}
    list1.each_with_index do |e,i|
      hash[e] = list2[i]
    end
    IndiferentHash.setup(hash)
  end

  def self.positional2hash(keys, *values)
    if Hash === values.last
      extra = values.pop
      inputs = IndiferentHash.zip2hash(keys, values)
      inputs.delete_if{|k,v| v.nil? or (String === v and v.empty?)}
      inputs = IndiferentHash.add_defaults inputs, extra
      inputs.delete_if{|k,v| not keys.include?(k) and not (Symbol === k ? keys.include?(k.to_s) : keys.include?(k.to_sym))}
      inputs
    else
      IndiferentHash.zip2hash(keys, values)
    end
  end

  def self.array2hash(array, default = nil)
    hash = {}
    array.each do |key, value|
      value = default.dup if value.nil? and not default.nil?
      hash[key] = value
    end
    IndiferentHash.setup(hash)
  end

  def self.process_to_hash(list)
    result = yield list
    zip2hash(list, result)
  end

  def self.hash2string(hash)
    hash.sort_by{|k,v| k.to_s}.collect{|k,v| 
      next unless %w(Symbol String Float Fixnum Integer Numeric TrueClass FalseClass Module Class Object).include? v.class.to_s
      [ Symbol === k ? ":" << k.to_s : k.to_s.chomp,
        Symbol === v ? ":" << v.to_s : v.to_s.chomp] * "="
    }.compact * "#"
  end

  def self.string2hash(string)
    options = {}

    string.split('#').each do |str|
      key, _, value = str.partition "="

      key = key[1..-1].to_sym if key[0] == ":"

      options[key] = true and next if value.empty?
      options[key] = value[1..-1].to_sym and next if value[0] == ":"
      options[key] = Regexp.new(/#{value[1..-2]}/) and next if value[0] == "/" and value[-1] == "/"
      options[key] = value[1..-2] and next if value =~ /^['"].*['"]$/
      options[key] = value.to_i and next if value =~ /^\d+$/
      options[key] = value.to_f and next if value =~ /^\d*\.\d+$/
      options[key] = true and next if value == "true"
      options[key] = false and next if value == "false"
      options[key] = value
    end

    IndiferentHash.setup(options)
  end
end
