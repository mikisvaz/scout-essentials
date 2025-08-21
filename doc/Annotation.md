# Annotation

The Annotation module provides a lightweight system for adding typed, named "annotations" (simple instance variables with accessors) to arbitrary Ruby objects and arrays. It's used by defining annotation modules (modules that `extend Annotation` and declare attributes via `annotation`) and then applying those annotation modules to objects at runtime.

Key features:
- Define annotation modules with named attributes.
- Attach annotation modules to objects or arrays (including Strings, Arrays, Hashes, Procs, etc.).
- Annotated arrays (`AnnotatedArray`) propagate annotations to their items and provide annotation-aware iteration and collection operations.
- Support for serialization (Marshal) and a `purge` operation that strips annotations from objects (recursively for arrays and hashes).

---

## Creating an annotation module

Define a module and `extend Annotation`. Declare annotation attributes using `annotation :attr1, :attr2`.

Example:

```ruby
module MyAnnotation
  extend Annotation
  annotation :code, :note
end
```

When a module is created this way, it gets:
- an internal `@annotations` list (names of attributes),
- accessors for declared attributes (e.g. `code`, `code=`),
- the ability to be used to annotate objects (`MyAnnotation.setup(obj, ...)` or by `obj.extend MyAnnotation`).

---

## Applying annotations

Use `Annotation.setup` or the annotation module's `setup` to attach annotations to objects.

Basic usage:

- Annotation.setup with a single annotation module:
  ```ruby
  Annotation.setup(obj, MyAnnotation, code: "X")
  ```
  or
  ```ruby
  MyAnnotation.setup(obj, code: "X")
  ```

- Annotation.setup accepts annotation types as:
  - a Module constant (e.g. `MyAnnotation`),
  - an Array of modules (`[A, B]`),
  - a String of module names separated by `|` (will be constantized).

- The `annotation_hash` (values for attributes) can be:
  - a Hash mapping attribute name => value,
  - a list of positional values that are zipped with the declared attribute names,
  - a Hash with string keys (converted to symbols).
  Examples:
  ```ruby
  MyAnnotation.setup(obj, :code)                # sets first attribute to :code (positional)
  MyAnnotation.setup(obj, code: "some text")    # sets code => "some text"
  MyAnnotation.setup(obj, "code" => "v")        # string keys are accepted
  MyAnnotation.setup(obj, code2: :code)         # remap behavior (see examples below)
  ```

- `Annotation.setup` convenience:
  ```ruby
  # Apply one or more annotation modules
  Annotation.setup(obj, [MyAnnotation, OtherAnnotation], code: "c", code3: "d")
  ```

Notes on calling `AnnotationModule.setup` (the module-level setup method used by both `Annotation.setup` and `AnnotationModule.setup`):
- If the target `obj` is frozen, it will be duplicated before extending.
- If a block is passed or `obj` is `nil` and a block is provided, the block (Proc) itself will be annotated (useful to attach annotations to callbacks).
- When multiple modules are applied to the same object, their annotations are merged; accessors are available for all annotated attributes.

Examples from tests:
```ruby
str = "String"
MyAnnotation.setup(str, :code)
# now str responds to `code` and `code` == :code
```

You can annotate other objects using an annotated object:
```ruby
a = MyAnnotation.setup("a", code: "c")
b = "b"
a.annotate(b)   # copies the annotation values and types from a to b
```

---

## Annotated object API

When an object is annotated (extended with annotation modules), it gains these helpers (provided by `Annotation::AnnotatedObject`):

- `annotation_types` -> Array of annotation modules applied to the object.
- `annotation_hash` -> Hash mapping annotation attribute names (symbols) to values stored on the object.
- `annotation_info` -> combines `annotation_hash` plus:
  - `annotation_types` (modules list),
  - `annotated_array` boolean (true when object is an `AnnotatedArray`).
- `.serialize` (instance) and `AnnotatedObject.serialize(obj)` (class method) -> returns a purged `annotation_info` merged with a `literal: obj` entry (useful when creating stable representations).
- `annotation_id` / `id` -> deterministic digest built from the object and its annotation info (uses `Misc.digest` in the framework).
- `annotate(other)` -> applies all annotation types and attribute values of `self` onto `other`.
- `purge` -> returns a duplicate of the object with all annotation-related instance variables removed (`@annotations`, `@annotation_types`, `@container`).
- `make_array` -> returns a new array containing the object, annotated with the same annotation types/values, and extended as an `AnnotatedArray`.

Example:
```ruby
s = MyAnnotation.setup("s", code: "C")
s.annotation_hash   # => { code: "C" }
s.id                # => some digest
s2 = "other"
s.annotate(s2)
s2.code             # => "C"
```

---

## Annotated arrays (AnnotatedArray)

`AnnotatedArray` is an array mixin that:
- stores annotation types/values at the array level,
- automatically annotates elements when they are accessed or iterated,
- provides container tracking on items: annotated items get `container` and `container_index` attributes (via `AnnotatedArrayItem`).

To make an array annotation-aware:
```ruby
AnnotationModule.setup(ary, code: "C")
ary.extend AnnotatedArray
```

Behavior and methods:
- Element access ([], first, last) returns annotated elements (unless `clean = true` passed to `[]`).
- `each`, `each_with_index`, `select`, `inject`, `collect` iterate over annotated items (so blocks receive annotated items).
- `compact`, `uniq`, `flatten`, `reverse`, `sort_by` are overridden to return annotated arrays (the result is annotated and extended with `AnnotatedArray`).
- `subset(list)` and `remove(list)` return new annotated arrays representing the set intersection/difference.
- Annotated array items receive `container` (the array) and `container_index` (the index position when produced via iteration/access).

Examples:
```ruby
ary = ["x"]
MyAnnotation.setup(ary, "C")
ary.extend AnnotatedArray

ary.code          # => "C"        (array-level)
ary[0].code       # => "C"        (element annotated)
ary.first.code    # => "C"
ary.each { |e| puts e.code }  # iterates annotated elements
```

`AnnotatedArrayItem` helpers:
- `container` -> reference to the array that annotated the item.
- `container_index` -> index position supplied by the array when returning that item.

Utility:
- `AnnotatedArray.is_contained?(obj)` -> true if obj is annotated as an `AnnotatedArrayItem`.

---

## Serialization and Marshal support

Annotations are stored as instance variables on the annotated objects; thus, `Marshal.dump` / `Marshal.load` preserve annotations and attribute values.

Example (from tests):
```ruby
a = MyAnnotation.setup("a", code: 'test1', code2: 'test2')
serialized = Marshal.dump(a)
a2 = Marshal.load(serialized)
a2.code   # => 'test1'
```

Arrays extended with `AnnotatedArray` and annotated likewise survive Marshal roundtrip; loaded arrays still annotate their elements.

---

## Purging annotations

- AnnotatedObject#purge removes annotation instance variables from the object and returns a dup without annotations (`@annotations`, `@annotation_types`, `@container`).
- Annotation.purge(obj) is recursive:
  - If obj is nil => returns nil.
  - If obj is an annotated array => calls the object's purge and then purges each element recursively.
  - If obj is an Array => returns an Array where each element is purged.
  - If obj is a Hash => returns a new Hash with purged keys and values.
  - Otherwise, if object is annotated (`Annotation.is_annotated?(obj)`), returns `obj.purge`, else returns the object itself.

Example:
```ruby
ary = ["string"]
MyAnnotation.setup(ary, "C")
ary.extend AnnotatedArray

Annotation.is_annotated?(ary)          # => true
Annotation.is_annotated?(ary.first)    # => true

purged = Annotation.purge(ary)
Annotation.is_annotated?(purged)       # => false
Annotation.is_annotated?(purged.first) # => false
```

---

## Detection helpers

- `Annotation.is_annotated?(obj)` -> true if the object has been annotated (the object has an `@annotation_types` instance variable).
- `AnnotatedArray.is_contained?(obj)` -> true if object is an `AnnotatedArrayItem`.

---

## Extending and composing annotations

- Multiple annotation modules can be applied to the same object. Their attributes and values are merged on the object.
- Annotation modules may `include` other annotation modules. When a module including another annotation module is itself extended into an object, the included module's declared attributes are propagated.
- When a module `extend Annotation`, the `Annotation.extended` hook ensures:
  - `@annotations` is initialized,
  - the module includes `Annotation::AnnotatedObject` (so annotated objects get object helpers),
  - the module extends `Annotation::AnnotationModule` (which implements `annotation`, `setup`, and include/extend integration code).

Example of composing annotations:
```ruby
module A
  extend Annotation
  annotation :a1
end

module B
  extend Annotation
  annotation :b1
end

obj = "s"
Annotation.setup(obj, [A, B], a1: 'one', b1: 'two')
# obj now responds to a1, b1
```

---

## Notes and edge cases

- `Annotation.setup(obj, ...)` returns `nil` immediately if `obj.nil?`.
- If the target object is frozen, the setup will duplicate it before extending.
- `AnnotationModule.setup` can accept positional values (zipped with the declared attributes) or a hash mapping attribute names to values.
  - Example: `MyModule.setup(obj, :val_for_first)` sets the first declared attribute to `:val_for_first`.
  - Example: `MyModule.setup(obj, :a => 1, :b => 2)` sets attributes by name.
- You can annotate a block/proc by passing a block to `setup` (or passing `nil` as the object and supplying a block). The block (Proc) will be extended with the annotation module.
- `Annotation.setup` accepts a third argument (`annotation_hash`) or positional values similar to the module-level `setup`. It also accepts `annotation_types` as a string with `|` separated module names, an Array of modules, or a single module.

---

## API quick reference

Annotation module-level:
- Annotation.setup(obj, annotation_types, annotation_hash_or_positional_values)
  - obj: object to annotate (String, Array, Array instance, Proc, etc.)
  - annotation_types: Module, String (module names separated by `|`), or Array of modules
  - annotation_hash_or_positional_values: Hash or positional values mapped to declared attributes
  - returns the annotated object (or nil if obj.nil?)

- Annotation.extended(base) (internal hook) — prepares modules that `extend Annotation`.
- Annotation.is_annotated?(obj) -> boolean
- Annotation.purge(obj) -> returns object or a purged (annotation-free) copy/structure

Annotation::AnnotationModule (module methods available on modules that `extend Annotation`):
- annotation(*attrs) -> declare attributes and create accessors
- annotations -> declared attributes list
- included(mod) — when the annotation module is included in another module, merges declared attributes
- extended(obj) — when the annotation module is extended into an object, sets up `@annotations` and registers this module into the object's `annotation_types`
- setup(obj, *values_or_hash, &block) -> annotate `obj` (or block) with this module and set attribute values

Annotation::AnnotatedObject (instance methods added to annotated objects):
- annotation_types -> array of modules applied
- annotation_hash -> Hash of attribute names => values
- annotation_info -> combines annotation_hash + metadata
- serialize / AnnotatedObject.serialize(obj) -> purged annotation_info merged with literal
- annotation_id / id -> digest based id
- annotate(other) -> copy annotations onto `other`
- purge -> duplicate object and remove annotation instance variables
- make_array -> wrap object into annotated array

AnnotatedArray (array-level helpers):
- extend AnnotatedArray to annotate arrays and propagate annotations to their items
- annotate_item(obj, position = nil) -> annotate an item and set container/container_index
- [] (overridden), first, last, each, each_with_index, select, inject, collect, compact, uniq, flatten, reverse, sort_by, subset, remove

---

## Examples (from tests)

Define annotation modules:

```ruby
module AnnotationClass
  extend Annotation
  annotation :code, :code2
end

module AnnotationClass2
  extend Annotation
  annotation :code3, :code4
end
```

Annotate a string:

```ruby
str = "String"
AnnotationClass.setup(str, :code)    # sets str.code == :code
AnnotationClass2.setup(str, :c3, :c4)
# str now includes both annotation modules and has code/code2/code3/code4
```

Annotate arrays and propagate to elements:

```ruby
ary = ["string"]
AnnotationClass.setup(ary, "Annotation String")
ary.extend AnnotatedArray
ary.code       # => "Annotation String"
ary[0].code    # => "Annotation String"
ary.first.code # => "Annotation String"
```

Purge annotations:

```ruby
ary = ["string"]
AnnotationClass.setup(ary, "C")
ary.extend AnnotatedArray

purged = Annotation.purge(ary)
# purged and purged.first are not annotated anymore
```

Marshal roundtrip preserves annotations:

```ruby
a = AnnotationClass.setup("a", code: 'test1', code2: 'test2')
d = Marshal.dump(a)
a2 = Marshal.load(d)
a2.code # => 'test1'
```

Annotating a block:

```ruby
# annotate the block (proc) itself
proc_obj = AnnotationClass.setup(nil, code: :c) do
  puts "hello"
end
proc_obj.code # => :c
```

This document covers the primary use and behaviors of Annotation, the annotation modules that extend it, the AnnotatedObject helpers added to annotated objects, and the AnnotatedArray behaviors. Use the examples above as templates to create, combine, and apply annotations to objects and collections.