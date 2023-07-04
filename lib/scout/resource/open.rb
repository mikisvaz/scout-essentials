class << Open
  alias _just_open open

  def open(file, *args, **kwargs, &block)
    file.produce if Path === file
    _just_open(file, *args, **kwargs, &block)
  end
end
