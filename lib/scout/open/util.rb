module Open
  GREP_CMD = begin
               if ENV["GREP_CMD"] 
                 ENV["GREP_CMD"]
               elsif File.exist?('/bin/grep')
                 "/bin/grep"
               elsif File.exist?('/usr/bin/grep')
                 "/usr/bin/grep"
               else
                 "grep"
               end
             end

  def self.grep(stream, grep, invert = false, fixed = nil, options = {})
    case 
    when Array === grep
      TmpFile.with_file(grep * "\n", false) do |f|
        if FalseClass === fixed
          CMD.cmd("#{GREP_CMD} #{invert ? '-v' : ''} -", "-f" => f, :in => stream, :pipe => true, :post => proc{FileUtils.rm f})
        else
          CMD.cmd("#{GREP_CMD} #{invert ? '-v' : ''} -", "-w" => true, "-F" => true, "-f" => f, :in => stream, :pipe => true, :post => proc{FileUtils.rm f})
        end
      end
    else
      CMD.cmd("#{GREP_CMD} #{invert ? '-v ' : ''} '#{grep}' -", :in => stream, :nofail => true, :pipe => true, :post => proc{begin stream.force_close; rescue Exception; end if stream.respond_to?(:force_close)})
    end
  end

  def self.gzip_pipe(file)
    Open.gzip?(file) ? "<(gunzip -c '#{file}')" : "'#{file}'"
  end

  def self.bgunzip(stream)
    Bgzf.setup stream
  end
   
  def self.gunzip(stream)
    CMD.cmd('zcat', :in => stream, :pipe => true, :no_fail => true, :no_wait => true)
  end

  def self.gzip(stream)
    CMD.cmd('gzip', :in => stream, :pipe => true, :no_fail => true, :no_wait => true)
  end

  def self.bgzip(stream)
    CMD.cmd('bgzip', :in => stream, :pipe => true, :no_fail => true, :no_wait => true)
  end

  def self.unzip(stream)
    TmpFile.with_file(stream.read) do |filename|
      StringIO.new(CMD.cmd("unzip '{opt}' #{filename}", "-p" => true, :pipe => true).read)
    end
  end

  # Questions
  def self.gzip?(file)
    file = file.find if Path === file
    !! (file =~ /\.gz$/)
  end

  def self.bgzip?(file)
    file = file.find if Path === file
    !! (file =~ /\.bgz$/)
  end

  def self.zip?(file)
    file = file.find if Path === file
    !! (file =~ /\.zip$/)
  end

  def self.is_stream?(obj)
    IO === obj || StringIO === obj
  end

  def self.has_stream?(obj)
    obj.respond_to?(:stream)
  end


  def self.notify_write(file)
    begin
      notification_file = file + '.notify'
      if Open.exists? notification_file
        key = Open.read(notification_file).strip
        key = nil if key.empty?
        if key && key.include?("@")
          to = from = key
          subject = "Wrote " << file
          message = "Content attached"
          Misc.send_email(from, to, subject, message, :files => [file])
        else
          Misc.notify("Wrote " << file, nil, key)
        end
        Open.rm notification_file
      end
    rescue
      Log.exception $!
      Log.warn "Error notifying write of #{ file }"
    end
  end

  def self.broken_link?(path)
    File.symlink?(path) && ! File.exist?(File.readlink(path))
  end

  class << self; alias exist? exists? end

  def self.exist_or_link?(file)
    self.exists?(file) || File.symlink?(file)
  end

  def self.writable?(path)
    path = path.find if Path === path
    if File.symlink?(path)
      File.writable?(File.dirname(path))
    elsif File.exist?(path)
      File.writable?(path)
    else
      File.writable?(File.dirname(File.expand_path(path)))
    end
  end

  def self.realpath(file)
    file = file.find if Path === file
    Pathname.new(File.expand_path(file)).realpath.to_s 
  end

  def self.list(file)
    file = file.produce_and_find if Path === file
    Open.read(file).split("\n")
  end
end
