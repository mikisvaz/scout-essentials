require_relative '../indiferent_hash'
module Path

  def self.caller_file(file = nil)
    if file.nil?
      caller_dup = caller.dup
      while file = caller_dup.shift
        break unless file =~ /(?:scout|rbbt)\/(?:resource\.rb|workflow\.rb)/ or
          file =~ /(?:scout|rbbt)\/(?:.*\/)?(path|open|final|tsv|refactor)\.rb/ or
          file =~ /(?:scout|rbbt)\/(?:.*\/)?path\/(?:find|refactor|util)\.rb/ or
          file =~ /(?:scout|rbbt)\/persist.rb/ or
          file =~ /(?:scout|rbbt)\/(persist|workflow)\// or
          file =~ /scout\/resource\/produce.rb/ or
          file =~ /modules\/rbbt-util/ or
          file =~ /^<internal:/
      end
      return nil if file.nil?
      file = file.sub(/\.rb[^\w].*/,'.rb')
    end
    file
  end

  def self.caller_lib_dir(file = nil, relative_to = ['lib', 'bin'])

    file = caller_file(file)

    return nil if file.nil?

    file = File.expand_path(file)

    return File.dirname(file) if not relative_to

    relative_to = [relative_to] unless Array === relative_to

    if relative_to.select{|d| File.exist? File.join(file, d)}.any? 
      return Path.setup(file)
    end

    while file != '/'
      dir = File.dirname file

      return dir if relative_to.select{|d| File.exist? File.join(dir, d)}.any?

      file = File.dirname file
    end

    return nil
  end

  def self.follow(path, map, map_name = nil)
    map = File.join(map, '{PATH}') unless map.include?("{")
    if path.respond_to?(:pkgdir)
      pkgdir = path.pkgdir
      pkgdir = pkgdir.pkgdir while pkgdir.respond_to?(:pkgdir)
    end
    pkgdir = Path.default_pkgdir if pkgdir.nil?
    file = map.sub('{PKGDIR}', pkgdir).
      sub('{HOME}', ENV["HOME"]).
      sub('{RESOURCE}', path.pkgdir.to_s).
      sub('{PWD}'){ FileUtils.pwd }.
      sub('{TOPLEVEL}'){ path._toplevel }.
      sub('{SUBPATH}'){ path._subpath }.
      sub('{BASENAME}'){ File.basename(path)}.
      sub('{PATH}', path).
      sub('{LIBDIR}'){ path.libdir || (path.pkgdir.respond_to?(:libdir) && path.pkgdir.libdir) || Path.caller_lib_dir || "NOLIBDIR" }.
      sub('{MAPNAME}', map_name.to_s).
      sub('{REMOVE}/', '').
      sub('{REMOVE}', '')

    while true
      file.gsub!(/\{(.+)(?<!\\)\/(.+)(?<!\\)\/(.+)\}/) do |m|
        key, orig, replace = m.split(/(?<!\\)\//).collect{|p| p.gsub('\/','/') }
        key_text = follow(path, "#{key}}", map_name)
        key_text[orig] = replace[0..-2] if key_text.include?(orig)
        key_text
      end || break
    end

    file
  end

  def self.path_maps
    @@path_maps ||= IndiferentHash.setup({
      :current => "{PWD}/{TOPLEVEL}/{SUBPATH}",
      :user    => "{HOME}/.{PKGDIR}/{TOPLEVEL}/{SUBPATH}",
      :global  => '/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
      :usr     => '/usr/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
      :local   => '/usr/local/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
      :fast    => '/fast/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
      :cache   => '/cache/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
      :bulk    => '/bulk/{TOPLEVEL}/{PKGDIR}/{SUBPATH}',
      :lib     => '{LIBDIR}/{TOPLEVEL}/{SUBPATH}',
      :scout_essentials_lib => File.join(Path.caller_lib_dir(__FILE__), "{TOPLEVEL}/{SUBPATH}"),
      :tmp     => '/tmp/{PKGDIR}/{TOPLEVEL}/{SUBPATH}',
      :default => :user
    })
  end

  def self.basic_map_order
    @@basic_map_order ||= %w(current workflow user local global usr lib fast cache bulk).collect{|m| m.to_sym }
  end

  def self.map_order
    @@map_order ||= 
      begin
        all_maps = path_maps.keys.collect{|m| m.to_s }.reverse
        basic_map_order = self.basic_map_order.collect{|m| m.to_s }

        lib_maps = all_maps.select{|m| m.end_with?('_lib') }
        basic_map_order[basic_map_order.index 'lib'] = lib_maps + ['lib']
        basic_map_order.flatten!

        (basic_map_order & all_maps) + (all_maps - basic_map_order)
      end.collect{|m| m.to_sym }
  end

  def self.add_path(name, map)
    path_maps[name] = map
    @@map_order = nil
  end

  def self.prepend_path(name, map)
    path_maps[name] = map
    map_order.unshift(name.to_sym)
  end

  def self.append_path(name, map)
    path_maps[name] = map
    map_order.push(name.to_sym)
  end

  def map_order
    @map_order ||= 
      begin
        all_maps = path_maps.keys.collect{|m| m.to_s }.reverse
        basic_map_order = Path.map_order.collect{|m| m.to_s }

        (basic_map_order & all_maps) + (all_maps - basic_map_order)
      end.collect{|m| m.to_sym }
  end

  def add_path(name, map)
    path_maps[name] = map
    @map_order = nil
  end

  def prepend_path(name, map)
    path_maps[name] = map
    map_order.unshift(name.to_sym)
  end

  def append_path(name, map)
    path_maps[name] = map
    map_order.push(name.to_sym)
  end

  def self.load_path_maps(filename)
    Path.setup(filename) unless Path === filename
    if filename.exist?
      filename = filename.find
      begin
        Log.debug "Loading search_paths from #{filename}"
        YAML.load(filename.read).each do |where, location|
          add_path where.to_sym, location
        end
      rescue
        Log.error "Error loading search_paths from #{filename}: " << $!.message
      end
    else
      Log.debug "Could not find search_paths file #{filename}"
    end
  end

  def _parts
    @_parts ||= self.split("/")
  end

  def _subpath
    @subpath ||= _parts.length > 1 ? _parts[1..-1] * "/" : nil
  end

  def _toplevel
    @toplevel ||= _parts[0]
  end

  HOME = "~"[0]
  SLASH = "/"[0]
  DOT = "."[0]
  def self.located?(path)
    # OPEN RESOURCE
    path.slice(0,1) == SLASH || 
      (path.slice(0,1) == HOME && path.slice(1,1) == SLASH) ||
      (path.slice(0,1) == DOT && path.slice(1,1) == SLASH)
  end

  def located?
    Path.located?(self)
  end

  def annotate_found_where(found, where)
    self.annotate(found).tap{|p| 
      p.instance_variable_set("@where", where) 
      p.instance_variable_set("@original", self.dup) 
    }
  end

  def where
    @where
  end

  def original
    @original
  end

  def follow(map_name = :default, annotate = true)
    IndiferentHash.setup(path_maps)
    map = path_maps[map_name] || Path.path_maps[map_name]
    if map.nil? && String === map_name
      map = File.join(map_name, '{TOPLEVEL}/{SUBPATH}')
    end
    raise "Map not found #{Log.fingerprint map_name} not in #{Log.fingerprint path_maps.keys}" if map.nil?
    while Symbol === map
      map_name = map
      map = path_maps[map_name]
    end
    found = Path.follow(self, map, map_name)

    annotate_found_where(found, map_name)  if annotate

    found
  end

  def self.exists_file_or_alternatives(file)
    file = file.dup if Path === file
    return file if Open.exist?(file) or Open.directory?(file)
    %w(gz bgz zip).each do |extension|
      alt_file = file + '.' + extension
      return alt_file if Open.exist?(alt_file) or Open.directory?(alt_file)
    end
    nil
  end

  def find(where = nil)
    if located?
      if File.exist?(File.expand_path(self))
        return self.annotate(File.expand_path(self))
      else
        found = Path.exists_file_or_alternatives(self)
        if found
          return self.annotate(found)
        else
          return self
        end
      end
    end

    return find_all if where == 'all' || where == :all

    return follow(where) if where

    map_order.each do |map_name|
      next unless path_maps.include?(map_name)
      found = follow(map_name, false)

      found = Path.exists_file_or_alternatives(found)
      return annotate_found_where(found, map_name) if found
    end

    return follow(:default)
  end

  def exist?
    # OPEN
    found = self.find
    File.exist?(found) || File.directory?(found)
  end

  alias exists? exist?

  def find_all(caller_lib = nil, search_paths = nil)
    map_order
      .collect{|where| find(where) }
      .select{|file| file.exist? }.uniq
  end

  def find_with_extension(extension, *args)
    found = self.find(*args)
    return found if found.exists? && ! found.directory?
    found_with_extension = self.set_extension(extension).find
    found_with_extension.exists? ? found_with_extension : found
  end
end
