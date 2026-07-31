# Caching Results

This guide explains how to cache computation results in scout-essentials
using the Persist module. You'll learn about the persist pattern,
serialization types, memory caching, and custom drivers.

## When to use this

- You have expensive computations that should run only once.
- You need to serialize Ruby objects to disk in a type-aware way.
- You want a simple caching API that handles atomic writes and locking.
- You need to cache results that are keyed by input parameters.

## Concepts

### The persist pattern

The core of Persist is the `persist` method. You give it a unique key, a
serialization type, and a block. If a cached result exists, it's loaded. If
not, the block runs, the result is saved, and then returned.

```ruby
result = Persist.persist("my_computation", :marshal) do
  expensive_computation
end
```

The first call runs the block and saves the result. Subsequent calls load
the cached result directly.

### Serialization types

Persist supports many serialization types. Choose the one that best fits
your data:

| Type | Serialization | Deserialization |
|------|--------------|-----------------|
| `:string`, `:text` | Raw string | Raw string |
| `:integer` | `to_s` | `to_i` |
| `:float` | `to_s` | `to_f` |
| `:boolean` | `to_s` | `"true"` → true, else false |
| `:array` | Lines joined by `\n` | Split by `\n` |
| `:yaml` | `YAML.dump` | `YAML.load` |
| `:json` | `JSON.generate` | `JSON.parse` |
| `:marshal` | `Marshal.dump` | `Marshal.load` |
| `:path` | `to_s` | `Path.setup(...)` |
| `:binary` | Raw bytes | Raw bytes |
| `:file` | Path string | Path (relative to cache) |

Array variants like `:yaml_array` or `:string_array` serialize each element
individually and join with newlines.

## Basic usage

### Caching a computation

```ruby
# The key uniquely identifies the computation
result = Persist.persist("unique_key_here", :marshal) do
  compute_large_matrix(input_params)
end
```

### Using a specific cache file

```ruby
# Cache to a specific path instead of an auto-generated one
result = Persist.persist("key", :yaml, path: "cache/result.yaml") do
  computation
end
```

### Checking if cached

```ruby
# Check if a cache file exists without triggering computation
path = Persist.persistence_path("my_key", :marshal)
File.exist?(path)  # => true if cached
```

## Serialization

### Saving and loading directly

```ruby
# Save any object
Persist.save(my_data, "data.yaml", :yaml)
Persist.save(my_hash, "data.json", :json)
Persist.save(my_object, "data.marshal", :marshal)

# Load
data = Persist.load("data.yaml", :yaml)
```

### Custom serialization drivers

Register custom serialization for your own types:

```ruby
# Register a custom serializer
Persist.save_drivers[:my_format] = lambda do |file, content|
  Open.write(file, MySerializer.dump(content))
end

# Register a custom deserializer
Persist.load_drivers[:my_format] = lambda do |file|
  MySerializer.load(Open.read(file))
end

# Use it
Persist.persist("key", :my_format) do
  MyData.new(...)
end
```

## Memory caching

For in-process caching that doesn't write to disk:

```ruby
result = Persist.persist("key", :memory) do
  expensive_computation
end
```

Memory caches persist only for the lifetime of the process. They are useful
for avoiding redundant computations within a single run.

## Cache configuration

### Default directories

Persist uses two directories:
- `Persist.cache_dir` — where cached data files are stored.
- `Persist.lock_dir` — where lock files for concurrent access are stored.

```ruby
# View defaults
Persist.cache_dir  # => #<Path var/cache/persistence>
Persist.lock_dir   # => #<Path tmp/persist_locks>

# Override
Persist.cache_dir = Path.setup("/my/cache/dir")
Persist.lock_dir = "/my/lock/dir"
```

## Common mistakes

### Using the wrong serialization type

```ruby
# WRONG: marshaling a simple string is wasteful
Persist.persist("key", :marshal) { "hello" }

# RIGHT: use :string for simple values
Persist.persist("key", :string) { "hello" }
```

### Non-unique keys

```ruby
# WRONG: same key for different inputs
Persist.persist("results", :marshal) { compute(a) }
Persist.persist("results", :marshal) { compute(b) }
# Second call returns cached result from compute(a)!

# RIGHT: include input in the key
Persist.persist("results_#{a}", :marshal) { compute(a) }
Persist.persist("results_#{b}", :marshal) { compute(b) }
```

### Forgetting that persist is idempotent

The block passed to `persist` runs only if the cache is empty. If you need
to recompute, delete the cache file first:

```ruby
File.delete(Persist.persistence_path("key", :marshal))
```

## See also

- [Working with Files](WorkingWithFiles.md) — Persist uses Open for atomic
  writes.
- [Producing Resources](ProducingResources.md) — Resource composes with
  Persist.
- For internal implementation details, see
  [Persistence and Resources](../developer/PersistenceAndResources.md).
