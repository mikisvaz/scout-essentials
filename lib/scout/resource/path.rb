module Path
  def produce(force = false)
    raise @produced if Exception === @produced
    return self if ! force && (Open.exist?(self) || @produced)
    begin
      if Resource === self.pkgdir
        self.pkgdir.produce self, force
      else
        false
      end
    rescue ResourceNotFound
      @produced = false
    rescue
      message = $!.message
      message = "No exception message" if message.nil? || message.empty?
      Log.warn "Error producing #{self}: #{message}"
      raise $!
    ensure
      @produced = true if @produced.nil?
    end
  end

  def produce_with_extension(extension, *args)
    begin
      self.produce(*args)
    rescue Exception
      exception = $!
      begin
        self.set_extension(extension).produce(*args)
      rescue Exception
        raise exception
      end
    end
  end

  def produce_and_find(extension = nil, *args)
    found = if extension
              found = find_with_extension(extension, *args)
              found.exists? ? found : produce_with_extension(extension, *args)
            else
              found = find
              found.exists? ? found : produce(*args)
            end
    raise "Not found: #{self}" unless found

    found
  end

  def relocate
    return self if Open.exists?(self)
    Resource.relocate(self)
  end

  def identify
    Resource.identify(self)
  end

  def open(*args, &block)
    produce
    Open.open(self, *args, &block)
  end

  def read
    produce
    Open.read(self)
  end

  def write(*args, &block)
    Open.write(self.find, *args, &block)
  end

  def list
    found = produce_and_find('list')
    Open.list(found)
  end

  def exists?
    return true if Open.exists?(self.find)
    self.produce
  end
end
