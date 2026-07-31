# Investigation: Persistence, Resources, and Concurrency

**Status:** Non-normative investigation artifact. May be outdated.

## Scope
Persist, Resource, ConcurrentStream, and their interactions.

---

## Persist

### What it is
A caching module that saves the result of expensive computations to disk (or
memory), keyed by a deterministic cache path. It provides type-aware
serialization and deserialization, multiple serialization drivers, and
concurrent-safe production via file locking.

### Core pattern: `persist` / `persist`-with-block
```ruby
result = Persist.persist("my_data", :string, :path => "/cache/my_data") do
  expensive_computation()
end
```
- If `/cache/my_data` exists, the stored value is loaded.
- If not, the block is executed, and the result is saved.
- The `:path` determines where on disk.
- The type (`:string`, `:marshal`, `:array`, etc.) determines serialization.

### Serialization types
Supported by `serialize`/`deserialize`:
- `:string`, `:text`, `:integer`, `:float`, `:boolean` — basic type coercion.
- `:array` — newline-joined.
- `:yaml`, `:json`, `:marshal` — standard serializers.
- `:binary` — raw bytes.
- `:file` — stores a path to another file (pointer).
- `:annotation`, `:annotations` — via `Annotation.tsv`.
- `<type>_array` — array of the inner type (e.g., `:integer_array`).
- `:memory` — uses the in-memory `Persist::MEMORY` hash.
- Custom drivers — registered via `save_drivers`/`load_drivers` hashes.

### `persist` lifecycle
1. Generate a cache path (via `persist_path` if not given).
2. Check if the cache file exists.
3. If it exists: load and return.
4. If not: acquire a lock (`Open.lock`), check again (double-check locking),
   execute the block, save the result, release the lock, return.

### `persist_path` generation
When `:path` is not explicitly provided, Persist builds one from the name and
options using `TmpFile.tmp_for_file`:
```ruby
Persist.persist_path("my_data", :some_option => "value")
# => ~/tmp/scout/tmpfiles/my_data·SOME_OPTION=VALUE
```
This means the cache path is deterministic for the same name + options,
enabling automatic cache reuse.

### Concurrency model
- `Open.lock(cache_path + '.lock')` — uses lockfiles for cross-process safety.
- Double-check: checks existence again inside the lock.
- Multiple processes attempting to produce the same cache will block on the
  lock, and the second will find the file already present.

### `persist_tsv` (legacy)
`Persist.persist_tsv(database, file, data, type)` is a convenience for caching
TSV-style data. It wraps the persist pattern with TSV-specific serialization.
In scout-essentials, this exists but the main TSV class is not included —
this method is for integration with downstream TSV-using code.

---

## Resource

### What it is
A module for declaring **named resources** that can be produced on demand.
A Resource module acts as a namespace: it defines a root path (where files
live), claims (how to produce each file), and a path resolution scheme.

### Anatomy of a Resource module
```ruby
module MyResource
  extend Resource
  self.claim Path.setup("data/file.tsv"), :proc do |path|
    # produce the file at `path`
  end
end
```
- `extend Resource` — becomes a resource namespace.
- `claim(path, type, content = nil, &block)` — declare how to produce a path.
- `self.root` — the filesystem root for this resource.
- `self.pkgdir` — package name for path resolution.
- `self.subdir` — subdirectory under the root.

### Claim types
1. `:string` — write the string content to the path.
2. `:url` — download the URL to the path.
3. `:proc` — call the block; it returns String/IO/Array/TSV to write.
   - `arity == 0` → block takes no args, returns data.
   - `arity == 1` → block receives the output path.
4. `:rake` — run a Rake task (with `ScoutRake.run`).
5. `:install` — install software (uses `Resource.install`).
6. `:csv` — (declared but not implemented — raises).

### Production lifecycle (`produce`)
1. Resolve the path to find its current location (`path.find`).
2. If the file exists at the resolved location, return.
3. If a claim exists for this path:
   - Acquire a lock (`Open.lock`).
   - Re-check existence (double-check).
   - Execute the claim (write string, download URL, run proc, run rake, etc.).
   - If the claim type is missing, try `.gz` / `.bgz` variants.
4. On error: remove the partial file and re-raise.
5. After production, reset the path's location cache.

### Resource → Path integration
The `Resource/path.rb` file adds `produce`, `produce_and_find`, `produce_with_extension`,
`relocate`, `identify`, `open`, `read`, `write`, `list`, `exists?`, and
`find_with_extension` methods to all Path objects.

This means **any Path can be produced on-demand** if its `pkgdir` is a
Resource module. This is the key integration: `path.produce` checks existence,
and if the file is missing, triggers production.

### Software installation (`Resource/software.rb`)
- `Resource.install(url_or_spec, name, software_dir)` — downloads and extracts
  software packages.
- `set_software_env(software_dir)` — adds installed software to PATH and
  LD_LIBRARY_PATH.
- Used by the `:install` claim type.

### Resource relocation and identification
- `Resource.relocate(path)` — moves a resource to a better location based on
  resource identification.
- `Resource.identify(path)` — determines the canonical identity of a path.

---

## ConcurrentStream

### What it is
A mixin that augments IO-like objects (pipes from `CMD`, file streams from
`Open`, in-memory streams) with concurrency-aware lifecycle management:
thread/pid tracking, join/abort semantics, callback chains, and error
propagation.

### Core attributes
- `threads` — threads that produce the stream's data.
- `pids` — subprocess PIDs that produce the stream's data.
- `callback` — Proc chain called on successful `join`.
- `abort_callback` — Proc chain called on `abort`.
- `autojoin` — if true, the stream auto-joins on close/eof.
- `no_fail` — if true, suppress process failures (log instead of raise).
- `pair` — a paired stream (e.g., stdout/stderr pair) that is aborted together.
- `lock` — an associated lock released on join/abort.
- `stream_exception` — exception captured during streaming; raised on join.
- `joined`, `aborted` — state flags.

### Lifecycle: join
1. `join_threads` — wait for all producer threads; check `Process::Status` for
   failures; raise `ConcurrentStreamProcessFailed` on failure (unless `no_fail`).
2. `join_pids` — `Process.waitpid` for each PID; check exit status.
3. Check `stream_exception` — raise if set.
4. `join_callback` — call the callback chain.
5. `close` — close the underlying IO.
6. Release the lock.

### Lifecycle: abort
1. Set `stream_exception` if not already set.
2. Call `abort_callback` chain.
3. `abort_threads` — raise `Aborted` exception in each producer thread.
4. `abort_pids` — send `SIGINT` to each PID.
5. Abort the pair stream if present.
6. Close the IO.
7. Release the lock.

### Callback chaining
`ConcurrentStream.setup(stream, :callback => proc1)` then
`ConcurrentStream.setup(stream, :callback => proc2)` results in a chained
callback that calls `proc1` then `proc2`. This allows multiple subsystems to
attach cleanup logic to the same stream without coordination.

### Annotate (propagation)
`ConcurrentStream#annotate(stream)` copies threads, pids, callback, etc. to
another stream. Used by CMD when transforming streams (e.g., decompressing).

### `process_stream` class method
`ConcurrentStream.process_stream(stream, **kwargs) { ... }` — a convenience
wrapper that sets up the stream, runs the block, and ensures proper
join/abort in case of exception. Used by stream-consuming code for
guaranteed cleanup.

### AbortedStream
`AbortedStream.setup(obj, exception)` — marks a stream as aborted, attaching
the exception. Consumers can check `AbortedStream === stream` and access
`stream.exception`.

---

## Cross-module interactions

- **Persist depends on Open** — for file I/O, locking, and atomic writes.
- **Persist depends on TmpFile** — for cache path generation.
- **Resource depends on Open, Path, TmpFile** — for production, path
  resolution, and locking.
- **CMD depends on ConcurrentStream** — CMD.cmd returns ConcurrentStream-enhanced
  IO objects that track the subprocess PID and threads.
- **Open depends on ConcurrentStream** — Open.stream wraps IO objects with
  ConcurrentStream for lifecycle safety.
- **ConcurrentStream depends on IndiferentHash** — for `process_options`.
- **Log::ProgressBar depends on CMD** — `guess_obj_max` uses `CMD.cmd("wc -l")`
  to estimate total lines in a file.

---

## Gotchas and warnings

1. **Persist.persist silently returns nil on failure** — if the block returns
   `nil`, `Persist.save` returns immediately without writing. The cache file
   is not created, so the next call will re-execute the block.
2. **Persist MEMORY type is process-local** — `:memory` persistence uses a
   global `Persist::MEMORY` hash, which is lost when the process exits. It is
   suitable only for within-process caching.
3. **Resource.produce fallback to .gz/.bgz** — if no claim matches, produce
   tries `path + '.gz'` then `path + '.bgz'`. This is usually desired but can
   cause confusing errors if you expected a specific extension.
4. **ConcurrentStream.join is idempotent** — calling `join` on an already-joined
   stream is safe (returns without re-joining), but the `@joined` flag is set
   even if the join raised an exception.
5. **ConcurrentStream callback chains can grow** — each `setup` call with a
   `:callback` prepends to the chain. Long chains from repeated `setup` calls
   may cause unexpected ordering.
6. **CMD no_fail streams** — a stream with `no_fail: true` will log errors but
   not raise. Reading from it may produce truncated output. Check
   `stream.exit_status` if you need to verify success.
7. **Open.lock requires the lock directory to exist** — if the directory does
   not exist, the lock file cannot be created and the lock fails silently.
8. **Resource :csv claim type raises NotImplementedError** — declared but
   not implemented. If you encounter this, use `:proc` with manual CSV parsing.
9. **Persist caching of nil results** — if the computation block returns `nil`,
   no cache file is written, leading to re-computation on every call. Use a
   sentinel value if nil is a valid result.
10. **ConcurrentStream.pair abort propagation** — aborting a stream also aborts
    its pair. If you only want to abort one side of a stdout/stderr pair, you
    must detach the pair first (set `pair = nil`).
