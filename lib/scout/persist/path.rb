require_relative 'open'

module Path
  def yaml(*rest, &block)
    Open.yaml(self, *rest, &block)
  end

  def json(*rest, &block)
    Open.json(self, *rest, &block)
  end

  def marshal(*rest, &block)
    Open.marshal(self, *rest, &block)
  end
end
