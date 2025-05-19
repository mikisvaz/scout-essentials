module Scout
  extend Resource

  self.pkgdir = 'scout'
end

Resource.default_resource = Scout

Path.load_path_maps(Scout.etc["path_maps"])
