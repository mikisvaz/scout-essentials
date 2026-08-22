# Path Resolution

`Path` is a `String` subclass carrying resource metadata. This page explains
how an *unlocated* logical name such as `data/config.yaml` is turned into a
real filesystem location, how to configure the search, and how `find`,
`follow`, `identify`, and friends behave.

## Anatomy of a `Path`

A `Path` is a plain `String` plus annotations (`:pkgdir`, `:libdir`,
`:path_maps`, `:map_order`, `:where`, `:original`), added by the `Annotation`
mechanism. Because it is a String, it can be joined, split, and used with
core `File` methods; annotations travel along when you `join` or use `/`:

```ruby
require 'scout-essentials'

p = Path.setup('data/config.yaml')
p.pkgdir    # => "scout" (Path.default_pkgdir)
p.located?  # => false ('data/config.yaml' is relative, not './x' or '/x')
p.to_s      # => "data/config.yaml"

p.join(:a)          # => "data/config.yaml/a"
p.join(:a, :b)      # => "data/config.yaml/b/a"  (b goes first)
p / :a              # => "data/config.yaml/a"
p._toplevel         # => "data"   (first path segment)
p._subpath          # => "config.yaml" (the rest)
p.data.samples      # => "data/config.yaml/data/samples"  (method_missing
                    #    appends a segment, right to left)
```

`[]` and `/` are both aliases of `join`. **There is no `Path#[]=` and no
class-level `Path.map_order=`** — use `Path.add_path`,
`Path.prepend_path`, `Path.append_path`, or the per-instance
`path_maps`/`map_order` annotations instead.

## Location: `find`

`find` resolves an unlocated path by trying every map in `map_order` until
one produces an existing file (or a `.gz`/`.bgz`/`.zip` alternative).
`find` **never returns nil**:

- If the path is already `located?` (starts with `/`, `./`, or `~/`) and
  exists, it returns the expanded path.
- If it is `located?` but missing, it tries the compressed alternatives and
  otherwise **returns itself**.
- If it is unlocated, it walks `map_order`; on total failure it returns
  `follow(:default)` — the default location where the file *would* be.

```ruby
p = Path.setup('data/config.yaml')
p.find             # tries :current, :user, :home, ... then :default
p.find(:user)      # force one specific map
p.find(:all)       # == find_all
p.exists?          # find then File.exist?
```

The returned `Path` is annotated with `where` (the map that matched) and
`original` (a copy of the unlocated path) so you can trace how a file was
resolved:

```ruby
found = p.find
found.where     # e.g. :user
found.original  # the original unlocated Path
```

## The default map order

The built-in maps and their order (13 entries) are:

| # | Map | Template |
|---|---|---|
| 1 | `:current` | `{PWD}/{TOPLEVEL}/{SUBPATH}` |
| 2 | `:user` | `{HOME}/.{PKGDIR}/{TOPLEVEL}/{SUBPATH}` |
| 3 | `:home` | `{HOME}/{TOPLEVEL}/{PKGDIR}/{SUBPATH}` |
| 4 | `:local` | `/usr/local/{TOPLEVEL}/{PKGDIR}/{SUBPATH}` |
| 5 | `:global` | `/{TOPLEVEL}/{PKGDIR}/{SUBPATH}` |
| 6 | `:usr` | `/usr/{TOPLEVEL}/{PKGDIR}/{SUBPATH}` |
| 7 | `:scout_essentials_lib` | `<gem libdir>/{TOPLEVEL}/{SUBPATH}` |
| 8 | `:lib` | `{LIBDIR}/{TOPLEVEL}/{SUBPATH}` |
| 9 | `:fast` | `/fast/{TOPLEVEL}/{PKGDIR}/{SUBPATH}` |
| 10 | `:cache` | `/cache/{TOPLEVEL}/{PKGDIR}/{SUBPATH}` |
| 11 | `:bulk` | `/bulk/{TOPLEVEL}/{PKGDIR}/{SUBPATH}` |
| 12 | `:default` | `{PWD}/{TOPLEVEL}/{SUBPATH}` |
| 13 | `:tmp` | `/tmp/{PKGDIR}/{TOPLEVEL}/{SUBPATH}` |

A per-instance `map_order` is recomputed lazily as
`(Path.map_order & available_maps) + (remaining maps, in reverse key order)`.
This is why a new map registered with `Path.add_path` (which clears the
class-level order) or `p.add_path` (which clears the instance order) ends up
at the *end* of the effective order, after the built-ins:

```ruby
p = Path.setup('data/config.yaml')
p.add_path(:onlymine, '/x/{SUBPATH}')
p.map_order # => [:current, :user, ..., :tmp, :onlymine]
```

`*_lib` maps (e.g. `:scout_essentials_lib`) are regular entries built from
the gem's own libdir at load time; `{LIBDIR}` in a template resolves to the
`libdir` annotation or, failing that, the directory of the calling library.

## `follow`: applying a map without searching

`follow(map)` applies one template, no matter whether the target exists:

```ruby
Path.setup('data/config.yaml').follow(:user)
# => "$HOME/.scout/data/config.yaml"
```

Placeholders available in templates: `{PWD}`, `{HOME}`, `{PKGDIR}`,
`{RESOURCE}`, `{TOPLEVEL}`, `{SUBPATH}`, `{BASENAME}`, `{PATH}`, `{LIBDIR}`,
`{MAPNAME}`, `{REMOVE}` (deletes itself and the following slash). A template
without any placeholder gets `{PATH}` appended, so the *whole path* is used
verbatim. A map value may be another map name (a `Symbol`), which is
dereferenced until a String is found. When `map_name` is an unknown String,
`follow` builds `<map_name>/{TOPLEVEL}/{SUBPATH}` on the fly — this is how
`Scout.etc` (`"etc"`) resolves to `$HOME/.scout/etc`:

```ruby
Scout.etc['path_maps'].find  # => "$HOME/.scout/etc/path_maps"
```

## Configuring the search

```ruby
Path.add_path(:mymap, '/my/{TOPLEVEL}/{SUBPATH}')   # effective in map_order
Path.prepend_path(:first, '/first/{TOPLEVEL}/{SUBPATH}')
Path.append_path(:last, '/last/{TOPLEVEL}/{SUBPATH}')

p = Path.setup('data/config.yaml')
p.add_path(:onlymine, '/x/{SUBPATH}')  # per-instance; recomputes map_order
p.path_maps                            # a dup of Path.path_maps
p.map_order                            # instance order, :onlymine included
```

`Path.load_path_maps(filename)` reads a YAML mapping of `where => location`
and registers each with `add_path`; at boot,
`Scout.etc['path_maps']` (i.e. `$HOME/.scout/etc/path_maps`) is loaded this
way, so users can add search locations without code changes.

## Finding every candidate: `find_all` / `glob_all`

```ruby
Path.setup('data/config.yaml').find_all
# => every location in map_order where the file exists (uniqued)

Path.setup('data/*').glob_all
# => Path#glob over each map result; annotated with original/where
```

`glob` on a `located?` path calls `Dir.glob` directly; on an unlocated path
it delegates to `glob_all`.

## Reversing the process: `identify` and `relocate`

`Resource.identify(path)` maps a located path back to an unlocated one by
matching each map template as a regexp (dropping `:current`); the shortest
candidate wins, and `$HOME` is folded back to `~`. `Resource.relocate(path)`
returns the existing path if it exists, otherwise identifies and re-finds it.

```ruby
Resource.identify(File.join(ENV['HOME'], '.scout', 'data', 'config'))
# => "data/config"
Resource.relocate(File.join(ENV['HOME'], '.scout', 'data', 'config'))
# => re-resolved through find
```

## Digest names and `etc`/`tmp` helpers

`Path#digest_str` produces a stable digest for a file or directory (used for
caching); for a directory with more than 10 files it uses a count plus an
MD5 of the file list, otherwise the MD5 of each file. See
[Caching Results](../user/CachingResults.md).

Resource helpers: `Scout.etc`, `Scout.tmp`, `Scout.share`, ... are
`Path#method_missing` segment builders over `Scout`'s own path (`Scout` is
itself a Resource with `pkgdir 'scout'`), so they produce unlocated
sub-paths that `find`/`follow(:user)` resolve under `$HOME/.scout`:

```ruby
Scout.etc                # => "etc"           (unlocated, pkgdir Scout)
Scout.etc.find           # => "$HOME/.scout/etc"
Scout.etc['path_maps'].find # => "$HOME/.scout/etc/path_maps"
```

`Scout.etc` is not a statically defined method: it resolves through
`Resource#method_missing` (resource.rb:69) into `Path#method_missing`
(path.rb:45) segment building, the same mechanism as any other segment
(`Scout.tmp`, `Scout.share`, ...).

## Related

- [Producing Resources](../user/ProducingResources.md) — claims and produce
  on top of `find`.
- [Working with Files](../user/WorkingWithFiles.md) — `Open` I/O that
  consumes `Path`s.
- [Architecture](Architecture.md) for the module dependency graph.
