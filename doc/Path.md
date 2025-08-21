# Path

Path is a lightweight path utility layered on top of the framework's Annotation system. It makes it easy to build, transform and locate resources by logical name across a variety of search maps (current, user, global, lib, etc.). Path objects are plain string values extended with Path behavior (via Path.setup or by extending instances). Many Open/Path helpers accept Path objects and will call `.find` / `.find_all` / `.produce_and_find` as needed.

Key features:
- Build and compose path strings fluently (join, /, method_missing).
- Map logical names to physical locations using configurable path maps.
- Find the first existing file across map order or list all matches.
- Helpers for file extension manipulation, globbing, dirname/basename, sanitizing filenames.
- Integration with Open and TmpFile utilities; supports annotation (pkgdir, libdir, map configuration).
- Helpers for digest/MD5 summary for files and directories.

---

## Creating / wrapping Path values

- Path.setup(str, pkgdir = nil)
  - Convert a string into a Path (i.e., extend it with Path methods). Many test examples call `Path.setup("...")`.
  - A Path is just a String extended with Path behavior and optional annotations (`pkgdir`, `libdir`, `path_maps`, `map_order`).

Shortcuts on Path instances:
- join(subpath, prevpath = nil) — join subpath to the Path (returns annotated Path)
  - Aliases: [] and /
  - Example:
    ```ruby
    p = Path.setup('/tmp')
    p.join(:foo)        # => "/tmp/foo"
    p[:bar, :foo]       # => "/tmp/bar/foo"
    p / :foo            # => "/tmp/foo"
    ```

- method_missing is used to make `path.component` behave like join:
  - `path.foo` → join("foo")
  - Be careful: methods starting `to_` or blocks will not be treated as path components.

---

## Package / library defaults

- Path.default_pkgdir and Path.default_pkgdir= — global default package dir (default `'scout'`).
- Instance attributes:
  - pkgdir — per-path override of package directory (defaults to Path.default_pkgdir).
  - libdir — library directory (attempts to infer caller lib dir).
  - path_maps — instance copy of global path maps (modifiable per-path).
  - map_order — instance map order (derived from global map_order unless overridden).

---

## Path maps and find behavior

Path maps let you define templates where logical paths can be found on disk. The module ships a sensible set of maps (current, user, global, usr, local, fast, cache, bulk, lib, tmp, …) and a default map order.

- Path.path_maps — global IndiferentHash of map templates (strings containing placeholders like {TOPLEVEL}, {PKGDIR}, {SUBPATH}, {PATH}, {LIBDIR}, etc.)
- Path.map_order / Path.basic_map_order — global order to search maps.
- You can add or change maps:
  - Path.add_path(name, map)
  - Path.prepend_path(name, map)
  - Path.append_path(name, map)
  - For a Path instance you can also call add_path / prepend_path / append_path (instance-level override).

Templates can reference:
- {PKGDIR}, {HOME}, {RESOURCE}, {PWD}, {TOPLEVEL}, {SUBPATH}, {BASENAME}, {PATH}, {LIBDIR}, {MAPNAME}, and custom substitutions.

Finding:
- Path#follow(map_name = :default) — substitute template tokens and return the resulting path string (annotated). Does not check existence. Annotates result with `.where` and `.original` when requested (see annotate_found_where).
- Path#find(where = nil) — search for the first existing file for the Path:
  - If path is absolute (located?), returns itself if exists or checks alternatives (.gz, .bgz, .zip).
  - If where is given, uses that map name only.
  - If where == :all returns an array of matching paths (see find_all).
  - Otherwise iterates configured map_order and returns the first found path (annotated with `.where` and `.original`).
- Path#find_all — returns all existing matches across map_order (useful to locate duplicates).
- Path#find_with_extension(extension, *args) — try original then the given extension.
- Path.exists_file_or_alternatives(file) — helper that checks for file or file.gz/.bgz/.zip alternatives.

Helpers for locating:
- Path.located?(path) / instance located? — returns true if path is absolute (~/, /, ./).
- Path.caller_file / Path.caller_lib_dir — helper to find the caller's script dir / lib directory (used to set libdir defaults and map values).
- Path.follow supports advanced `{PATH/old/new}` style substitutions (see tests showing `Path.follow(path, "/some_dir/{PATH/scout/scout_commands}")`).

When a find succeeds, Path#set attributes:
- found.where — the map name used to find the file
- found.original — original logical path string before substitution

---

## Globbing and directory utilities

- Path#glob(pattern = "*") — list children matching pattern if this Path points to a directory; returns annotated Path instances.
- Path#glob_all(pattern = nil) — search across path maps and return all matching annotated paths.
- Path#directory? — true if the found path is a directory.
- Path.dirname / Path.basename — string helpers returning annotated strings.

---

## Filename / extension utilities

- Path.is_filename?(string, need_to_exists = true) — static predicate to test if a value looks like a filename.
- Path.sanitize_filename(filename, length = 254) — shorten a filename safely preserving an extension and adding a digest postfix when needed.
- Extension helpers:
  - get_extension(multiple = false) — last extension or multiple.
  - set_extension(extension) — return path with extension appended.
  - unset_extension — remove last extension.
  - remove_extension(extension = nil) — remove a specific extension or unset last.
  - replace_extension(new_extension, multiple = false) — replace extension(s).
- Path.relative_to(dir) — returns relative path from dir to this path (uses Misc.path_relative_to).

---

## Misc utilities

- Path.digest_str — extension in path/digest.rb:
  - If path is a file and exists → "File MD5: <md5>".
  - If path is a directory → "Directory MD5: <digest of glob>".
  - Otherwise returns quoted path string.

- Path.no_method_missing — remove the module-level method_missing implementation (rarely used).

- TmpFile.with_path — helper that yields a path string and ensures it is a Path (via Path.setup).

- Path.newer?(path, file, by_link = false) — compare mtimes; returns truthy if `path` is newer than `file`. Handles non-existing files and optionally compares lstat (links).

---

## Integration & annotations

Path extends the Annotation module; each Path can carry annotations:
- `pkgdir`, `libdir`, `path_maps`, `map_order`. These let different packages or code contexts override search behavior for a path instance.

`Path.setup` creates a Path with default annotations:
- `pkgdir` defaults to Path.default_pkgdir (usually 'scout').
- `libdir` defaults to caller library directory (Path.caller_lib_dir).

Examples from tests and common use:

- Compose paths:
  ```ruby
  p = Path.setup('/tmp')
  p.join(:foo)          # => "/tmp/foo"
  p[:bar, :foo]         # => "/tmp/bar/foo"
  p.foo[:bar]           # => "/tmp/foo/bar"
  ```

- Find a file across path maps:
  ```ruby
  p = Path.setup("share/data/some_file", 'scout')
  p.find(:usr)               # resolves using :usr map -> "/usr/share/scout/data/some_file"
  p.find                     # searches map_order and returns first existing match
  p.find.where               # map name where it was found (e.g. :current)
  p.find.original            # original logical path prior to substitution
  ```

- Search all matches:
  ```ruby
  Path.setup("share/data/some_file", 'scout').find_all
  ```

- Add custom search paths:
  ```ruby
  file = Path.setup("somefile")
  file.append_path('dir1', '/tmp/dir1')
  file.prepend_path('dir2', '/opt/dir2')
  ```

- Work with extensions:
  ```ruby
  p = Path.setup("/home/.scout/dir/file.txt")
  p.unset_extension   # => "/home/.scout/dir/file"
  p.replace_extension('tsv')
  ```

- Glob directories:
  ```ruby
  dir = Path.setup(tmpdir)
  dir.glob          # returns annotated Path children
  ```

---

## Notes & edge cases

- Path uses `Path.located?` to decide if a path is already absolute / explicitly located (leading `/`, `~/` or `./`).
- If `find` is called on a non-located path, it searches maps in `map_order`. Map templates are string patterns — if a map is missing `Path.find` will fallback to the default map.
- `find` will also check for compressed alternatives (filename.gz, .bgz, .zip) via helper `exists_file_or_alternatives`.
- The system allows per-path overrides of `pkgdir` and `path_maps` — useful for testing and package-specific layouts.
- `Path.follow` performs token substitution and supports nested `{PATH/.../...}` style replacements.
- `caller_lib_dir` and `caller_file` try to infer the caller's library directory; used to set sensible defaults for `libdir`.
- Many helpers in the framework accept Path objects and will call `.find` (or `.produce_and_find` when supported). Use Path.setup to annotate and pass Path objects to other APIs.

---

## API quick reference

- Creation / basics:
  - Path.setup(string, pkgdir=nil)
  - path.join(subpath, prevpath=nil)  — aliases: path[:x], path / :x
  - path.method_missing to allow `path.foo` as join

- Mapping & locating:
  - Path.path_maps, Path.map_order, Path.add_path / prepend_path / append_path
  - path.follow(map_name=:default) — expand template without checking existence
  - path.find(where = nil) — locate first existing match (annotates `.where` and `.original`)
  - path.find_all — return all existing matches across maps
  - path.find_with_extension(extension, *args)

- Filesystem / filename helpers:
  - path.glob(pattern="*"), path.glob_all(pattern=nil)
  - path.dirname, path.basename
  - path.get_extension, set_extension, unset_extension, remove_extension, replace_extension
  - Path.sanitize_filename, Path.is_filename?

- Utilities:
  - Path.located?(s), path.located?
  - Path.caller_file, Path.caller_lib_dir
  - Path.digest_str (file/directory MD5 summary)
  - Path.newer?(path, file, by_link = false)

This document summarizes the Path module's purpose and primary surface area. Use Path.setup to get annotated strings that interoperate with Open and other framework utilities to find and manipulate package-oriented filesystem resources.