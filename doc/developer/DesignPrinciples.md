# Design Principles

This document explains the coding philosophy behind scout-essentials. It
covers the core conventions, idioms, and patterns that make the code
elegant and expressive. It is intended for framework contributors and
advanced users who want to understand the design rationale.

## Core principles

### 1. Objects, not classes

Scout-essentials avoids subclassing. Instead, it extends existing objects
at runtime with modules. A Path is not a subclass of String — it is a
String that has been extended with `Path` behavior.

**Why?** Because Ruby's core classes (String, Array, Hash, IO) are the
natural data currency of the framework. Subclassing them is fragile and
breaks interoperability. Runtime extension preserves the original class,
so an annotated String still works everywhere a String is expected.

**Idiom:**

```ruby
# Instead of subclassing
class MyPath < String; end  # WRONG

# Extend at runtime
Path.setup(my_string)       # RIGHT — my_string is still a String
```

### 2. The setup convention

Every module that extends objects provides a `.setup` class method. This
method:
1. Extends the object with the module.
2. Initializes any required state (annotations, metadata, lifecycle hooks).
3. Returns the object (not a new instance).

```ruby
Path.setup("data/file")              # annotate + init path metadata
NamedArray.setup([1,2,3], [:a,:b,:c]) # annotate + init field names
IndiferentHash.setup({a: 1})          # annotate + enable indifferent access
```

The setup convention is the entry point for almost every module.

### 3. The lifecycle block

Resources that need cleanup provide a block form that handles cleanup
automatically. This ensures resources are always released, even on error.

```ruby
TmpFile.with_file { |tmp| ... }    # auto-delete
Open.open(file) { |io| ... }       # auto-close
Persist.persist(...) { ... }       # auto-lock
```

**Rule:** If a resource needs cleanup, provide a block form. Never rely on
the caller to remember cleanup.

### 4. Fluent method_missing

Several modules use `method_missing` to build fluent APIs. This is not
metaprogramming for its own sake — it creates a natural language for
expressing paths and structures.

```ruby
# Path uses method_missing to build path hierarchies
base = Path.setup("/project")
base.data.samples        # => "/project/data/samples"
base.data["results"]     # => "/project/data/results"
```

**Rule:** Use method_missing only when it creates a more natural API than
explicit methods. Always pair it with `respond_to_missing?`.

### 5. Composition over configuration

Scout-essentials favors small, composable modules over large configuration
objects. Each module does one thing well. Complex behavior emerges from
composition.

```ruby
# Resource composes: Path (resolution) + Open (I/O) + Persist (locking) + CMD (execution)
# Each module is independent and usable alone
```

### 6. Implicit type conversion

The library works with native Ruby types wherever possible. Modules accept
strings, arrays, hashes, and IOs directly. If conversion is needed, it
happens implicitly via setup.

```ruby
# Open accepts a String, a Path, or a Resource — all resolve to a file path
Open.read("data/file")      # String
Open.read(Path.setup("data/file"))  # Path (annotated String)
Open.read(MyResource.data.file)     # Resource-backed Path
```

### 7. Transparency

Annotated objects are transparent: they pass through all methods that
expect their base type. An annotated String works with `+`, `==`, `split`,
and any method that expects a String. This means annotation is never a
barrier to interoperability.

```ruby
path = Path.setup("data/file")
path + ".bak"            # => "data/file.bak" (String concatenation works)
path.split("/")          # => ["data", "file"] (String method works)
path.size                # => 9 (String method works)
```

### 8. Idempotency

Operations are designed to be idempotent wherever possible. Calling `setup`
multiple times is safe. Producing an existing resource is a no-op. Caching
returns the cached value without re-running the block.

### 9. First-class method objects (Proc/Lambda)

The library heavily uses procs and lambdas as first-class objects. Claims
are procs. Persist blocks are procs. Callbacks are procs. This allows
behavior to be passed around, stored, and composed flexibly.

```ruby
# Resource claim as a proc
claim self.data.file, :proc do
  generate_content
end

# Persist block as a proc
Persist.persist("key", :marshal) do
  compute
end
```

### 9. The annotated string idiom

The most distinctive Scout pattern is the "annotated string": a String that
has metadata attached but remains a String. This pattern is used for:
- **Path** — a String with path resolution behavior.
- **NamedArray** (as strings) — a String with a name.
- **NamedStream** — an IO with a filename.
- **NamedArray** (as arrays) — an Array with field names.

The power of this pattern is that annotated strings are compatible with all
code that expects a String. You can print them, concatenate them, write
them to files, and pass them to commands.

```ruby
path = Path.setup("data/file")
system("cp '#{path}' /backup/")  # works! path is still a String
```

### 10. Position-optional method signatures

Many methods accept either positional or keyword arguments, making the API
flexible and forgiving:

```ruby
# Positional or keyword
JobInfo.setup(obj, "name", :running)       # positional
JobInfo.setup(obj, name: "name", status: :running)  # keyword
```

## Anti-patterns to avoid

### Subclassing core classes

```ruby
# WRONG: subclassing String loses compatibility
class MyString < String; end

# RIGHT: extend at runtime
str = "hello"
str.extend(MyModule)
```

### Defining a new class when annotation suffices

```ruby
# WRONG: a full class for metadata
class SampleMetadata
  attr_accessor :organism, :tissue
  def initialize(name, organism: nil, tissue: nil)
    @name = name
    ...
  end
end

# RIGHT: an annotation module
module SampleMetadata
  extend Annotation
  annotation :organism, :tissue
end
# Apply it to any object: SampleMetadata.setup(sample_name, organism: "Human")
```

### Manual resource management

```ruby
# WRONG: caller must remember cleanup
tmp = TmpFile.tmp_file
Open.write(tmp, data)
process(tmp)
# forgot to delete tmp!

# RIGHT: block form handles cleanup
TmpFile.with_file do |tmp|
  Open.write(tmp, data)
  process(tmp)
end  # auto-deleted
```

### Coupling modules via inheritance

```ruby
# WRONG: tight coupling via inheritance
class MyPersist < Persist; end  # inherits all internals

# RIGHT: composition
class MyPersist
  def initialize
    @cache = Persist  # use Persist as a service
  end
end
```

### Overcomplicating with configuration

```ruby
# WRONG: complex config object
options = { mode: :advanced, features: [:a, :b], nested: { ... } }
ComplexModule.do_thing(options)

# RIGHT: simple API with defaults
SimpleModule.do_thing  # works with no config
```

## Related

- [Architecture](Architecture.md) — Module dependency graph.
- [Annotation System](AnnotationSystem.md) — Implementation of the core
  extension pattern.
- For detailed code investigation, see
  [`../../research/design-philosophy-analysis.md`](../../research/design-philosophy-analysis.md).
