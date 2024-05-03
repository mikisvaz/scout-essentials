module Scout
  extend Resource

  self.pkgdir = 'scout'
end

Path.load_path_maps(Scout.etc["path_maps"])
