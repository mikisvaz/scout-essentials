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
end
