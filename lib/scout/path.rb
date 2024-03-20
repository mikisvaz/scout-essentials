require_relative 'annotation'
require_relative 'path/find'
require_relative 'path/util'
require_relative 'path/tmpfile'

module Path
  extend Annotation
  annotation :pkgdir, :libdir, :path_maps

  def self.default_pkgdir
    @@default_pkgdir ||= 'scout'
  end
  
  def self.default_pkgdir=(pkgdir)
    @@default_pkgdir = pkgdir
  end

  def pkgdir
    @pkgdir ||= Path.default_pkgdir
  end

  def libdir
    @libdir || Path.caller_lib_dir
  end

  def path_maps
    @path_maps ||= Path.path_maps.dup
  end

  def join(subpath = nil, prevpath = nil)
    return self if subpath.nil?

    subpath = subpath.to_s if Symbol === subpath
    prevpath = prevpath.to_s if Symbol === prevpath

    subpath = File.join(prevpath.to_s, subpath) if prevpath
    new = self.empty? ? subpath.dup : File.join(self, subpath)
    self.annotate(new)
    new
  end

  alias [] join
  alias / join

  def method_missing(name, prev = nil, *args, &block)
    if block_given? || name.to_s.start_with?('to_')
      super name, prev, *args, &block
    else
      join(name, prev)
    end
  end

end
