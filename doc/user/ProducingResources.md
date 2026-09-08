# Producing Resources

A **resource** is a logical file — a name like `data/config.yaml` — that a
software package can materialize on demand. This page explains the `claim`
syntax, how `produce` uses claims to write files, and the helpers around
them.

## Declaring a resource

Any module that `extend`s `Resource` becomes a resource package:

```ruby
require 'scout-essentials'

module MyApp
  extend Resource
  annotation :pkgdir
  self.pkgdir = 'myapp'
end

MyApp.claim MyApp.data.config, :string, "key=value\n"
```

Inside such a module the idiomatic form (note: no `self.` prefix on `claim`)
is:

```ruby
module MyApp
  extend Resource
  annotation :pkgdir
  self.pkgdir = 'myapp'

  claim data.file, :string, "content\n"
end
```

- `claim(path, type, content = nil, &block)` — `type` is a **mandatory
  positional** argument (`claim path { }` raises `ArgumentError`). Passing
  only the path plus a block is not a valid call.
- `type` is one of `:string`, `:url`, `:proc`, `:rake`, `:install`.
  `:csv` is an unimplemented stub that raises `RuntimeError
  "TSV/CSV Not implemented yet"` when produced. There is **no `:annotation`
  claim type**.
- `path` is normally a `Path` built with `method_missing` segments
  (`MyApp.data.config`); a plain `String` is also accepted.

## Claim types

| Type | `content` | Effect |
|------|-----------|--------|
| `:string` | String | written verbatim |
| `:url` | source path/URL | the source is opened (with `:noz` when it looks compressed) and copied to the final path |
| `:proc` | `Proc` (arity 0 or 1) | called with no args (arity 0) or the final path (arity 1); the result is dispatched (below) |
| `:rake` | Rakefile directory/task | `run_rake` builds the file (below) |
| `:install` | software spec hash | `Resource.install` installs software into `share/software` (below) |

`:proc` result dispatch — the returned value drives how the file is written:

- `String`, `IO`, `StringIO` → `Open.sensible_write(final_path, data)`
- `Array` → elements joined with `"\n"` then written
- `TSV` / `TSV::Dumper` → the dumper stream is written (requires
  `rbbt-util`/scout-gear; **a `nil` return trips the `when TSV` branch
  first** and raises `NameError: uninitialized constant Resource::TSV`, so
  procs that may return nil must guard themselves)
- `nil` → nothing is written (file left missing) — but see the caveat above
- anything else → `RuntimeError "Unkown object produced: ..."`

## Producing

`Path#produce` (in `lib/scout/resource/path.rb`) is the entry point:

```ruby
MyApp.data.config.produce   # returns the logical path (a Path)
MyApp.data.config.find      # => "$HOME/.myapp/data/config"  (now existing)
Open.read(MyApp.data.config.find) # => "key=value\n"
```

- It never returns nil: on `ResourceNotFound` (nothing claims the path) it
  stores `false` and returns it, and that decision is **latched** in
  `@produced` — a later call does not retry unless you pass `force`.
- A raised `Exception` stored in `@produced` is re-raised on the next call.
- On a successful produce the target is written under a **produce lock**
  (`TmpFile.tmp_for_file(final_path, dir: lock_dir)` + `Open.lock`).
- If nothing claims the plain path but a `.gz` or `.bgz` variant is claimed,
  production falls through to those extensions. The fall-through is
  asymmetric: producing `x.txt` may materialize `x.txt.gz`, but asking for
  `x.gz` when only `x.txt` is claimed fails.
- `force: true` (or `produce(true)`) removes the existing file and reruns.

```ruby
MyApp.data.config.produce(true) # force re-production
```

### Extension-aware helpers

- `produce_and_find(extension = nil, *args)` — produce (falling back to the
  given extension with `produce_with_extension`) and return the located
  path; raises `RuntimeError "Not found"` if the result is still missing.
- `produce_with_extension(extension, *args)` — try the plain path first, then
  the variant with `extension` appended; raise the *first* exception if both
  fail.
- `find_with_extension(ext, *args, produce: true)` — `find` first; if the
  plain result does not exist, look for `self.set_extension(ext)`.
  `produce:` defaults to **true**, so it may trigger a produce.
- `exists?(produce: true)` — default **produces** before answering; pass
  `false` for a pure existence check.

### Produce-aware `Path` I/O

`Path#read` and `Path#open` call `produce` first; `Path#list` is
`produce_and_find('list')` then `Open.list`. `Path#write` does **not**
produce — it writes straight to `self.find` (use it to place a manual file
under the resource tree):

```ruby
MyApp.data.manual.write("manual\n")
# => writes to the found location, no claim consulted
```

## Rake claims

A rake claim points at a directory containing a `Rakefile`:

- `rake_dirs` lists candidate directories; `has_rake?(path)` is true when a
  rake prefix matches, and `rake_for(path)` returns the longest matching
  prefix (an empty-string prefix matches everything).
- Production runs the task through `ScoutRake` (forked execution). If rake
  reports `Don't know how to build task`, the walk-up retry joins the task
  name with the parent directory and retries; if that also fails, the error
  is converted to `ResourceNotFound`.
- A `Path` whose pkgdir is the resource module is produced with
  `pkgdir.produce(self)`; `Path#produce` on a String path returns `false`.

```ruby
# Rakefile in ./ with: file "data/built.txt" do |t| Open.write(t.name, "x") end
MyApp.data.built.txt.produce
Open.read(MyApp.data.built.txt.find) # => "x"
```

## Software installs

`:install` claims (and `Resource.install(name, software_dir, options)`)
install software binaries under `share/software/<name>` by sourcing
`share/software/install_helpers` and running the recipe from the spec hash
(`:git`, `:src`, `:url`, `:jar`, `:extra`, `:configure`, `:make`, ...).
`Resource.set_software_env(software_dir)` runs at load time on the default
`software` dir to expose installed binaries on `PATH`/`JAVA_CLASSPATH`-style
variables.

## `Resource.sync`

```ruby
Resource.sync(path, map = nil, options = {})
```

A module-level method (there is **no** `Path#sync`) that walks the map
order copying/symlinking resource files found in other locations into the
map's directory, so that unlocated paths resolve locally. It is unrelated to
`Open.rsync`.

## Scout itself is a Resource

`Scout` extends `Resource` with `pkgdir 'scout'` and is
`Resource.default_resource`. `Scout.etc`, `Scout.tmp`, ... are ordinary
`Path` segment builders over the `Scout` package:

```ruby
Resource.default_resource # => Scout
Scout.etc.find            # => "$HOME/.scout/etc"
```

## Related

- [Path Resolution](../developer/PathResolution.md) for `find`/`follow`.
- [Persistence and Resources](../developer/PersistenceAndResources.md) for the
  produce lock namespace and claim semantics from a developer angle.
