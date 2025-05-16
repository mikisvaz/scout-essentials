module Path
  def no_method_missing
    class << self
      undef_method :method_missing
    end
  end

  def self.is_filename?(string, need_to_exists = true)
    return false if string.nil?
    return true if Path === string
    return true if String === string and
      ! string.include?("\n") and
      (string.length < 265 || string.split("/").select{|p| p.length > 265 }.empty?) and
      (! need_to_exists || File.exist?(string))
    return false
  end

  def self.sanitize_filename(filename, length = 254)
    if filename.length > length
      if filename =~ /(\..{2,9})$/
        extension = $1
      else
        extension = ''
      end

      post_fix = "--#{filename.length}@#{length}_#{Misc.digest(filename)[0..4]}" + extension

      filename = filename[0..(length - post_fix.length - 1)] << post_fix
    else
      filename
    end
    filename
  end

  def directory?
    return nil unless self.exist?
    File.directory?(self.find)
  end

  def sub(*args)
    self.annotate super(*args)
  end

  def dirname
    self.annotate(File.dirname(self))
  end

  def basename
    self.annotate(File.basename(self))
  end

  def glob(pattern = "*")
    if self.include? "*"
      if located?
        Dir.glob(self)
      else
        self.glob_all
      end
    else
      return [] unless self.exist? 
      found = self.find

      exp = File.join(found, pattern)
      paths = Dir.glob(exp).collect{|f| self.annotate(f) }

      paths.each do |p|
        p.original = File.join(found.original, p.sub(/^#{found}/, ''))
      end if found.original

      paths
    end
  end

  def glob_all(pattern = nil, caller_lib = nil, search_paths = nil)
    search_paths ||= self.path_maps || Path.path_maps
    search_paths = search_paths.dup

    search_paths.keys.collect do |where| 
      found = find(where)

      paths = pattern ? found.glob(pattern) : found.glob

      paths = paths.collect{|p| self.annotate p }

      paths = paths.each do |p|
        p.original = File.join(found.original, p.sub(/^#{found}/, ''))
        p.where = where
      end if found.original and pattern

      paths
    end.flatten.uniq
  end

  def get_extension(multiple = false)
    parts = File.basename(self).split(".")
    extension = [parts.pop]

    while parts.length < 5
      extension << [parts.pop]
    end if multiple

    extension * "."
  end

  def set_extension(extension)
    self.annotate(self + ".#{extension}")
  end

  def unset_extension
    parts = self.split("/")
    basename = parts.pop
    return self unless basename.include?(".")
    basename = basename.split(".")[0..-2] * "."
    parts.push basename
    self.annotate(parts * "/")
  end

  def remove_extension(extension = nil)
    if extension.nil?
      unset_extension
    else
      self.annotate(self.sub(/\.#{extension}$/,''))
    end
  end

  def replace_extension(new_extension = nil, multiple = false)
    if String === multiple
      new_path = self.sub(/(\.[^\.\/]{1,5})(.#{multiple})?$/,'')
    elsif multiple
      new_path = self.sub(/(\.[^\.\/]{1,5})+$/,'')
    else
      new_path = self.sub(/\.[^\.\/]{1,5}$/,'')
    end
    new_path = new_path + "." + new_extension.to_s
    self.annotate(new_path)
  end


  # Is 'file' newer than 'path'? return non-true if path is newer than file
  def self.newer?(path, file, by_link = false)
    return true if not Open.exists?(file)
    path = path.find if Path === path
    file = file.find if Path === file
    if by_link
      patht = File.exist?(path) ? File.lstat(path).mtime : nil
      filet = File.exist?(file) ? File.lstat(file).mtime : nil
    else
      patht = Open.mtime(path)
      filet = Open.mtime(file)
    end
    return true if patht.nil? || filet.nil?
    diff = patht - filet
    return diff if diff < 0
    return false
  end
end
