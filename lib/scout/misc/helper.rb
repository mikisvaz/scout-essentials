module Misc
  def self.intersect_sorted_arrays(a1, a2)
    e1, e2 = a1.shift, a2.shift
    intersect = []
    while true
      break if e1.nil? or e2.nil?
      case e1 <=> e2
      when 0
        intersect << e1
        e1, e2 = a1.shift, a2.shift
      when -1
        e1 = a1.shift while not e1.nil? and e1 < e2
      when 1
        e2 = a2.shift
        e2 = a2.shift while not e2.nil? and e2 < e1
      end
    end
    intersect
  end

  def self.counts(array)
    counts = {}
    array.each do |e|
      counts[e] ||= 0
      counts[e] += 1
    end

    counts
  end

end
