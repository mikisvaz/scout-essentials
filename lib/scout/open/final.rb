require 'scout/log'
module Open
  def self.get_stream(file, mode = 'r', options = {})
    return file if Open.is_stream?(file)
    return file.stream if Open.has_stream?(file)
    file = file.find if Path === file

    return Open.ssh(file, options) if Open.ssh?(file)
    return Open.wget(file, options) if Open.remote?(file)

    File.open(File.expand_path(file), mode)
  end

  def self.file_write(file, content, mode = 'w')
    File.open(file, mode) do |f|
      begin
        f.flock(File::LOCK_EX)
        f.write content 
        f.flock(File::LOCK_UN)
      ensure
        f.close unless f.closed?
      end
    end
  end

  def self.write(file, content = nil, options = {})
    options = IndiferentHash.add_defaults options, :mode => 'w'

    file = file.find(options[:where]) if Path === file
    mode = IndiferentHash.process_options options, :mode

    Open.mkdir File.dirname(file)

    case
    when block_given?
      begin
        f = File.open(file, mode)
        begin
          yield f
        ensure
          f.close unless f.closed?
        end
      rescue Exception
        FileUtils.rm file if File.exist? file
        raise $!
      end
    when content.nil?
      file_write(file, "", mode)
    when String === content
      file_write(file, content, mode)
    when (IO === content || StringIO === content)
      begin
        File.open(file, mode) do |f| 
          f.flock(File::LOCK_EX)
          while block = content.read(Open::BLOCK_SIZE)
            f.write block
          end
          f.flock(File::LOCK_UN)
        end
      rescue Exception
        FileUtils.rm_rf file if File.exist? file
        raise $!
      end
      content.close unless content.closed?
      content.join if content.respond_to? :join
    else
      raise "Content unknown #{Log.fingerprint content}"
    end

    notify_write(file)
  end

  def append(file, content, options = {})
    options = IndiferentHash.setup options
    options[:mode] = "a"
    write(file, content, options)
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
    file = file.find if Path === file
    FileUtils.rm(file) if File.exist?(file) || Open.broken_link?(file)
  end

  def self.rm_rf(file)
    FileUtils.rm_rf(file)
  end

  def self.touch(file)
    file = file.find if Path === file
    Open.mkdir File.dirname(file)
    FileUtils.touch(file)
  end

  def self.mkdir(target)
    target = target.find if Path === target
    if ! File.exist?(target)
      FileUtils.mkdir_p target
    end
  end

  def self.mkfiledir(target)
    target = target.find if Path === target
    dir = File.dirname(target)
    if ! File.exist?(dir)
      FileUtils.mkdir_p dir
    end
  end

  def self.cp(source, target, options = {})
    source = source.find if Path === source
    target = target.find if Path === target

    FileUtils.mkdir_p File.dirname(target) unless File.exist?(File.dirname(target))
    FileUtils.rm_rf target if File.exist?(target)
    FileUtils.cp_r source, target
  end

  def self.directory?(file)
    file = file.find if Path === file
    File.directory?(file)
  end

  def self.exists?(file)
    file = file.find if Path === file
    File.exist?(File.expand_path(file))
  end

  def self.ctime(file)
    file = file.find if Path === file
    File.ctime(file)
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

  def self.size(file)
    file = file.find if Path === file
    File.size(file)
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
      Log.debug "Could not make regular link, trying symbolic: #{Log.fingerprint(source)} -> #{Log.fingerprint(target)}"
      Open.ln_s(source, target, options)
    end
    nil
  end

  def self.link_dir(source, target)
    Log.debug "Copy with hard-links #{Log.fingerprint source}->#{Log.fingerprint target}"
    FileUtils.cp_lr(source, target)
  end

  def self.same_file(file1, file2)
    File.identical?(file1, file2)
  end

end
