module Misc
  def self.in_dir(dir)
    old_pwd = FileUtils.pwd
    begin
      FileUtils.mkdir_p dir unless File.exist?(dir)
      FileUtils.cd dir
      yield
    ensure
      FileUtils.cd old_pwd
    end
  end

  def self.path_relative_to(basedir, path)
    path = File.expand_path(path) unless path.slice(0,1) == "/"
    basedir = File.expand_path(basedir) unless basedir.slice(0,1) == "/"

    basedir += "/" unless basedir.slice(-2,-1) == "/"

    if path.start_with?(basedir)
      return path.slice(basedir.length, basedir.length)
    else
      return nil
    end
  end

  def self.tarize_cmd(path, dest = nil)
    Misc.in_dir(path) do
      if dest
        CMD.cmd("tar cvfz '#{dest}' '.'")
      else
        CMD.cmd("tar cvfz - '.'", :pipe => true)
      end
    end
  end

  def self.tarize(source_dir, archive_path)
    require 'rubygems/package'
    require 'zlib'
    require 'stringio'
    require 'fileutils'

    tar_io = StringIO.new("")

    Gem::Package::TarWriter.new(tar_io) do |tar|
      Dir[File.join(source_dir, '**', '*')].each do |file|
        relative_path = file.sub(/^#{Regexp.escape(source_dir)}\/?/, '')

        if File.directory?(file)
          tar.mkdir(relative_path, File.stat(file).mode)
        else
          tar.add_file(relative_path, File.stat(file).mode) do |tf|
            File.open(file, 'rb') { |f| tf.write(f.read) }
          end
        end
      end
    end

    tar_io.rewind

    File.open(archive_path, 'wb') do |f|
      gz = Zlib::GzipWriter.new(f)
      gz.write(tar_io.string)
      gz.close
    end
  end

  def self.untar(file, target = '.')
    target = target.find if Path === target
    file = file.find if Path === file
    Misc.in_dir target do
      if IO === file
        CMD.cmd("tar xvfz -", in: file)
      else
        CMD.cmd("tar xvfz '#{file}'")
      end
    end
  end

end
