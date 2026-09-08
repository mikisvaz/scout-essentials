# Annotating Data

Annotations attach named metadata — an organism, a provenance URL, a
"kind" of file — to ordinary Ruby objects (Strings, Arrays, Hashes) without
changing their class or wrapping them. This page is the user-facing view of the
system; internals and design notes are in
[Annotation System](../developer/AnnotationSystem.md).

Every example below was run against the current `lib/scout/`.

## Defining an annotation

```ruby
module SampleInfo
  extend Annotation
  annotation :organism, :tissue, :donor
end

sample = SampleInfo.setup('S003', organism: 'Human', tissue: 'Liver')

sample                 # => "S003"      (still a String)
sample.organism        # => "Human"
sample.tissue          # => "Liver"
sample.is_a?(String)   # => true
sample.is_a?(SampleInfo) # => true      (the module really was extended in)
```

`require 'scout-essentials'` is enough: `Annotation` arrives via
`scout/path` (`lib/scout/path.rb:1`).

## The object you get back

`setup` **extends the object you pass, in place**, and returns that same
object — the call is an annotation, not a conversion:

```ruby
name = 'S003'
annotated = SampleInfo.setup(name, organism: 'Human')
annotated.equal?(name)   # => true
```

Two consequences:

- a **frozen** object is `dup`ed first, so `setup` returns a different,
  unfrozen copy — always use the return value;
- `dup` of an annotated object **loses the annotations** (`SampleInfo ===
  sample.dup => false`); `clone` keeps them (`SampleInfo === sample.clone =>
  true` — `clone` copies the singleton class, `dup` does not). To copy
  metadata onto a `dup` explicitly:

```ruby
copy = SampleInfo.setup(sample.dup, sample.annotation_hash)
# or: sample.annotate(other_object)
```

`obj.dup` on an `Integer`-like target is different: `setup` rescues the
`TypeError: can't define singleton` and hands back the plain, un-annotated
object — nothing raises.

## Introspection

```ruby
sample.annotation_types      # => [SampleInfo]      (module objects, not names)
sample.annotation_types.include?(SampleInfo)   # => true

SampleInfo.annotations       # => [:organism, :tissue, :donor]   (module state)

sample.annotation_hash       # => {:organism=>"Human", :tissue=>"Liver"}
sample.annotation_info       # => {..same.., :annotation_types=>[SampleInfo],
                             #     :annotated_array=>false}
sample.annotation_id         # => "860c73f490edb8115064663b7f579d73"
Annotation.is_annotated?(sample)  # => true
```

Note where each thing lives: `annotation_types` is on the **object**; the
declared attribute list is read from the **module** with `.annotations`
(there is no `ANNOTATIONS` constant).

### Round-trip

`annotation_hash` plus `Annotation.setup` is the serialisation pair:

```ruby
info = sample.annotation_info
Annotation.setup('S003', 'SampleInfo', sample.annotation_hash)
```

The type argument may be a `"A|B"` String of module names (unknown names are
only `Log.warn`ed and skipped) or an Array of module objects.

`#serialize` produces the plain Hash (`annotation_info` merged with
`:literal`) consumed by the `:annotation` persistence driver. There is **no
TSV serialisation of annotations in this repo** — `Annotation.tsv` /
`Annotation.load_tsv` live in scout-gear (see the attribution table in
[Architecture](../developer/Architecture.md)).

Nested values you store are left alone: hashes stay plain `Hash`, they are
**not** converted to `IndiferentHash`, and `deep_indifferent` does not exist
in this gem.

## NamedArray — field names over Array positions

`NamedArray` (`lib/scout/named_array.rb`) is a separate annotation module
that gives an Array named fields. It needs its **explicit**
`require 'scout/named_array'` — `scout-essentials.rb` does not load it:

```ruby
require 'scout/named_array'

row = NamedArray.setup(%w[S003 Human Liver], %w[id organism tissue])
row.organism    # => "Human"   (method_missing access)
row[:organism]  # => "Human"
row['tissue']   # => "Liver"
```

Signatures: `NamedArray.setup(array, names, *rest)` — the names are
a positional Array, **not** a `key:` keyword.

### Access is via `method_missing`

Field accessors are *not* real methods, so they do not participate in the
usual introspection:

```ruby
row.respond_to?(:organism)          # => false
row.methods.include?(:organism)     # => false
row.organism                        # => "Human"   (still works)
```

`:[]` accepts a Symbol or a String and resolves through the field list
(`identify_name`), so a field named like an Array method can still be reached
positionally by name.

### Array methods shadow field names

If a field is called `first`, `last`, `count`, `zip`, `sample` … the real
`Array` method wins:

```ruby
row2 = NamedArray.setup(%w[a b c], %w[first second third])
row2.first       # => "a"      (Array#first, not the field)
row2.first(2)    # => ["a", "b"]

row3 = NamedArray.setup(%w[S001 S002 S003], %w[values count])
row3.values      # => "S001"   (field: Array has no #values)
row3.count       # => 3        (Array#count wins, not the field)
```

Note `values` — unlike `first`/`count` — is **not** an `Array` method, so the
field accessor still works; `count` is real and wins. Prefer field names that
are not `Array`/`Enumerable` verbs, or use `row[:name]` for ambiguous ones.

`to_hash` (only available on `NamedArray`) returns an `IndiferentHash` of
field → value.

Watch out for `id` — `annotation_id` (aliased `id`) is defined by the
annotation system itself, so a field named `id` collides and the digest is
returned instead.

## `AnnotatedArray` — elements inherit the container's annotations

Annotate the *container*, then `extend AnnotatedArray`, and every element
handed out by `[]`, `first`, `last`, `each`, `collect`, `select`, `compact`,
`uniq`, `flatten`, `reverse`, `sort_by`, `subset`, `remove` is re-annotated:

```ruby
samples = SampleInfo.setup(%w[S001 S002 S003], organism: 'Human')
samples.extend AnnotatedArray

samples[0].organism    # => "Human"
samples.each { |s| s.organism }
samples.collect { |s| s.length }   # [4, 4, 4], elements annotated
samples.select { |s| s != 'S002' } # re-annotated array
```

Not overridden — **annotations are dropped** (method owners are
`Array`/`Enumerable`): `map`, `zip`, `+`, `filter_map`, `flat_map`,
`each_slice`, `values_at`. `zip` in particular does not propagate annotations
to the *other* operand's elements.

`[index]` re-annotates; `[index, true]` (the clean second argument) returns the
raw element with no annotations (`lib/scout/annotation/array.rb:21-25`).

Two hard limits:

- elements must be extendable: an Array of `Integer`s raises `TypeError: can't
  define singleton`;
- `#make_array` does **not** annotate the elements — it wraps `self` in a
  one-element annotated Array (see
  [Annotation System](../developer/AnnotationSystem.md)).

## Related

- [Annotation System](../developer/AnnotationSystem.md) — internals, limits,
  serialisation drivers.
- [Path Resolution](../developer/PathResolution.md) — `Path` is an annotated
  module.
- [Caching Results](CachingResults.md) — the `:annotation` persistence type.
