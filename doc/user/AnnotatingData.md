# Annotating Data

This guide explains how to attach metadata to objects in scout-essentials.
You'll learn about annotations, named arrays, and key-indifferent hashes —
three tools that make data manipulation more expressive without sacrificing
compatibility with standard Ruby.

## When to use this

- You need to attach metadata to a String, Array, or Hash without changing
  its type.
- You want array elements accessible by name (like a struct or tuple).
- You're tired of `hash[:key]` vs `hash["key"]` errors.

## Concepts

### Annotations

An annotation is a set of named attributes attached to an object. The object
keeps its original class — an annotated String is still a String — but gains
accessor methods for the annotation attributes.

```ruby
module SampleMetadata
  extend Annotation
  annotation :organism, :tissue, :donor
end

sample = "S001"
SampleMetadata.setup(sample, organism: "Human", tissue: "Liver")

sample            # => "S001" (still a String)
sample.organism   # => "Human"
sample.tissue     # => "Liver"
sample.donor      # => nil
```

### Named arrays

A named array is an Array where each position has a name. You can access
elements by position or by name.

```ruby
values = NamedArray.setup([42, "active", 3.14], [:count, :status, :score])

values[0]      # => 42        (by position)
values[:count] # => 42        (by name)
values["status"] # => "active" (string key works too)
values.count   # => 42        (method access)

values.to_hash # => {count: 42, status: "active", score: 3.14}
```

### Key-indifferent hashes

An IndiferentHash is a Hash where string and symbol keys are interchangeable.

```ruby
h = IndiferentHash.setup({a: 1, "b" => 2})

h[:a]   # => 1
h["a"]  # => 1
h[:b]   # => 2
h["b"]  # => 2
```

## Creating annotation modules

Define a module, extend it with `Annotation`, and declare attributes:

```ruby
module JobInfo
  extend Annotation
  annotation :name, :status, :cpu_time
end
```

You can add more attributes later:

```ruby
JobInfo.annotation :memory  # adds the :memory accessor
```

## Applying annotations

### To a single object

```ruby
obj = "my_job"
JobInfo.setup(obj, name: "analysis", status: :running)
obj.name    # => "analysis"
obj.status  # => :running
```

You can also use positional values (they fill attributes in declaration order):

```ruby
JobInfo.setup(obj, "analysis", :running)
obj.name    # => "analysis"
```

### To multiple objects at once

```ruby
Annotation.setup(array, [JobInfo, OtherAnnotation], name: "x", other: "y")
```

### Checking annotations

```ruby
obj.respond_to?(:status)  # => true
obj.annotations         # => [:name, :status, :cpu_time]
obj.respond_to?(:name)  # => true
```

## Named arrays in detail

### Creating named arrays

```ruby
# With field names
arr = NamedArray.setup([1, 2, 3], [:x, :y, :z])

# With field names and a key (primary field)
arr = NamedArray.setup([1, 2, 3], [:x, :y, :z], key: :x)
```

### Accessing by name

```ruby
arr[:y]       # => 2
arr["z"]      # => 3
arr.y         # => 2
```

### Converting to hash

```ruby
arr.to_hash   # => IndiferentHash { :x => 1, :y => 2, :z => 3 }
```

### Iterating with names

Named arrays support annotation-aware operations. Standard Array methods
like `each`, `map`, `select` work as expected. Some methods like `zip`,
`collect`, and `[]` propagate annotations to results.

## Key-indifferent hashes in detail

### Creating

```ruby
h = IndiferentHash.setup({foo: 1})
# or
h = IndiferentHash.setup({ "foo" => 1 })
```

### Nested hashes

Nested hashes are automatically set up:

```ruby
h = IndiferentHash.setup({ config: { port: 8080 } })
h["config"]["port"]  # => 8080
```

### Merging

```ruby
h1 = IndiferentHash.setup({a: 1, b: 2})
h2 = {b: 3, c: 4}

h1.merge(h2)       # => {a: 1, b: 3, c: 4} (IndiferentHash)
h1.deep_merge(h2)  # recursively merges nested hashes
```

### Case-insensitive variant

If you need case-insensitive keys:

```ruby
h = CaseInsensitiveHash.setup({Format: "CSV"})
h["format"]  # => "CSV"
h[:FORMAT]   # => "CSV"
```

## Common mistakes

### Forgetting to call `setup`

```ruby
# WRONG: extend alone doesn't initialize attributes
obj = "test"
obj.extend(JobInfo)
obj.name  # => nil (or error: attribute not initialized)

# RIGHT: use setup
JobInfo.setup(obj, name: "test")
obj.name  # => "test"
```

### Assuming annotation changes the class

```ruby
metadata = SampleMetadata.setup("S001", organism: "Human")
metadata.class  # => String (not SampleMetadata)
metadata + "!"  # => "S001!" (String operations still work)
```

### Modifying a frozen object

If the target object is frozen, `setup` duplicates it first. The original
remains frozen and unchanged.

## See also

- [Working with Files](WorkingWithFiles.md) — Path objects are annotated
  strings.
- For internal implementation details, see
  [Annotation System](../developer/AnnotationSystem.md).
