require_relative 'log'
require_relative 'path'
require_relative 'resource/produce'
require_relative 'resource/path'
require_relative 'resource/open'
require_relative 'resource/util'
require_relative 'resource/software'
require_relative 'resource/sync'

require_relative 'log'
require_relative 'path'
require_relative 'resource/produce'
require_relative 'resource/path'
require_relative 'resource/open'
require_relative 'resource/util'
require_relative 'resource/software'
require_relative 'resource/sync'

module Resource
  extend Annotation
  annotation :pkgdir, :libdir, :subdir, :resources, :rake_dirs, :path_maps, :map_order, :lock_dir

  class << Resource
    attr_accessor :default_resource

    def default_resource
      @default_resource
    end
  end

  def self.default_lock_dir
    Path.setup('tmp/produce_locks').find
  end

  def path_maps
    @path_maps ||= Path.path_maps.dup
  end

  def map_order
    @map_order ||= Path.map_order.dup
  end

  def prepend_path(name, map)
    path_maps[name] = map
    map_order.unshift(name.to_sym)
  end

  def append_path(name, map)
    path_maps[name] = map
    map_order.push(name.to_sym)
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
