# Investigation: Design Philosophy and Cross-Cutting Patterns

**Status:** Non-normative investigation artifact. May be outdated.

## Scope
Cross-cutting design principles that make scout-essentials elegant and
expressive, identified by analyzing patterns across all modules.

---

## Principle 1: Annotate, don't wrap

**The single most important principle.** When you have a piece of data that
already has a natural Ruby type (String, Array, Hash, IO), you do not create
a wrapper class. Instead, you annotate it.

```ruby
# GOOD — annotate an existing object
path = Path.setup("data/file.tsv")   # path.class == String
gene = Gene.setup("BRCA1", :organism, "Hsa")  # gene.class == String

# WRONG — create a wrapper class
class MyPath < String; end            # breaks String API
class GeneWrapper; def initialize(g); @g = g; end; end  # loses String-ness
```

Annotation uses Ruby's singleton-class extension:
- `extend SomeModule` on the specific object instance.
- The object's class is unchanged.
- The annotation is removable via `Annotation.purge`.

This principle is applied to: Path (annotated Strings), NamedArray (annotated
Arrays), IndiferentHash (annotated Hashes), ConcurrentStream (annotated IOs).

---

## Principle 2: Module composition over inheritance

There are no deep class hierarchies. Behavior is composed via Ruby modules
mixed into objects at runtime.

```ruby
# Path = String + Path annotations
module Path
  extend Annotation       # becomes an annotation module
  annotation :pkgdir, :libdir, :path_maps, :map_order, :where, :original
end

path = Path.setup("data/file.tsv")  # String + Path module
```

Each concern is a module: Annotation, IndiferentHash, ConcurrentStream,
Resource, Path. They can be mixed into the same object without conflict.

---

## Principle 3: `setup` is the constructor

Classes are rarely instantiated with `.new`. Instead, `Module.setup(obj, ...)`
extends an existing object with the module and sets its annotations.

```ruby
# Annotation modules provide a class-level `setup` method
Path.setup("data/file.tsv", "mypkg")        # → annotated String
IndiferentHash.setup({a: 1})                 # → annotated Hash
ConcurrentStream.setup(io, pids: [123])      # → annotated IO
Gene.setup("BRCA1", :organism, "Hsa")        # → annotated String
```

`setup` always returns the same object it received (after extension). It does
not clone unless the object is frozen. This means `setup` is idempotent and
non-destructive.

---

## Principle 4: `method_missing` as a fluent builder

When a module needs to provide a dynamic, open-ended API, `method_missing` is
used to build structures fluently.

```ruby
# Path uses method_missing to build nested paths
path = Path.setup("data")
path.genes.tsv           # → "data/genes/tsv" (annotated Path)
path.results["run1"]     # → "data/results/run1"

# NamedArray uses method_missing for field accessors
arr = NamedArray.setup([1, 2, 3], [:a, :b, :c])
arr.a   # → 1
arr.b   # → 2
```

The key insight: `method_missing` is not for error recovery, it's for
**building an API that mirrors the domain**. Path segments become method
names; field names become accessors.

---

## Principle 5: Conventions for resource discovery

The framework discovers resources by convention, not by explicit registration:

| Convention | Resolution |
|---|---|
| Path maps `{PKGDIR}`, `{LIBDIR}`, `{PWD}`, `{HOME}` | Automatically resolved |
| `Resource.claim(path, type, &block)` | Declares how to produce a path |
| `CMD.tool(:name) { ... }` | Registers tool auto-install |
| `Path#find` | Tries each map in `map_order` |
| `Resource#produce` | Triggers claim if file missing |

There are no plugin manifests or registration calls. Put a claim in the right
module and the framework finds it.

---

## Principle 6: The "produced on demand" pattern

Files are not pre-generated. They are produced lazily when first accessed:

```ruby
module MyData
  extend Resource
  self.claim Path.setup("data/file.tsv"), :proc do |path|
    Open.write(path, generate_data())
  end
end

path = MyData.data["file.tsv"]  # accesses via method_missing
path.read                        # triggers produce → generate_data()
path.read                        # second read: file exists, no production
```

This is the Scout equivalent of a build system. The claim is the build rule;
`produce` is the build trigger; `find` is the output path.

---

## Principle 7: Stream everything

Expensive I/O (command output, file reads, network) is always returned as
streams, not eagerly-read buffers. Streams are ConcurrentStream-enhanced IOs
with lifecycle management:

```ruby
stream = CMD.cmd("cat huge_file", :pipe => true)
stream.each_line { |line| process(line) }
stream.join  # wait for command completion
```

- `pipe: true` → streaming mode.
- Default → blocking mode (reads all output).
- Streams carry their PID/threads for proper cleanup.
- Streams support callbacks for cleanup.

---

## Principle 8: IndiferentHash everywhere

Options and configuration are always IndiferentHash — symbol/string
indifferent. This eliminates symbol-vs-string bugs:

```ruby
options = IndiferentHash.setup({})
options[:model] = "gpt-4"
options['model']  # → "gpt-4"
options[:model]   # → "gpt-4"
```

All option-processing utilities (`process_options`, `add_defaults`, `pull_keys`)
work on IndiferentHash. When writing code that accepts options, use these
utilities.

---

## Principle 9: Self-documenting through annotation propagation

When you extract items from annotated collections, they inherit the parent's
annotations:

```ruby
list = Gene.setup(["BRCA1", "TP53"], :organism, "Hsa")
list.first.organism  # → "Hsa" (inherited from parent list)
list.select { |g| g.length > 4 }.organism  # → "Hsa" (preserved through select)
```

This is the AnnotatedArray pattern: enumeration methods are overridden to
propagate annotations. The data carries its metadata with it.

---

## Principle 10: Compact DSLs over verbose configuration

Scout prefers compact, expressive DSLs:

```ruby
# SOPT compact definition
SOPT.parse("-t--tool* tool to use
-d--database* database
-v--verbose")

# Path maps as a hash of templates
path_maps = {
  current: "{PWD}/{TOPLEVEL}/{SUBPATH}",
  home:    "{HOME}/{TOPLEVEL}/{PKGDIR}/{SUBPATH}"
}
```

Configuration is data (hashes, strings), not objects.

---

## Anti-patterns to avoid

### 1. Creating wrapper classes for native types
```ruby
# WRONG
class PathWrapper
  def initialize(path); @path = path; end
  def read; File.read(@path); end
end

# RIGHT — annotate
path = Path.setup("data/file.tsv")
path.read  # works because Resource/path.rb adds read
```

### 2. Eager initialization
```ruby
# WRONG
class Processor
  def initialize
    @cache = build_huge_cache()  # expensive, always runs
  end
end

# RIGHT — lazy
def cache
  @cache ||= build_huge_cache()
end
```

### 3. Explicit delegation when method_missing already works
```ruby
# WRONG — don't add these to a module that already uses method_missing
def data; @path.data; end
def results; @path.results; end

# RIGHT — method_missing handles it
```

### 4. Not using IndiferentHash for options
```ruby
# WRONG — symbol/string fragility
def foo(options)
  options[:key] || options['key']  # verbose, error-prone
end

# RIGHT
def foo(options)
  options = IndiferentHash.setup(options) unless IndiferentHash === options
  options[:key]
end
```

### 5. Breaking the annotate-don't-wrap principle for IO
```ruby
# WRONG
class TrackedStream
  def initialize(io); @io = io; end
end

# RIGHT — annotate the IO
ConcurrentStream.setup(io, :pids => [pid], :threads => [thread])
```

### 6. Forgetting to `join` streams
```ruby
# WRONG — orphaned subprocess
stream = CMD.cmd("long_command", :pipe => true)
lines = stream.readlines  # may leave process running if exception

# RIGHT
begin
  stream = CMD.cmd("long_command", :pipe => true)
  lines = stream.readlines
ensure
  stream.join
end
```

### 7. Mutating global path configuration
```ruby
# WRONG — affects all paths globally
Path.path_maps = { ... }  # class-level mutation

# RIGHT — per-path or per-resource
path = Path.setup("data", path_maps: { ... }, map_order: [...])
```

---

## Cross-cutting utilities (Misc module)

The `Misc` module is a grab-bag of utilities used across the codebase. It is
the "stdlib" of scout-essentials. Key categories:

### Format utilities
- `Misc.format_paragraph(text, size, indent, offset)` — word-wrap text to fit
  terminal width, preserving code blocks and lists.
- `Misc.format_definition_list(hash, sep)` — format a hash as `key: value`.
- `Misc.format_seconds(time)` — `HH:MM:SS` format.
- `Misc.format_seconds_short(time)` — human-readable short form.
- `Misc.colors_for(list)` — assign hex colors to unique elements.

### Math utilities
- `Misc.log2(x)`, `Misc.log10(x)` — cached multiplier versions.
- `Misc.max`, `Misc.min`, `Misc.mean`, `Misc.stddev` — list statistics.
- `Misc.zip_fields(lists)` — transpose arrays.
- `Misc.bin_for_value`, `Misc.bins` — histogram binning.

### Digest utilities
- `Misc.digest_str(obj)` — deterministic string representation for digesting.
- `Misc.digest(obj)` — MD5 of `digest_str`.
- `Misc.file_md5(path)` — MD5 of file content.
- `Misc.obj_md5(obj)` — MD5 of object representation.

### Filesystem utilities
- `Misc.in_dir(dir) { ... }` — chdir + yield + restore.
- `Misc.path_relative_to(basedir, path)` — relative path computation.
- `Misc.add_libdir(dir)` — add lib directory to LOAD_PATH.
- `Misc.zip_zones`, `Misc.tar_files` — archive helpers.

### System utilities
- `Misc.hostname` — cached hostname.
- `Misc.children(pid)` — child processes.
- `Misc.pid_alive?(pid)` — check if process is alive.

### Process utilities
- `Misc.benchmark(repeats) { ... }` — benchmark and log.
- `Misc.insist(times, sleep) { ... }` — retry with exponential backoff.
- `Misc.pid_alive?(pid)` — check liveness.

### Matching utilities
- `Misc.match_value(value, condition)` — fuzzy/comparison matching.
- `Misc._convert_match_condition(str)` — parse `>1`, `/regex/`, `!value`, etc.
- `Misc.intersect_sorted_arrays(a1, a2)` — efficient sorted intersection.

---

## Gotchas and warnings

1. **Annotation `setup` on frozen objects** — `setup` dup's frozen objects,
   which creates a new instance. If you hold a reference to the original
   frozen object, it won't have the annotation.
2. **`method_missing` can mask typos** — In Path, calling `path.typo_method`
   will create a new path `"data/typo_method"` instead of raising. This is by
   design but can cause subtle bugs.
   - Mitigation: `path.method_missing` only fires if the method name doesn't
     start with `to_` and no block is given.
3. **IndiferentHash default value interaction** — if a hash has a `default`
   or `default_proc`, the alternate-form lookup is bypassed. This can silently
   return the default instead of trying the other key form.
4. **ConcurrentStream callback ordering** — callbacks are chained in LIFO
   order (most recently added runs first). If ordering matters, document it.
5. **Persist cache path determinism** — the path is derived from the name +
   options hash. If the options hash is not deterministic (e.g., contains a
   Proc or a non-deterministic object), the cache path changes every run.
6. **Resource produce race condition** — if two processes call `produce`
   simultaneously on a non-existent resource, both will run the claim. The
   lock prevents this, but only if both use the same lock path. Verify that
   `Open.lock` is always called with the canonical lock path.
7. **Log.severity is global** — changes affect all threads. Use
   `Log.with_severity(level) { ... }` for scoped changes.
8. **Misc.digest of a Path** — `Misc.digest` checks if the string is a valid
   filename and if so, digests the file content. This is usually desired
   (digesting the data, not the path string), but can be surprising.
9. **Path.map_order as class variable** — `@@map_order` is shared across all
   Path instances. Modifying it globally affects all paths. Per-instance
   `@map_order` can be set during `Path.setup`.
10. **Annotation propagation may not match expectations** — AnnotatedArray
    overrides specific enumeration methods (`[]`, `first`, `last`, `select`,
    `collect`, etc.). Methods not in the list (e.g., `filter_map`, `tally`)
    will NOT propagate annotations.
