# Architecture

This document explains the internal architecture of scout-essentials: how
modules depend on each other, what the key abstractions are, and how data
flows through the library.

## Module map

Scout-essentials consists of twelve primary modules organized into four
functional layers:

### Foundation layer (no internal dependencies)

| Module | Purpose |
|--------|---------|
| `Log` | Logging, progress bars, colored output, fingerprinting |
| `Misc` | General-purpose helpers (format, digest, math, system, hooks) |
| `TmpFile` | Temporary file and directory management |
| `Annotation` | Runtime object extension for metadata |
| `IndiferentHash` | Key-indifferent hash access |
| `SimpleOPT` (SOPT) | Command-line option parsing |

### I/O layer (depends on foundation)

| Module | Purpose |
|--------|---------|
| `Open` | Unified file I/O: local, compressed, remote |
| `Path` | Logical-to-physical path resolution via path maps |
| `CMD` | External command execution with streaming |

### Concurrency layer (depends on I/O)

| Module | Purpose |
|--------|---------|
| `ConcurrentStream` | Lifecycle management for IO streams |

### Persistence layer (depends on all above)

| Module | Purpose |
|--------|---------|
| `Persist` | Content-addressed caching with serialization |
| `Resource` | On-demand file production via claims |

## Dependency graph

```
Log, Misc, TmpFile (foundation — no internal deps)
        ↑
Annotation, IndiferentHash, SimpleOPT
        ↑
Open, Path, CMD
        ↑
ConcurrentStream
        ↑
Persist, Resource
```

Key cross-module dependencies:
- **Open** depends on Log, TmpFile, Path, ConcurrentStream.
- **Path** depends on Log, Misc, Annotation.
- **CMD** depends on Log, Open, ConcurrentStream, TmpFile.
- **Persist** depends on Log, Open, Path, TmpFile.
- **Resource** depends on Log, Open, Path, Persist, CMD.
- **ConcurrentStream** depends on Log.

## Key abstractions

### The annotated object

The most important pattern: extend a Ruby object (String, Array, Hash, IO)
with a module at runtime. Path is an annotated String. NamedArray is an
annotated Array. IndiferentHash is a setup-based Hash. This preserves type
compatibility while adding behavior.

See [Annotation System](AnnotationSystem.md) for implementation details.

### The setup convention

Nearly every module provides a `.setup` class method that extends an
object and initializes state:

```ruby
Path.setup(str)                    # annotate + init path metadata
NamedArray.setup(arr, fields)      # annotate + init field names
IndiferentHash.setup(hash)         # annotate + enable indifferent access
ConcurrentStream.setup(io, ...)    # annotate + register lifecycle
```

### The lifecycle block

Resources that need cleanup (temp files, open streams, locks) provide a
block form that handles cleanup automatically:

```ruby
TmpFile.with_file { |tmp| ... }    # delete after block
Open.open(file) { |io| ... }       # close after block
Persist.persist(...) { ... }       # lock + write after block
```

## Data flow

### File resolution and reading

```
logical path (String)
    ↓ Path.setup
Path object (annotated String)
    ↓ path.find
physical path (resolved across maps)
    ↓ Open.read
content (String or IO)
```

### Command pipeline

```
CMD.cmd("producer", pipe: true)
    ↓
ConcurrentStream (IO with lifecycle)
    ↓ feed as stdin
CMD.cmd("consumer", in: stream, pipe: true)
    ↓
ConcurrentStream
    ↓ stream.join
final output + exit status check
```

### Resource production

```
Resource.data.file (Path)
    ↓ path.produce
    ↓ check Resource claims
    ↓ acquire Persist lock
    ↓ run production (download / proc / rake)
    ↓ Open.sensible_write (atomic)
physical file
```

## Extension points

1. **Annotation modules** — Create new modules with `extend Annotation` to
   add metadata to any object.
2. **Path maps** — Add search locations with `Path.add_path`.
3. **Persist drivers** — Register custom serialization types.
4. **Resource claim types** — Extend `Resource.produce` for new types.
5. **Log color schemes** — Extend `Log::Color` for custom colors.
6. **CMD tools** — Register tools for auto-installation.

## Related

- [Design Principles](DesignPrinciples.md) — Coding philosophy and idioms.
- [Annotation System](AnnotationSystem.md) — Core extension pattern.
- [Path Resolution](PathResolution.md) — Map-based file resolution.
- [Streaming Model](StreamingModel.md) — ConcurrentStream lifecycle.
- [Persistence and Resources](PersistenceAndResources.md) — Caching and
  production.
