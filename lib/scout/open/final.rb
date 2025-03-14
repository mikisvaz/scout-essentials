require 'scout/log'
module Open
  def self.get_stream(file, mode = 'r', options = {})
    return file if Open.is_stream?(file)
    return file.stream if Open.has_stream?(file)
    file = file.find if Path === file

    return Open.ssh(file, options) if Open.ssh?(file)
    return Open.wget(file, options) if Open.remote?(file)

    File.open(file, mode)
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
    File.exist?(file)
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
end
