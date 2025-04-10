require 'scout/open/sync'
module Resource
  def self.sync(path, map = nil, options = {})
    resource = IndiferentHash.process_options options, 
      :resource

    map = 'user' if map.nil?
    resource = path.pkgdir if resource.nil? and path.is_a?(Path) and path.pkgdir.is_a?(Resource)
    resource = Resource.default_resource if resource.nil?

    target = resource.identify(path).find(map)

    if File.exist?(path)
      real_paths = [path]
    else
      path = Path.setup(path, pkgdir: resource) unless path.is_a?(Path)
      real_paths = path.directory? ? path.find_all : path.glob_all
    end

    real_paths.each do |source|
      Open.sync(source, target, options)
    end
  end
end
