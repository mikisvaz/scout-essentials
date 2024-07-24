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

  def self.directory?(file)
    file = file.find if Path === file
    File.directory?(file)
  end

  def self.exists?(file)
    file = file.find if Path === file
    File.exist?(file)
  end
  class << self; alias exist? exists? end

  def self.exist_or_link?(file)
    self.exists?(file) || File.symlink?(file)
  end

  def self.mv(source, target, options = {})
    target = target.find if Path === target
    source = source.find if Path === source
    FileUtils.mkdir_p File.dirname(target) unless File.exist?(File.dirname(target))
    tmp_target = File.join(File.dirname(target), '.tmp_mv.' + File.basename(target))
    FileUtils.mv source, tmp_target
    FileUtils.mv tmp_target, target
    return nil
  end

  def self.rm(file)
    FileUtils.rm(file) if File.exist?(file) || Open.broken_link?(file)
  end

  def self.rm_rf(file)
    FileUtils.rm_rf(file)
  end

  def self.touch(file)
    FileUtils.touch(file)
  end

  def self.mkdir(target)
    target = target.find if Path === target
    if ! File.exist?(target)
      FileUtils.mkdir_p target
    end
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

  def self.ctime(file)
    file = file.find if Path === file
    File.ctime(file)
  end

  def self.realpath(file)
    file = file.find if Path === file
    Pathname.new(File.expand_path(file)).realpath.to_s 
  end

  def self.mtime(file)
    file = file.find if Path === file
    begin
      if File.symlink?(file) || File.stat(file).nlink > 1
        if File.exist?(file + '.info') && defined?(Step)
          done = Persist.load(file + '.info', Step::SERIALIZER)[:done]
          return done if done
        end

        file = Pathname.new(file).realpath.to_s 
      end
      return nil unless File.exist?(file)
      File.mtime(file)
    rescue
      nil
    end
  end

  def self.cp(source, target, options = {})
    source = source.find if Path === source
    target = target.find if Path === target

    FileUtils.mkdir_p File.dirname(target) unless File.exist?(File.dirname(target))
    FileUtils.rm_rf target if File.exist?(target)
    FileUtils.cp_r source, target
  end


  def self.ln_s(source, target, options = {})
    source = source.find if Path === source
    target = target.find if Path === target

    target = File.join(target, File.basename(source)) if File.directory? target
    FileUtils.mkdir_p File.dirname(target) unless File.exist?(File.dirname(target))
    FileUtils.rm target if File.exist?(target)
    FileUtils.rm target if File.symlink?(target)
    FileUtils.ln_s source, target
  end

  def self.ln(source, target, options = {})
    source = source.find if Path === source
    target = target.find if Path === target
    source = File.realpath(source) if File.symlink?(source)

    FileUtils.mkdir_p File.dirname(target) unless File.exist?(File.dirname(target))
    FileUtils.rm target if File.exist?(target)
    FileUtils.rm target if File.symlink?(target)
    FileUtils.ln source, target
  end

  def self.ln_h(source, target, options = {})
    source = source.find if Path === source
    target = target.find if Path === target

    FileUtils.mkdir_p File.dirname(target) unless File.exist?(File.dirname(target))
    FileUtils.rm target if File.exist?(target)
    begin
      CMD.cmd("ln -L '#{ source }' '#{ target }'")
    rescue ProcessFailed
      Log.debug "Could not hard link #{source} and #{target}: #{$!.message.gsub("\n", '. ')}"
      CMD.cmd("cp -L '#{ source }' '#{ target }'")
    end
  end

  def self.link(source, target, options = {})
    begin
      Open.ln(source, target, options)
    rescue
      Log.debug "Could not make regular link, trying symbolic: #{Misc.fingerprint(source)} -> #{Misc.fingerprint(target)}"
      Open.ln_s(source, target, options)
    end
    nil
  end

  def self.link_dir(source, target)
    Log.debug "Copy with hard-links #{Log.fingerprint source}->#{Log.fingerprint target}"
    FileUtils.cp_lr(source, target)
  end

  def self.list(file)
    file = file.produce_and_find if Path === file
    Open.read(file).split("\n")
  end
end
