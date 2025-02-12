module Misc

  Log2Multiplier = 1.0 / Math.log(2.0)
  Log10Multiplier = 1.0 / Math.log(10.0)
  def self.log2(x)
    Math.log(x) * Log2Multiplier
  end

  def self.log10(x)
    Math.log(x) * Log10Multiplier
  end

  def self.max(list)
    max = nil
    list.each do |v|
      next if v.nil?
      max = v if max.nil? or v > max
    end
    max
  end

  def self.min(list)
    min = nil
    list.each do |v|
      next if v.nil?
      min = v if min.nil? or v < min
    end
    min
  end

  def self.std_num_vector(v, min, max)
    v_min = Misc.min(v)
    v_max = Misc.max(v)
    v_range = v_max - v_min
    range = max.to_f - min.to_f

    v.collect{|e| (e.nil? || e.nan?) ? e : min + range * (e.to_f - v_min) / v_range } 
  end

  def self.sum(list)
    list.compact.inject(0.0){|acc,e| acc += e }
  end

  def self.mean(list)
    sum(list.compact.collect{|v| v.to_f } ) / list.compact.length
  end

  def self.median(array)
    sorted = array.sort
    len = sorted.length
    (sorted[(len - 1) / 2] + sorted[len / 2]).to_f / 2
  end

  def self.variance(list)
    return nil if list.length < 2
    mean = mean(list)
    list = list.compact
    list_length = list.length

    total_square_distance = 0.0
    list.each do |value|
      distance = value.to_f - mean
      total_square_distance += distance * distance
    end

    total_square_distance / (list_length - 1)
  end

  def self.sd(list)
    return nil if list.length < 2
    variance = self.variance(list)
    Math.sqrt(variance)
  end

  def self.counts(array)
    counts = {}
    array.each do |e|
      counts[e] ||= 0
      counts[e] += 1
    end

    counts
  end

  def self.proportions(array)
    total = array.length

    proportions = Hash.new 0

    array.each do |e|
      proportions[e] += 1.0 / total
    end

    class << proportions; self; end.class_eval do
      def to_s
        sort{|a,b| a[1] == b[1] ? a[0] <=> b[0] : a[1] <=> b[1]}.collect{|k,c| "%3d\t%s" % [c, k]} * "\n"
      end
    end

    proportions
  end

  def self.zscore(e, list)
    m = Misc.mean(list)
    sd = Misc.sd(list)
    (e.to_f - m) / sd
  end

  def self.softmax(array)
		# Compute the exponentials of the input array elements
		exp_array = array.map { |x| Math.exp(x) }

		# Sum of all exponentials
		sum_exp = exp_array.sum

		# Compute the softmax values by dividing each exponential by the sum of exponentials
		softmax_array = exp_array.map { |x| x / sum_exp }

		return softmax_array
	end
end
