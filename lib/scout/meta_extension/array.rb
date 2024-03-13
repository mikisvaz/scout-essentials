module ExtendedArray

  module ExtendedArrayItem
    attr_accessor :container, :container_index
  end
  
  def self.is_contained?(obj)
    ExtendedArrayItem === obj
  end

  def annotate_item(obj, position = nil)
    obj = obj.dup if obj.frozen?
    obj.extend ExtendedArray if Array === obj
    obj.extend ExtendedArrayItem
    obj.container = self
    obj.container_index = position
    self.annotate(obj)
  end

  def [](pos, clean = false)
    item = super(pos)
    return item if item.nil? or clean
    annotate_item(item, pos)
  end

  def first
    annotate_item(super, 0)
  end

  def last
    annotate_item(super, self.length - 1)
  end

  def each_with_index(&block)
    super do |item,i|
      block.call annotate_item(item, i)
    end
  end

  def each(&block)
    i = 0
    super do |item|
      block.call annotate_item(item, i)
      i += 1
    end
  end

  def inject(acc, &block)
    each do |item|
      acc = block.call acc, item
    end
    acc
  end

  def collect(&block)
    if block_given?
      inject([]){|acc,item| acc.push(block.call(item)); acc }
    else
      inject([]){|acc,item| acc.push(item); acc }
    end
  end

  %w(compact uniq flatten reverse sort_by).each do |method|

    self.define_method(method) do |*args|
      res = super(*args)

      annotate(res)
      res.extend ExtendedArray

      res
    end
  end
end
