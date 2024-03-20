require_relative 'log'
require_relative 'path'
require_relative 'resource/produce'
require_relative 'resource/path'
require_relative 'resource/open'
require_relative 'resource/util'
require_relative 'resource/software'

module Resource
  extend Annotation
  annotation :pkgdir, :libdir, :subdir, :resources, :rake_dirs, :path_maps, :lock_dir

  def self.default_lock_dir
    Path.setup('tmp/produce_locks').find
  end

  def subdir
    @subdir ||= ""
  end

  def lock_dir
    @lock_dir ||= Resource.default_lock_dir
  end

  def pkgdir
    @pkgdir ||= Path.default_pkgdir
  end

  def root
    Path.setup(subdir, self, self.libdir, @path_maps)
  end

  def method_missing(name, prev = nil, *args)
    if prev.nil?
      root.send(name, *args)
    else
      root.send(name, prev, *args)
    end
  end
end
