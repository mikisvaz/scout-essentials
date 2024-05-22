require_relative 'log'
require_relative 'path'
require_relative 'resource/produce'
require_relative 'resource/path'
require_relative 'resource/open'
require_relative 'resource/util'
require_relative 'resource/software'

module Resource
  extend Annotation
  annotation :pkgdir, :libdir, :subdir, :resources, :rake_dirs, :path_maps, :map_order, :lock_dir

  class << Resource
    attr_accessor :default_resource

    def default_resource
      @default_resource ||= Scout
    end
  end

  def self.default_lock_dir
    Path.setup('tmp/produce_locks').find
  end

  def path_maps
    @path_maps ||= Path.path_maps.dup
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
    Path.setup(subdir.dup, self, self.libdir, @path_maps, @map_order)
  end

  def method_missing(name, prev = nil, *args)
    if prev.nil?
      root.send(name, *args)
    else
      root.send(name, prev, *args)
    end
  end
end
