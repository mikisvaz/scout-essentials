# Annotation System

Annotations attach named metadata to **ordinary Ruby objects** without
wrapping them and without changing their class. The same mechanism is what
makes `Path`, `Resource` and `NamedArray` work, so understanding it is a
prerequisite for [Path Resolution](PathResolution.md) and
[Persistence and Resources](PersistenceAndResources.md).

Everything on this page is backed by `tmp/rewrite_C/probe_01..04.rb` and
probes P36–P42 in `research/behavior-probes.md`, run against the current
`lib/scout/annotation*.rb`.

## Load path

`lib/scout-essentials.rb` does **not** require `scout/annotation` directly.
`Annotation` becomes available because `scout/path` requires it
(`lib/scout/path.rb:1`), so `require 'scout-essentials'` gives you the
constant (`Object.const_defined?(:Annotation) => true`, probe_03) — but a
library that only wants annotations can `require 'scout/annotation'` on its
own.

## The DSL

```ruby
module SampleInfo
  extend Annotation
  annotation :organism, :tissue
end
```

`extend Annotation` turns the module into an **AnnotationModule**. The
`annotation` class-level call does three things (annotation_module.rb):

- declares the attribute list, kept in module state `@annotations` and read
  with `SampleInfo.annotations` (there is **no `ANNOTATIONS` constant**);
- defines reader/writer methods (`#organism`, `#organism=`) for when the
  module is mixed into an object;
- registers the module so `Annotation.setup` can resolve type names.

## `setup` and the binding rules

`AnnotationModule#setup(obj, values = nil, &block)` is the constructor. The
values may be given as a Hash or positionally, and a block is an alternative
source for the object itself:

```ruby
SampleInfo.setup('S003', organism: 'Human', tissue: 'Liver')
SampleInfo.setup('S004', %w[Human Liver])          # positional, same order
SampleInfo.setup { 'S005' }                         # block-as-object
```

Rules verified in probe_01/probe_02:

- **In-place extension.** `setup` calls `obj.extend SampleInfo` on the object
  you pass and returns **that same object** (`setup(s).equal?(s) => true`) —
  except when the object is **frozen**, in which case `obj.dup` is annotated
  and returned instead; always use the return value of `setup`.
- **TypeError → un-annotated.** Objects that cannot hold singleton methods
  (`Integer` literals, symbols) raise `TypeError: can't define singleton`;
  `setup` rescues it and returns the *plain* object with no metadata.
- **`:annotation_types` is reserved.** Each annotated object gets an
  `@annotation_types` array; declaring `annotation :annotation_types` collides
  with it (probe_01: writing to it raised `NoMethodError` against `nil`).

## Introspection and serialisation

State lives on the object, the type list on the object too:

```ruby
s = SampleInfo.setup('S003', organism: 'Human', tissue: 'Liver')

SampleInfo.annotations           # => [:organism, :tissue]   (module state)
s.annotation_types               # => [SampleInfo]           (module objects!)
Annotation.is_annotated?(s)      # => true
s.is_a?(SampleInfo)              # => true  (extend really happened)
s.is_a?(String)                  # => true  (class unchanged)
```

`annotation_types` holds the **module objects**, never their names —
`s.annotation_types.include?(SampleInfo)` is the correct membership test.

`AnnotatedObject` (mixed into every annotated object) provides:

```ruby
s.annotation_hash   # => {:organism=>"Human", :tissue=>"Liver"}
s.annotation_info   # => {:organism=>"Human", :tissue=>"Liver",
                    #     :annotation_types=>[SampleInfo], :annotated_array=>false}
s.serialize         # => {...same, :literal=>"S003"}   (values purged recursively)
s.annotation_id     # => "860c73f490edb8115064663b7f579d73"
```

- `annotation_hash` — the declared attributes only;
- `annotation_info` — plus `:annotation_types` and `:annotated_array`;
- `serialize` — `annotation_info` merged with `:literal` (the object itself),
  with every value passed through `Annotation.purge` (annotated_object.rb:23);
  this is what the `:annotation` serialisation driver consumes. It is **only a
  Hash here**; the TSV form (`Annotation.tsv` / `Annotation.load_tsv`) lives in
  scout-gear, not in this repo (attribution table in
  [Architecture](Architecture.md));
- `annotation_id` (aliased `id`) — `Misc.digest([self, annotation_info])`.

### Module-level helpers

- `Annotation.is_annotated?(obj)` — true if any annotation module is mixed in.
- `Annotation.purge(obj)` — **recursive**: for an annotated object it calls the
  instance `#purge`; for Arrays/Hashes it purges each element; otherwise it
  returns the object unchanged.
- `Annotation.setup(obj, "A|B", hash)` — the generic deserialiser. The type
  string is split on `|`, each name resolved with `Object.const_get`. **Unknown
  names only warn and are skipped** (`Log.warn "Annotation NoSuchAnnotation not
  defined"`, probe_01) — no exception.

### Instance-side helpers

- `#purge` — returns a **copy**: it removes `@annotation_types`, `@annotations`
  and every attribute ivar from a `dup` (and purges nested values) and returns
  it. The object's own class is kept (a purged `SampleInfo` String is still a
  `String`, no longer `is_a?(SampleInfo)`); always use the return value.
- `#make_array` — wraps `self` in a **one-element Array** carrying the same
  annotations and extends it with `AnnotatedArray` (annotated_object.rb:75-80);
  it does not annotate the receiver's elements.
- `#annotate(other)` — copies the current annotations onto another object.

## Round-trips and copies

- **Marshal round-trips** annotations (P42, probe_01): the singleton modules
  survive dump/load.
- **Only `dup` loses them; `clone` keeps them** (probe_02:
  `dup is_annotated? => false`, `clone is_annotated? => true, .a => 1` —
  `clone` copies the singleton class, `dup` does not): to re-annotate a `dup`
  copy the metadata explicitly with `annotation_hash` →
  `Annotation.setup` / `MyModule.setup`, or call `#annotate` on the copy.

## `AnnotatedArray`

`extend AnnotatedArray` on an annotated Array — the pattern used throughout
`test/scout/annotation/test_array.rb` — makes the *elements* carry the
container's annotations:

```ruby
arr = SampleInfo.setup(%w[S001 S002], organism: 'Human')
arr.extend AnnotatedArray
arr[0].organism        # => "Human"
arr.first.organism     # => "Human"
```

Overrides provided in `lib/scout/annotation/array.rb`:

- `[]` `(pos, clean = false)` — the element is re-annotated unless the second
  argument is truthy, in which case it is returned clean (probe_09: a fresh
  array's `fresh[0, true]` is an un-annotated `String` while `fresh[1]` is
  annotated);
- `first`, `last`, `each_with_index`, `each`, `inject`, `collect`, `select` —
  re-annotated;
- `compact`, `uniq`, `flatten`, `reverse`, `sort_by` — re-annotated;
- `subset(list)`, `remove(list)` — set operations (`&`, `-`) with
  re-annotation.

**Limits** — live probe `tmp/rewrite_C/probe_09_annotated_array.rb` (method
owners plus actual results): `map`, `zip`, `filter_map`, `flat_map`,
`each_slice`, `values_at` and `count` are **not overridden** (their owner is
`Array`/`Enumerable`) and return plain results with no annotations — `ary.map
{ |x| x }` yields `[false, false, false]` under `Annotation.is_annotated?`,
while `ary.each` yields `[true, true, true]`, and `zip` keeps annotations only
on the container-side elements.

**Requirement:** elements must be extendable. `AnnotatedArray` over an Array
of `Integer`s raises `TypeError: can't define singleton` (probe_09) — use
Strings or other extendable objects.

## NamedArray is a separate thing

`NamedArray` (`lib/scout/named_array.rb`) is an Annotation module over Arrays
giving field-name access to positions. It does **not** extend
`AnnotatedArray` and is not a String type. It needs an explicit
`require 'scout/named_array'`. See [Annotating
Data](../user/AnnotatingData.md).

## Related

- [Path Resolution](PathResolution.md) — `Path` is an annotated module.
- [Persistence and Resources](PersistenceAndResources.md) — `Resource` is an
  annotated module; `:annotation` serialisation uses `serialize`.
- [Annotating Data](../user/AnnotatingData.md) — the user-facing API.
