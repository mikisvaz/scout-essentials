require_relative 'annotation'
module NamedArray
  extend Annotation
  annotation :fields, :key

  def all_fields
    [key, fields].compact.flatten
  end

  def self.field_match(field, name)
    if (String === field) && (String === name)
      return true if field == name
      return true if field.include?("(" + name + ")") 
      return true if name.include?("(" + field + ")")
      return true if field.start_with?(name + " ")
      return true if name.start_with?(field + " ")
    else
      field == name
    end
  end

  def self.identify_name(names, selected, strict: false)
    res = (Array === selected ? selected : [selected]).collect do |field|
      case field
      when nil
        0
      when Range
        field
      when Integer
        field
      when Symbol
        field == :key ? field : identify_name(names, field.to_s)
      when (names.nil? and String)
        if field =~ /^\d+$/
          identify_field(key_field, fields, field.to_i)
        else
          raise "No name information available and specified name not numeric: #{ field }"
        end
      when Symbol
        names.index{|f| f.to_s == field.to_s }
      when String
        pos = names.index{|f| f.to_s == field }
        next pos if pos
        if field =~ /^\d+$/
          next identify_names(names, field.to_i)
        end
        next pos if strict
        pos = names.index{|name| field_match(field, name) }
        next pos if pos
        nil
      else
        raise "Field '#{ Log.fingerprint field }' was not understood. Options: (#{ Log.fingerprint names })"
      end
    end

    Array === selected ? res : res.first
  end

  def identify_name(selected)
    NamedArray.identify_name(fields, selected)
  end

  def positions(fields)
    if Array ==  fields
      fields.collect{|field|
        NamedArray.identify_name(@fields, field)
      }
    else
      NamedArray.identify_name(@fields, fields)
    end
  end

  def [](key)
    pos = NamedArray.identify_name(@fields, key)
    return nil if pos.nil?
    super(pos)
  end

  def []=(key, value)
    pos = NamedArray.identify_name(@fields, key)
    return nil if pos.nil?
    super(pos, value)
  end


  def concat(other)
    if Hash === other
      new_fields = []
      other.each do |k,v|
        new_fields << k
        self << v
      end
      self.fields.concat(new_fields)
    else
      super(other)
      self.fields.concat(other.fields) if NamedArray === other
      self
    end
  end

  def to_hash
    hash = {}
    self.fields.each do |field|
      hash[field] = self[field]
    end
    IndiferentHash.setup hash
  end

  def values_at(*positions)
    super(*identify_name(positions))
  end

  def self._zip_fields(array, max = nil)
    return [] if array.nil? or array.empty? or (first = array.first).nil?

    max = array.collect{|l| l.length }.max if max.nil?

    rest = array[1..-1].collect{|v|
      v.length == 1 & max > 1 ? v * max : v
    }

    first = first * max if first.length == 1 and max > 1

    first.zip(*rest)
  end

  def self.zip_fields(array)
    if array.length < 10000
      _zip_fields(array)
    else
      zipped_slices = []
      max = array.collect{|l| l.length}.max
      array.each_slice(10000) do |slice|
        zipped_slices << _zip_fields(slice, max)
      end
      new = zipped_slices.first
      zipped_slices[1..-1].each do |rest|
        rest.each_with_index do |list,i|
          new[i].concat list
        end
      end
      new
    end
  end

  def self.add_zipped(source, new)
    source.zip(new).each do |s,n|
      next if n.nil?
      s.concat(n)
    end
    source
  end

  def method_missing(name, *args)
    if identify_name(name)
      return self[name]
    else
      return super(name, *args)
    end
  end
end
