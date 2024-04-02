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

  def self.tarize(path, dest = nil)
    Misc.in_dir(path) do
      if dest
        CMD.cmd("tar cvfz '#{dest}' '.'")
      else
        CMD.cmd("tar cvfz - '.'", :pipe => true)
      end
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
