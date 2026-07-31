# Path Resolution

This document explains how the Path resolution system works internally. It
is intended for framework contributors who need to understand or extend the
path search mechanism.

## Why this abstraction exists

Scout-based applications reference data files by logical names (e.g.,
`data/config.yaml`), not absolute paths. The physical location of these
files varies by installation: user-local, global, cached, or in a package
directory. Path resolution translates logical names to physical paths by
searching a configurable set of locations called "path maps."

This separation lets the same code work across different installations
without hardcoding paths.

## How it works

### Path as an annotated string

A Path is a String extended with path resolution behavior:

```ruby
path = Path.setup("data/config.yaml")
path.class       # => String
path.is_a?(Path) # => true (checked via annotation)
```

The annotation carries metadata: `pkgdir`, `libdir`, `path_maps`,
`map_order`, and the resolved location.

### Path maps

A path map is a template string with placeholders. When resolving a logical
path, Path substitutes the placeholders to produce candidate physical paths:

```ruby
Path.path_maps[:user]  # => "{HOME}/.scout/{TOPLEVEL}/{SUBPATH}"
```

Placeholders:
- `{PATH}` — the logical path (e.g., `data/config.yaml`)
- `{PKGDIR}` — package directory name
- {SUBPATH} — sub-path within the package
- `{HOME}` — user home directory
- `{PWD}` — current working directory
- `{TOPLEVEL}` — top-level directory name (first component of the path)

### Map order

`map_order` determines the sequence in which maps are searched:

```ruby
Path.map_order
# => [:current, :user, :global, :cache, :tmp, :lib, ...]
```

The first map that produces an existing file wins. If no map resolves to
an existing file, `find` returns nil.

### The `find` method

```ruby
def find
  map_order.each do |map_name|
    template = path_maps[map_name]
    candidate = expand_template(template)
    return candidate if File.exist?(candidate)
  end
  nil
end
```

The actual implementation also handles:
- Alternative extensions: if `data/config.yaml` doesn't exist, it checks
  `data/config.yaml.gz`, `data/config.yaml.bgz`, etc.
- `{PATH/old/new}` style inline substitutions.
- Resource-backed paths: if the path has a Resource claim, `find` may
  trigger production.

### The `produce` method

For Resource-backed paths, `produce` ensures the file exists by triggering
the production logic (download, generate, install):

```ruby
path.produce  # creates the file if missing, returns the path
```

## Configuration

### Adding path maps

```ruby
# Add a new search location
Path.add_path(:my_location, "/custom/data/{PATH}")

# Prepend (higher priority)
Path.prepend_path(:user, "/shared/{PATH}")

# Append (lower priority)
Path.append_path(:global, "/opt/data/{PATH}")
```

### Changing map order

```PATH
```ruby
# Prioritize cache over user
Path.map_order = [:current, :cache, :user, :global]
```

### Following paths

`Path.follow` resolves `{PATH/old/new}` substitutions in a template:

```ruby
template = "/shared/{PATH/data/converted}"
Path.follow("data/file", template)
# => "/shared/converted/file"
```

## Key invariants

1. **Path objects are Strings.** They have all String methods plus
   resolution methods.
2. **`find` does not produce.** It only checks existence. Use `produce` to
   create missing files.
3. **Map order matters.** The first match wins, so order maps by priority.
4. **Extension alternatives are checked.** If `file.txt` doesn't exist,
   `.gz`, `.bgz`, and `.zip` variants are checked automatically.

## Extension points

### Custom path maps

Add maps for application-specific directories:

```ruby
Path.add_path(:my_app_data, "/opt/myapp/{SUBPATH}")
Path.map_order = Path.map_order.dup.unshift(:my_app_data)
```

### Custom map templates with substitution

Maps can use `{PATH/old/new}` for path component replacement:

```ruby
Path.add_path(:converted, "/cache/{PATH/data/converted}")
```

When resolving `data/file`, this produces `/cache/converted/file`.

### Resource integration

Paths tied to a Resource module can produce themselves. See
[Persistence and Resources](PersistenceAndResources.md).

## Interactions with other subsystems

- **Open** — `Open.read`, `Open.open`, etc. resolve Path objects via
  `path.find` before accessing the file.
- **Resource** — Resource-backed paths trigger production on `produce` or
  when accessed with `exists?(produce: true)`.
- **Persist** — Persist uses Path for cache_dir and lock_dir configuration.
- **TmpFile** — TmpFile.tmp_for_file uses Path patterns for temp directory
  structure.

## Common pitfalls

### find returns nil, not false

```ruby
path = Path.setup("nonexistent")
path.find     # => nil
path.exists?  # => false

# Don't use find in boolean context without nil check
if path.find  # truthy check works because nil is falsy
  ...
end
```

### Map order is not set once

`map_order` can be modified at runtime. Code that runs before you change it
uses the old order. Set map order early, ideally during initialization.

### Extension alternatives can surprise

If you have both `data.txt` and `data.txt.gz`, `find` returns whichever
appears first in map order, not necessarily the uncompressed version.

## Related

- [Architecture](Architecture.md) — How Path fits in the module dependency
  graph.
- [Persistence and Resources](PersistenceAndResources.md) — How Resource
  extends Path with production.
- For detailed code investigation, see
  [`../../research/io-paths-analysis.md`](../../research/io-paths-analysis.md).
