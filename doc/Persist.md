# Persist

Persist provides a unified persistence layer for serializing, saving and loading Ruby objects to/from files, with helpers for common formats (JSON, YAML, Marshal), typed serialization, memory-backed persistence, atomic writes, caching, and safe concurrent access (locking). It integrates with Open, Path and the Lockfile-based locking in Open.lock.

Key capabilities:
- Typed serialization/deserialization for many common types (string, integer, float, boolean, array, json, yaml, marshal, path, file, binary, and *_array variants).
- Save/load drivers can be customized (Persist.save_drivers / Persist.load_drivers).
- Safe, atomic writes using Open.sensible_write.
- `Persist.persist` — higher-level pattern: compute value if not present or stale, save it, and return result; supports streaming writes and keeping locks while streaming.
- In-process memory persistence (`:memory`).
- Helpers to load JSON/YAML/Marshal with Open (Open.json/Open.yaml/Open.marshal).
- Configurable cache_dir and lock_dir for persisted artifacts and lockfiles.

---

## Configuration & defaults

- Persist.cache_dir — default cache directory (Path) used when creating persistence paths. Defaults to Path.setup("var/cache/persistence").
- Persist.lock_dir — directory used to create lockfiles for persist operations (default tmp/persist_locks).
- Persist.SERIALIZER — default serializer symbol used when type is `:serializer` (default :json).
- Persist.TRUE_STRINGS — strings that are treated as true when deserializing booleans.

You can set:
```ruby
Persist.cache_dir = Path.setup("var/cache/persistence")   # or string
Persist.lock_dir = Path.setup("tmp/persist_locks").find
```

---

## Serialization helpers

- Persist.serialize(content, type)
  - Convert an object into a string/bytes suitable to save for the given `type`.
  - Supported types include:
    - nil, :string, :text, :integer, :float, :boolean, :file, :path, :select, :folder, :binary — converted to string representation (IO/StringIO contents read).
    - :array — joined by newline
    - :yaml — YAML.dump
    - :json — JSON.generate
    - :marshal — Marshal.dump
    - :annotation / :annotations — annotation TSV (framework-specific)
    - `<type>_array` variants — will serialize each entry with given `type` and join with newlines
  - Raises if unknown type.

- Persist.deserialize(serialized, type)
  - Converts serialized string back into Ruby object for `type`.
  - Supported types include :string, :integer, :float, :boolean, :array, :yaml, :json, :marshal, :path (returns Path.setup(...)), :file, :file_array, :annotation, and `<type>_array` variants.

---

## Low-level save/load

- Persist.save(content, file, type = :serializer)
  - Save `content` to `file` according to `type`.
  - Uses `Persist.save_drivers[type]` when registered (callable).
    - If the driver arity is 1, it should return serialized string (Persist will sensible_write it).
    - If arity > 1, the driver is called with (file, content) and should perform the save itself.
  - For binary, writes in 'wb' mode.
  - Otherwise calls `serialize` and writes via `Open.sensible_write(file, serialized, :force => true)`.
  - Special `type == :memory` stores content in in-memory hash.
  - Returns nil (or driver-specific return).

- Persist.load(file, type = :serializer)
  - Load and return object saved at `file` according to `type`.
  - Accepts `type` values described in deserialize; special handlers:
    - :binary -> Open.read(file, mode: 'rb')
    - :yaml / :json / :marshal -> uses Open.yaml/open.json/Open.marshal
    - :stream -> returns Open.open(file) (an IO-like stream)
    - :path -> Path.setup(file)
    - :file -> reads content, handles leading `./` as relative path replacement; returns a filename or file path depending on contents
    - :file_array -> reads lines and expands relative paths
    - :memory -> if type is a Hash, returns type[file]
  - Can use custom `Persist.load_drivers[type]` if registered.

- Custom drivers:
  - `Persist.save_drivers[type] = ->(file, content) { ... }` or ->(content) { ... }
  - `Persist.load_drivers[type] = ->(file) { ... }`

---

## The high-level pattern: Persist.persist

The most important API: `Persist.persist(name, type = :serializer, options = {}) { ... }`

Purpose: compute or produce a value and cache it persistently; subsequent calls return cached value unless stale or update requested.

Behavior summary:
- `name` — logical name (used to build persistent path if path not provided).
- `type` — serializer type (see above). `:serializer` resolves to Persist.SERIALIZER.
- `options` — various options (see list below).
- The block computes and returns the value to be persisted (or may write to an IO stream and return an IO to be consumed).
- If a persisted file exists and not stale, `Persist.persist` returns the loaded value (or the file path if `:no_load` true).
- If file absent or stale, it runs the block, saves result via `Persist.save`, and returns result (or file or stream depending on options/return).

Common options (via IndiferentHash/persist-specific keys):
- :dir or :path or :persist[:path] — explicit file path to use (otherwise generated by Persist.persistence_path).
- :data — optional object passed to block when block accepts arity 1.
- :no_load — if true, do not load existing file, return file path instead (or file if empty result).
- :update — boolean or Path; if provided triggers recompute. If a Path is passed it is compared by mtime; if that mtime is newer than the cached file, block executes and caches new result.
- :lockfile — specify lockfile path (or use defaults created under Persist.lock_dir)
- :tee_copies — when block returns an IO stream, tee the stream into multiple copies (useful to both write to file and also return streams)
- :prefix — when persistence_path is generated, can influence tmp filename prefix (used in tests)
- :canfail — if true, swallow save errors (used by some callers)
- :update can be used as a path or Time to force recalculation based on modification time

Concurrency & locking:
- Persist.persist uses `Open.lock` with a lockfile derived from persistence path (unless disabled) to avoid concurrent processes duplicating work.
- When the block returns an IO / StringIO (stream), Persist persists via streaming: it creates tee copies, writes one copy to file (using Open.sensible_write) in a background thread and returns another readable stream to the caller.
  - In that streaming case Persist raises a `KeepLocked` (internal sentinel) so the lock is kept while the background writer thread runs; the calling code obtains an IO to read the stream while the persisting thread writes to file under the same lock.
  - Test usage demonstrates two processes racing to produce the same persisted stream; locking ensures only one writes and others read the saved result or receive a streamed IO.

Return semantics:
- If `no_load` true, returns path (string/Path) instead of loaded object.
- If the block returns `nil`, behavior:
  - If `no_load` true -> return file path (or file)
  - If type nil -> returns nil (no persist)
  - Else attempt to load from file and return result

Memory variant:
- `Persist.memory(name, options = {}, &block)` — convenience calling `Persist.persist` with `:memory` type (keeps persist in RAM).
- `Persist.MEMORY_CACHE` holds memory entries.

Persistence path helper:
- `Persist.persistence_path(name, options = {})` — returns a path in cache_dir for the named persistence file (uses TmpFile.tmp_for_file under the hood). Caller can pass `:dir` override.

---

## Helpers & Open/Path integration

- Open.json(file) / Open.yaml(file) / Open.marshal(file) — convenience wrappers reading & parsing using Open.open.
- `Path#yaml` / `Path#json` / `Path#marshal` are added to Path via persist/path.rb as convenience to call Open.* on a Path.

---

## Examples (from tests)

Save/load primitive types:
```ruby
Persist.save("ABC", "/tmp/x", :string)
Persist.load("/tmp/x", :string)  # => "ABC"

Persist.save([1,2], "/tmp/x", :integer_array)
Persist.load("/tmp/x", :integer_array)  # => [1,2]
```

Using `persist` to cache a computed value:
```ruby
res = Persist.persist("myname", :json, dir: some_dir) do
  expensive_compute()
end
# On subsequent calls returns cached value unless update requested.
```

Streaming content into persistence and returning an IO stream:
```ruby
io = Persist.persist("stream_name", :string, path: file) do
  Open.open_pipe do |sin|
    1000.times { |i| sin.puts "line #{i}" }
  end
end
# io is a readable IO (stream), background thread writes file atomically while caller can read one copy.
```

Memory persistence:
```ruby
value = Persist.memory("key"){ expensive_compute }
```

Force update when a source file changed:
```ruby
Persist.persist("cache_key", :string, update: source_file) { produce_new_value() }
```

---

## Custom drivers

Register custom save/load behavior for a type:
```ruby
Persist.save_drivers[:mytype] = ->(file, content) { ... }   # or ->(content) { ... }
Persist.load_drivers[:mytype] = ->(file) { ... }
```
If driver takes 1 argument it should return serialized string; Persist.save will sensible_write it. If driver expects file as first argument it should perform write itself.

---

## Error handling & notes

- Persist.persist wraps work in an Open.lock to avoid duplicate computations; it will rethrow exceptions by default (unless `:canfail` true).
- If a block raises, persist will normally propagate the exception; tests demonstrate that when the persisted file already exists the caller will get cached value even if block raises (depending on options).
- When streaming, Persist keeps locks while the background writer thread runs (ensures atomicity and consistent readers).
- Persist.save uses `Open.sensible_write` → atomic temp->mv behavior and uses locks when requested.
- The `:path` and `:dir` options allow customizing where persisted files go (useful in tests).
- Use `Persist.save_drivers` and `Persist.load_drivers` to support external formats or custom storage backends.

---

## API quick reference

- Persist.serialize(content, type)
- Persist.deserialize(serialized, type)
- Persist.save(content, file, type = :serializer)
- Persist.load(file, type = :serializer)
- Persist.persist(name, type = :serializer, options = {}) { ... } — high-level caching pattern (with locking)
- Persist.memory(name, options = {}, &block) — in-RAM persist wrapper
- Persist.persistence_path(name, options = {}) — generate a path under Persist.cache_dir
- Persist.cache_dir / Persist.lock_dir — configurable directories
- Persist.save_drivers / Persist.load_drivers — custom driver registries
- Open.json(file), Open.yaml(file), Open.marshal(file) — helpers to read parsed content
- Path#json / Path#yaml / Path#marshal — Path helpers to read persisted data

---

Persist is intended for reproducible caching of computed results in scripts and workflows, where atomic writes and cross-process locking are required. Use `Persist.persist` for the common compute-and-cache pattern; register custom drivers for special file formats or storage backends.