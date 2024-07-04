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

  # Divides the array into chunks of size +size+ by taking
  # consecutive elements. If a block is given it runs it
  # instead of returning the chunks
  def self.chunk(array, size)
    total = array.length
    current = 0
    res = [] unless block_given?
    while current < total
      last = current + size - 1
      if block_given?
        yield array[current..last]
      else
        res << array[current..last]
      end
      current = last + 1
    end
    block_given? ? nil : res
  end

  # Divides the array into +num+ chunks of the same size by placing one
  # element in each chunk iteratively.
  def self.divide(array, num)
    num = 1 if num == 0
    chunks = []
    num.to_i.times do chunks << [] end
    array.each_with_index{|e, i|
      c = i % num
      chunks[c] << e
    }
    chunks
  end

  # Divides the array into chunks of +num+ same size by placing one
  # element in each chunk iteratively.
  def self.ordered_divide(array, num)
    last = array.length - 1
    chunks = []
    current = 0
    while current <= last
      next_current = [last, current + num - 1].min
      chunks << array[current..next_current]
      current = next_current + 1
    end
    chunks
  end

end
