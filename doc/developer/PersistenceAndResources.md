# Persistence and Resources

This document explains how Persist and Resource compose to provide caching
and on-demand resource production. It is intended for framework contributors.

## Why these abstractions exist

### Persist

Persist solves the problem of avoiding redundant computation. Many
operations in data-intensive applications are expensive (downloads, large
sorts, alignments) and should run only once. Persist provides a content-
addressed caching layer: you give it a key and a serialization type, and
it stores the result in a file whose name is derived from the key.

### Resource

Resource solves the problem of declaring where files come from. In a
distributed environment, files may need to be downloaded, generated, or
installed on first use. Resource lets you "claim" a path — declare how it
should be produced — and the framework produces it on demand.

Together: Persist provides the storage layer; Resource provides the
declaration and production layer.

## How they work

### Persist

#### The persist pattern

```ruby
Persist.persist("unique_key", :marshal) do
  expensive_computation
end
```

1. `Persist.persist` computes a cache path from the key (via digest).
2. If the cache file exists, it loads and returns the cached value.
3. If not, the block runs, the result is serialized to the cache file, and
   then returned.
4. Locking ensures safe concurrent access: while one process writes,
   others wait or return the previous cached value.

#### Cache path computation

The cache path is derived from:
- The key string (digested if long, used directly if short and filesystem-
  safe).
- The serialization type (appended to the filename).
- The configured `Persist.cache_dir`.

```ruby
Persist.persistence_path("my_key", :yaml)
# => #<Path var/cache/persistence/my_key.yaml>
```

#### Serialization drivers

Persist maintains two registries:

```ruby
Persist.save_drivers  # type -> lambda { |file, content| ... }
Persist.load_drivers  # type -> lambda { |file| ... }
```

Built-in types include `:string`, `:yaml`, `:json`, `:marshal`, `:float`,
`:integer`, `:boolean`, `:array`, `:path`, `:binary`. Custom types are
registered by adding to these registries.

#### Locking

Persist uses file-based locks (via Lockfile) to ensure concurrent safety:

```ruby
Persist.lock(file) do
  # exclusive access to file
end
```

While locked, other processes block (or return cached value if available).
This prevents races when multiple processes try to produce the same cache
entry simultaneously.

### Resource

#### Claim system

A Resource module declares how to create files via `claim`:

```ruby
module MyResource
  claim self.data.file, :string, "content"
  claim self.data.other, :proc do
    generate_content
  end
  claim self.data.remote, :url, "https://example.com/data"
end
```

Each claim registers a type and content. The claim types:

- `:string` — write the string to the file.
- `:proc` — call the proc; write its return value to the file. If the proc
  has arity 1, it receives the target filename and is expected to write
  directly.
- `:url` — download and save.
- `: Resource.produce` handles additional types like `:rake` (run a
  Rakefile) and `:install` (run a software installer).
- Custom types can be added by extending `Resource.produce`.

#### Production lifecycle

```ruby
path = MyResource.data.file

# Production
path.produce
```

1. Check if the file already exists. If yes, return the path.
2. Acquire a lock (via Persist's locking mechanism) to prevent concurrent
   production.
3. Run the production logic based on the claim type.
4. Atomically write the result to the target path.
5. Release the lock.
6. Return the path.

Production is atomic: the content is written to a temporary file first,
then moved into place. This prevents partial reads.

#### Resource module setup

```ruby
module MyResource
  extend Resource
  self.pkgdir = 'myresource'  # package directory name
  self.subdir = Path.setup('share/mypkg')  # optional subdirectory
end
```

### Composition of Persist and Resource

Resource uses Persist's locking mechanism for production safety. The flow
is:

1. User calls `path.produce` on a Resource-backed path.
2. Resource checks if the file exists.
3. If not, Resource acquires a Persist lock.
4. Production logic runs (download, generate, etc.).
5. Content is atomically written via `Open.sensible_write`.
6. Lock is released.
6. Path is returned.

This means:
- Multiple processes trying to produce the same resource serialize safely.
- The first process to acquire the lock does the work; subsequent ones find
  the file already exists.
- If the producer fails, the lock is released and no partial file remains.

## Key invariants

1. **Persist is keyed by a unique string.** The cache filename is derived
   from the key. Non-unique keys cause collisions.
2. **Resource production is idempotent.** Producing an existing resource
   is a no-op.
3. **Resource production is atomic.** No partial files are left on failure.
4. **Both use locking for concurrency safety.** Locks prevent races.
5. **Resource claims are module-level.** Claims are registered on the
   Resource module and persist for the lifetime of the process.

## Extension points

### Custom Persist drivers

```ruby
Persist.save_drivers[:my_format] = ->(file, content) { ... }
Persist.load_drivers[:my_format] = ->(file) { ... }
```

### Custom Resource claim types

Extend `Resource.produce` to handle new types:

```ruby
module MyResource
  class << self
    def produce_with_my_type(path, resource, claim_type, content)
      if claim_type == :my_custom_type
        produce_my_custom(path, content)
      else
        produce_without_my_type(path, alias, claim_type, content)
      end
    end
    alias_method :produce_without_my_type, :produce
    alias_method :produce, :produce_with_my_type
    end
end
```

### Custom resource modules

Create a module that extends Resource:

```ruby
module MyAppResources
  extend Resource
  self.pkgdir = 'myapp'
end
```

## Interactions with other subsystems

- **Open** — Both Persist and Resource use Open for file I/O (atomic
  writes, streaming, remote access).
- **Path** — Both use Path for path resolution and metadata.
- **TmpFile** — Both use TmpFile for temporary file creation during atomic
  writes.
- **Log** — Both use Log for progress reporting and diagnostics.
- **CMD** — Resource's `:rake` and `:install` claim types run commands
  via CMD.

## Common pitfalls

### Persist key collisions

Two different computations with the same key share the same cache file.
Ensure keys are unique per computation. Including input parameters in the
key is the safest approach.

### Resource claim types

The claim type must match what `Resource.produce` expects. If you pass a
proc with the wrong arity (e.g., arity 1 when it should be arity 0), the
production logic may write to the target file directly instead of returning
content.

### Forgetting to extend Resource

```ruby
# WRONG
module Bad
  claim self.file, :string, "content"  # NoMethodError
end

# RIGHT
module Good
  extend Resource
  claim self.method, :string, "content"
end
```

### Production not triggering

`Path.find` does not trigger production. Use `path.produce` or
`path.exists?(produce: true)` to ensure production.

## Related

- [Architecture](Architecture.md) — How Persist and Resource fit in the
  dependency graph.
- [Path Resolution](PathResolution.md) — How paths resolve before
  production.
- For detailed code investigation, see
  [`../../research/persistence-resources-analysis.md`](../../research/persistence-resources-analysis.md).
