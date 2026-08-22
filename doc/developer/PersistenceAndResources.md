# Persistence and Resources

This page documents the developer contracts behind two mechanisms that both
write files: **`Persist`** (caching the result of a computation) and
**`Resource#produce`** (materializing a declared resource). Both are
lock-protected and rely on `Open.sensible_write` for atomic output.

## `Persist.persist`

```ruby
Persist.persist(name, type, options = {}, &block)
```

`Persist.persist` runs `block` and stores its serialized result under a
cache path, unless the cache is already valid, in which case the stored
value is deserialized and returned without running the block.

- `name` — usually a cache path; `options[:persist_path]` (or `:path`)
  overrides it.
- `type` — a serialization type; see the table in
  [Caching Results](../user/CachingResults.md).
- With no block the call is a lookup.
- `path_hash`/`:path` options name the cache file; `key:` appends
  `[key]` to it.
- `:check` — a file, an Array of files or a Proc; when any of them is newer
  than the cache (`Path#outdated?`) the cache is recomputed. `:check`
  requires the cache path itself to be a `Path` (a plain `String` cache
  path raises `NoMethodError`).
- `:update` — `true` (always recompute), a `Time` or a `Numeric` number of
  seconds (recompute when the cache file is older), or a `Path` whose mtime
  is compared with the cache's.
- `:memory` type + `MEMORY_CACHE` — in-process memoization with the same
  API; `Persist.memory("key", key: k) { ... }` is the shorthand.
- `KeepLocked` — when passed, the persist lock is held across the whole
  read/serialize cycle, preventing readers from seeing a half-written cache
  file.
- `:canfail` — on failure (of the computation, not of the lookup) the error
  is swallowed and `nil` is returned instead of raising.
- **Error path**: unless `DontPersist` is raised, a failing block leaves no
  partial cache file behind — the target is removed.
- `no_load: true` (or a `TrueClass` value) returns the cache **path**
  instead of the content.

The serialization drivers are not constants: they are entries in the
accessor hashes `Persist.save_drivers` and `Persist.load_drivers`, both
keyed by type symbol. You can add a type by inserting a Proc into both
hashes. **No serialization suffix is ever appended to the filename**: two
calls with different types and the same `name`/`persist_path` collide on
the same file.

## Lock namespaces

Three lock directories exist, and they are **not** interchangeable:

| Lock dir | Owner | Naming of the lock file |
|----------|-------|------------------------|
| `Persist.lock_dir` (`tmp/persist_locks`) | `Persist.persist` | derived from the cache path |
| `Resource.default_lock_dir` (`tmp/produce_locks`) | `Resource#produce` | `TmpFile.tmp_for_file(final_path, dir: lock_dir)` |
| `Open.sensible_write_lock_dir` (`tmp/sensible_write_locks`) | `Open.sensible_write` | derived from the target path |

The locking primitive is `Open.lock(filename, &block)` on the vendored
`Lockfile`. **`Persist.lock` does not exist.**

## `Resource` and `Path`: one mechanism

`Path` is a String subclass extended with `Annotation`; `Resource` is a
module extended with `Annotation` and `extend`ed by resource packages.
Because both are annotation-based, a `Path` produced from a resource module
carries the module itself as its `pkgdir` annotation, and `Path#produce`
delegates to `pkgdir.produce(self, force)`:

```ruby
module MyApp
  extend Resource
  annotation :pkgdir
  self.pkgdir = 'myapp'
end
```

- `claim(path, type, content = nil, &block)` — `type` is mandatory and
  positional; valid types are `:string`, `:url`, `:proc`, `:rake`,
  `:install`. `:csv` raises `"TSV/CSV Not implemented yet"` when produced.
- A `:proc` claim of arity 0 is called with no arguments; arity 1 receives
  the final path. The return value is dispatched: `String`/`IO`/`StringIO`
  → written; `Array` → joined with newlines; `TSV`/`TSV::Dumper` → dumper
  stream (scout-gear only; **a `nil` return hits the `when TSV` branch
  first** and raises `NameError` without scout-gear); `nil` → nothing
  written.
- Producing an unclaimed path falls through to `.gz`/`.bgz` variants when
  those are claimed — asymmetrically (plain → `.gz` works, `.gz` → plain
  does not).
- `@produced` on the `Path` latches tri-state: `true` after a successful
  produce, `false` after `ResourceNotFound`, the exception after a failure;
  later calls return/raise that value instead of retrying, unless `force`.
- `Path#read`/`#open`/`#list` produce first (`#list` uses
  `produce_and_find('list')`); `Path#write` does not.
- `Resource.sync(path, map, options)` — module-level helper (no `Path#sync`)
  that re-materializes resource files found elsewhere into a local map
  directory.

## Rake and software

- `rake_dirs` directories make a package "have rake": `has_rake?(path)` /
  `rake_for(path)` (longest prefix match). Production runs the rake task
  through `ScoutRake`, which forks; a `Don't know how to build task`
  message triggers a walk-up retry, then `ResourceNotFound`.
- `:install` claims run `Resource.install(name, software_dir, options)`,
  sourcing `share/software/install_helpers` and honoring spec keys such as
  `:git`, `:src`, `:url`, `:jar`, `:extra`. `Resource.set_software_env`
  exports the installed binaries (run once at load time on the default
  `software` dir).

## Related

- [Caching Results](../user/CachingResults.md) — user-facing guide to
  `Persist`.
- [Producing Resources](../user/ProducingResources.md) — user-facing guide
  to claims and `produce`.
- [Architecture](Architecture.md) — module graph and lock overview.
