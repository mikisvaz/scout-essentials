module Misc
  def self._convert_match_condition(condition)
    return true if condition == 'true'
    return false if condition == 'false'
    return Regexp.new(condition[1..-2]) if condition[0] == "/"
    return [:cmp, $1, $2.to_f] if condition =~ /^([<>]=?)(.*)/
    return [:invert, _convert_match_condition(condition[1..-1].strip)] if condition[0] == "!"
    #return {$1 => $2.to_f} if condition =~ /^([<>]=?)(.*)/
    #return {false => _convert_match_condition(condition[1..-1].strip)} if condition[0] == "!"
    return condition
  end

  def self.match_value(value, condition)
    condition = _convert_match_condition(condition.strip) if String === condition

    return true if value.nil? && condition.nil?
    return false if value.nil?

    case condition
    when Regexp
      !! value.match(condition)
    when NilClass, TrueClass
      value === TrueClass or (String === value and value.downcase == 'true')
    when FalseClass
      value === FalseClass or (String === value and value.downcase == 'false')
    when String
      Numeric === value ? value.to_f == condition.to_f : value == condition
    when Numeric
      value.to_f == condition.to_f
    when Array
      case condition.first
      when :cmp
        value.to_f.send(condition[1], condition[2])
      when :invert
        ! match_value(value, condition[1] )
      else
        condition.inject(false){|acc,e| acc = acc ? true : match_value(value, e) }
      end
    else
      raise "Condition not understood: #{Misc.fingerprint condition}"
    end
  end

  def self.tokenize(str)
    str.scan(/"([^"]*)"|'([^']*)'|([^"'\s]+)/).flatten.compact
  end
end
