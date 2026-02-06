module Path
  def produce(force = false)
    raise @produced if Exception === @produced
    return self if ! force && (Open.exist?(self.find) || @produced)
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

  def exists?(produce: true)
    return true if Open.exists?(self.find)
    if produce
      self.produce
      Open.exists?(self.find)
    else
      false
    end
  end

  def find_with_extension(extension, *args, produce: true)
    found = self.find(*args)
    return found if found.exists?(produce: produce) && ! found.directory?
    if Array === extension
      extension.each do |ext|
        found_with_extension = self.set_extension(ext).find
        return found_with_extension if found_with_extension.exists?(produce: produce)
      end
    else
      found_with_extension = self.set_extension(extension).find
      return found_with_extension if found_with_extension.exists?(produce: produce)
    end
    return found
  end
end
