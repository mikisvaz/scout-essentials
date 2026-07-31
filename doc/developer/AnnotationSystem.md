# Annotation System

This document explains how the Annotation system works internally. It is
intended for framework contributors who need to understand or extend the
annotation machinery.

## Why this abstraction exists

Annotation solves a recurring problem: you need to attach metadata to an
object (typically a String or Array) without changing its class. In the
Scout framework, Path objects are annotated Strings, NamedArray objects are
annotated Arrays, and several other modules follow the same pattern.

The alternative — subclassing — is limiting because Ruby's String and Array
are not easily subclassable without losing compatibility with standard
library methods and because subclass instances are not "just a String" to
type-checking code.

Annotation provides a uniform way to extend objects at runtime: define a
module, declare attributes, and apply it with `setup`.

## How it works

### Module definition

```ruby
module MyAnnotation
  extend Annotation
  annotation :attr1, :attr2
end
```

When `extend Annotation` runs:
1. The module gains class methods: `setup`, `purge`, `included`, `annotation`.
2. A `ANNOTATIONS` list is initialized on the module.
3. `annotation_types` accessor is added.

When `annotation :attr1, :attr2` runs:
1. `attr_accessor :attr1, :attr2` is called on the module.
2. `:attr1` and `:attr2` are appended to the module's `ANNOTATIONS` list.

### The `setup` method

```ruby
MyAnnotation.setup(obj, attr1: "value")
```

`setup` performs these steps:
1. Extends `obj` with `MyAnnotation` (if not already extended).
2. Merges annotation types: `obj.annotation_types` is updated to include
   `MyAnnotation` plus all its super-module annotations.
3. Sets the annotation attributes from the keyword arguments or positional
   values.
4. Returns `obj`.

If `obj` is frozen, `setup` duplicates it first.

### The annotated object

After setup, the object has:
- Instance variable accessors for each annotation attribute.
- An `annotation_types` array listing all annotation modules applied.
- All original methods of its base class (String, Array, etc.).

### Annotation propagation

Some Array methods are annotated-method-aware: they propagate annotations
from the source array to the result. This is implemented via
`AnnotatedArray`, which extends the behavior of annotated arrays.

When an array is annotated and extended with `AnnotatedArray`, these methods
propagate annotations:
- `+`, `==`, `each`, `[]`, `collect`, `map`, `compact`, `flatten`, `uniq`,
  `zip`, `values_at`, `first`, `last`, `[]`/slice, and more.

Methods not in this list (e.g., `filter_map`, `tally`) do **not** propagate
annotations.

## Key invariants

1. **Annotated objects keep their original class.** `MyAnnotation.setup(str)`
   does not change `str.class`. The object is still a String.
2. **`setup` is idempotent.** Calling `setup` multiple times with the same
   module merges annotations; it does not create duplicate entries.
3. **`setup` handles frozen objects.** If the target is frozen, `setup`
   duplicates it and annotates the duplicate.
4. **Annotation attributes default to nil.** Unset attributes return nil,
   not an error.
5. **`annotation_types` is cumulative.** If multiple annotation modules are
   applied, `annotation_types` lists all of them.

## Extension points

### Creating new annotation modules

```ruby
module MyMetadata
  extend Annotation
  annotation :foo, :bar
end
```

This is the primary extension point. Any module that `extends Annotation`
becomes an annotation module.

### Adding attributes later

```ruby
MyMetadata.annotation :baz  # adds :baz to ANNOTATIONS and creates accessor
```

### Purging annotations

```ruby
MyMetadata.purge(obj)  # removes annotation methods and state from obj
```

### AnnotatedArray

If you need annotation propagation through array operations, ensure your
annotation module works with AnnotatedArray. NamedArray extends
AnnotatedArray to provide this behavior.

## Interactions with other subsystems

- **Path** — Path is an annotation module. Path.setup(str) annotates a
  string with path resolution behavior and metadata (pkgdir, libdir,
  path_maps, map_order).
- **NamedArray** — NamedArray extends Annotation and AnnotatedArray. It
  adds named field accessors to arrays.
- **IndiferentHash** — While not itself an Annotation module, it follows the
  same setup-based pattern and is often used alongside annotations.
- **ConcurrentStream** — Uses the setup pattern but is not an Annotation
  module. It extends IO objects directly.
- **Open** — Open functions return streams annotated with NamedStream (a
  module that adds `.filename` and `.digest_str` to IO objects).

## Common pitfalls

### Forgetting `extend Annotation`

```ruby
# WRONG: won't have setup, annotation, or annotation_types
module Bad
  annotation :foo  # NoMethodError
end

# RIGHT
module Good
  extend Annotation
  annotation :foo
end
```

### Assuming subclass-level type checks

```ruby
annotated_str = MyAnnotation.setup("hello")
annotated_str.is_a?(String)  # => true
annotated_str.is_a?(MyAnnotation)  # => false (it's extended, not subclassed)
```

To check if an object has an annotation, use `annotation_types` or
`respond_to?`:

```ruby
annotated_str.annotation_types.include?("MyAnnotation")  # => true
annotated_str.respond_to?(:foo)  # => true
```

### Annotation not propagating through array methods

If you annotate an array and then call a method not in AnnotatedArray's
propagation list, the result loses annotations. For example, `filter_map`
and `tally` do not propagate. If you need propagation, convert to
NamedArray or manually re-annotate the result.

## Related

- [Architecture](Architecture.md) — How Annotation relates to other modules.
- [Design Principles](DesignPrinciples.md) — The annotated object idiom.
- For detailed code investigation, see
  [`../../research/annotations-data-analysis.md`](../../research/annotations-data-analysis.md).
