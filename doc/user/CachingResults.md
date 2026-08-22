# Caching Results

This guide explains how to cache computation results in scout-essentials
using the `Persist` module: the `persist` pattern, serialization types,
staleness invalidation, in-memory caching, and locking.

## The persist pattern

`Persist.persist` runs a block once and reuses the cached result on later
calls:

```ruby
require 'scout-essentials'

value = Persist.persist('result', :string) do
  "expensive computation"
end

value # => "expensive computation"  (first call: block runs)
value # => "expensive computation"  (second call: loaded from disk)
```

The signature is `Persist.persist(name, type = :serializer, options = {}, &block)`:

- `name` — a string used to build the cache file name (a path is also
  accepted; its `filename` is used). Unless you give `:path`/`:persist_path`,
  the cache lands under `Persist.cache_dir`, which returns the relative
  `Path`/String `var/cache/persistence`.
- `type` — a serialization type (table below); `:serializer` is the default
  and resolves to `:json` (`Persist::SERIALIZER == :json`).
- `options` — a plain `Hash` of options. `persist_path` takes an options
  hash, and a **second positional argument is NOT supported**: the option key
  is `:persist_path` (or `:path`), never a positional argument.

```ruby
Persist.persistence_path('result')                 # => "var/cache/persistence/result"
Persist.persistence_path('result', key: 'X')       # => "var/cache/persistence/result[X]"
Persist.persistence_path('result', :marshal)       # TypeError — no positional type
Persist.persistence_path('result', dir: tmp_dir)   # honoured via :dir
```

**Options:**

| Option | Meaning |
|---|---|
| `:persist_path` / `:path` | Exact file to use as cache (String or Path) |
| `:persist` | `false` bypasses persistence entirely and just returns `yield` |
| `:no_load` | `true` returns the cache file itself instead of its contents |
| `:update` | Force recomputation. A `true` recomputes; a `Time`/number recomputes when the cache is older; a `Path` uses that file's `mtime` |
| `:check` | Array of dependency paths; the cache is invalidated when any is newer |
| `:canfail` | Swallow errors, returning `nil` (or the file with `:no_load`) instead of raising |
| `:data` | Passed as the block argument when the block has arity 1 |
| `:tee_copies` | Number of extra stream copies when the block returns a stream |
| `:lockfile` | Use a specific lock file instead of the default |

If the block has arity 1, it receives the cache file (a `Path`/String), and
its return value is loaded from disk only if it is `nil`:

```ruby
Persist.persist('result', :text, persist_path: path) do |file|
  Open.write(file, "written by block\n")
end # => loads the file
```

## Serialization types

`Persist.serialize` / `Persist.deserialize` / `Persist.save` / `Persist.load`
understand these types (`type` is `nil, :string, :text, :integer, :float,
:boolean, :file, :path, :select, :folder, :binary, :array, :yaml, :json,
:marshal, :annotation, :serializer`, plus `:stream` on load):

| Type | Saved as | Loaded as |
|---|---|---|
| `nil`, `:text` | `to_s` | String, exactly as written (no stripping) |
| `:string` | `to_s` | String, stripped |
| `:integer`, `:float` | `to_s` | `Integer` / `Float` |
| `:boolean` | `to_s` | `true` only if in `TRUE_STRINGS` (`"true"`, `"yes"`, `"y"`, `"t"`, `"on"` and their case variants, `"1"`) |
| `:file`, `:folder`, `:select` | `to_s` | Stripped String (a `:file` entry starting with `"./"` is resolved relative to the cache file's directory) |
| `:path` | `to_s` | `Path.setup(...)` |
| `:binary` | bytes (encoding forced to ASCII-8BIT) | bytes read with `mode: 'rb'` |
| `:array` | elements joined with `"\n"` | Array of lines |
| `:yaml` | `to_yaml` | Loaded with `Open.yaml` (`YAML.unsafe_load` — `Open.yaml` is defined in the persist layer, `lib/scout/persist/open.rb:11`), so hashes/arrays round-trip. Note `:yaml_array` goes through the per-line `deserialize` path (`YAML.parse`) and yields `Psych::Nodes::Document` objects — use `:json_array` for array round-trips |
| `:json` | `to_json` | `JSON.parse` |
| `:marshal` | `Marshal.dump` | `Marshal.load` |
| `:annotation` | `Annotation.tsv(content, :all).to_s` | `Annotation.load_tsv(TSV.open(...))` (part of the scout-gear ecosystem, not usable standalone) |
| `:serializer` | alias for `:json` | alias for `:json` |
| `:stream` (load only) | — | `Open.open(file)` |
| `:file_array` (load only) | — | Array of files, `"./"`-relative entries resolved |

Any type can take an `_array` suffix (`:yaml_array`, `:path_array`, …) when
saving or loading: elements are serialized individually and joined/split on
newlines. **No type suffix is ever appended to cache file names** — two
different types sharing a `name` collide on the same cache file. An unknown
type raises `RuntimeError: Persist does not know <type>`.

## Cache location and lock location

```ruby
Persist.cache_dir    # => var/cache/persistence   (a relative String path)
Persist.cache_dir = '/some/other/dir'
Persist.lock_dir     # => $HOME/.scout/tmp/persist_locks  (an absolute String)
Persist.lock_dir = '/some/other/locks'
```

Locks live under `Persist.lock_dir` and are named after the cache file plus
`.persist`: `<cache-file>.persist`. They are `Open.lock` lockfiles (see
[Working with Files](WorkingWithFiles.md)); there is **no** `Persist.lock` —
`Persist.persist` uses `Open.lock` internally.

## Staleness: `:update` and `:check`

`:check` lists dependencies; when any of them is newer than the cache, the
cache is recomputed. `:update` forces recomputation, optionally guarded by a
`Time` (numeric age in seconds) or a `Path` (an mtime to compare against):

```ruby
cache = Path.setup('var/cache/persistence/example')

Persist.persist('example', :string, persist_path: cache, check: [input]) do
  "computed"
end
# input updated -> "computed" re-runs

Persist.persist('example', :string, persist_path: cache, update: 60) { "x" }
# re-runs only if the cache is older than 60 seconds

Persist.persist('example', :string, persist_path: cache, update: dep_path) { "x" }
# re-runs only if dep_path's mtime is newer than the cache's
```

`:check` and `:update` (and the `update` computation itself) depend on
`Open.mtime` and on `file.outdated?(check)`, which are `Path` methods; give
`persist` a `Path` (`persist_path:` a `Path.setup(...)`), not a plain
`String`, when you rely on them.

## Memory caching

Type `:memory` stores the block result in a process-global hash
(`Persist::MEMORY_CACHE`) instead of a file; a custom repo hash can be passed
with `:memory:` / `:repo:`:

```ruby
Persist.persist('m', :memory) { [1, 2] } # => [1, 2]

Persist.memory('m2', key: 'K') { "in-memory-value" }
# => "in-memory-value"; the key is composed into the entry name
```

`Persist.memory(name, options, &block)` is the helper for the common
`[name, key]` case.

## Streams and `KeepLocked`

When the block returns an `IO`/`StringIO`, `persist` does not block: it
tee's the stream so the caller consumes one copy while a background thread
writes another to the cache file. The returned stream keeps the persist lock
until it is joined (`KeepLocked`); join the stream (or let `autojoin` run)
before relying on the cache file.

```ruby
stream = Open.open_pipe { |sin| 10.times { |i| sin.puts "row#{i}" } }
res = Persist.persist('rows', :string, persist_path: path) { stream }
res # => a ConcurrentStream (IO); the cache file is complete once res.join
```

## Error handling

If the block raises, `persist` removes the partial cache file (unless the
exception is a `DontPersist`) and re-raises — **unless** `:canfail` is set,
in which case it returns `nil` (or the file with `:no_load`):

```ruby
Persist.persist('failing', :string, canfail: true) { raise "boom" } # => nil
```

## Related

- [Working with Files](WorkingWithFiles.md) — `Open.lock`, `sensible_write`,
  and I/O that `Persist` builds on.
- [Producing Resources](ProducingResources.md) — Resource composes with
  Persist.
- For internal implementation details, see
  [Persistence and Resources](../developer/PersistenceAndResources.md).
