# Investigation: Annotations, Data Structures, and Options

**Status:** Non-normative investigation artifact. May be outdated.

## Scope
Annotation, NamedArray, IndiferentHash, CaseInsensitiveHash, SimpleOPT (SOPT).

---

## Annotation system

### What it is
A lightweight, non-invasive system for attaching typed, named metadata
(instance variables with accessors) to **any** Ruby object — strings, arrays,
hashes — without subclassing or wrapping. The object's class never changes.

### Core mechanism
1. A module calls `extend Annotation` to become an "annotation module."
2. `extend Annotation` triggers `Annotation.extended(base)`, which:
   - Initializes `@annotations = []` on the module.
   - `include`s `AnnotatedObject` into the module (providing `annotate`,
     `purge`, `annotation_hash`, etc.).
   - `extend`s `AnnotationModule` onto the module (providing `annotation`,
     `setup`, `annotations`).
3. `annotation :attr1, :attr2` calls `attr_accessor` on each and records them
   in `@annotations`.
4. `MyMod.setup(obj, ...)` extends `obj` with `MyMod`, copies annotation types
   into `obj.annotation_types`, and sets instance variables for each annotation
   attribute.

### setup() parameter resolution
`setup` is flexible about arguments:
- Positional: `MyMod.setup(obj, val1, val2)` → `@attr1 = val1, @attr2 = val2`
  (via `attrs.zip(rest)`).
- Hash: `MyMod.setup(obj, {attr1: val1, attr2: val2})` → used directly as pairs
  when keys match annotation names.
- Block: `setup(*args) { |obj| ... }` — block receives the object, args are rest.
- Frozen objects are dup'd before extending.

### AnnotatedObject mixin
Provides:
- `annotation_types` — array of modules applied to this object.
- `base_type` — last annotation type applied (the "primary" type).
- `annotation_hash` — `{ name => value }` for all annotated attributes.
- `annotate(other)` — copies all annotations to another object.
- `purge` — returns a clean duplicate with all annotation ivars removed.
- `annotation_id` / `id` — digest of `[self, annotation_info]`.
- `make_array` — wraps self in a single-element array and extends with AnnotatedArray.

### AnnotatedArray mixin
When an annotated object is itself an Array, `AnnotatedArray` provides:
- Automatic annotation propagation: `[]`, `first`, `last`, `each`, `each_with_index`,
  `select`, `collect`, `compact`, `uniq`, `flatten`, `reverse`, `sort_by` —
  each returns results annotated with the parent's types.
- `annotate_item(obj, pos)` — sets `container` and `container_index` on each
  item (via `AnnotatedArrayItem`), then annotates.
- `subset(list)`, `remove(list)` — set operations that preserve annotations.

### Key insight: the propagate-through-enumeration pattern
AnnotatedArray overrides Array enumeration methods so that **every element
extracted from an annotated array inherits the parent's annotations**. This
is why you can do:
```ruby
list = Gene.setup(["BRCA1", "TP53"], :organism, "Hsa")
list.first.organism  # => "Hsa"  (inherited from parent)
```

---

## NamedArray

### What it is
An extension of Annotation for Arrays that adds **named fields** and name-based
accessors. Built directly on the Annotation system.

### Annotations
- `fields` — ordered list of field names for each array position.
- `key` — optional primary key field name.

### Key methods
- `[](name_or_index)` — resolves a name to position via `identify_name`, then
  delegates to `Array#[]`.
- `[]=(name_or_index, value)` — same resolution for assignment.
- `to_hash` — returns an `IndiferentHash` mapping field names → values.
- `concat(hash_or_array)` — if given a Hash, appends its values and adds keys
  to fields.
- `method_missing` — provides getter accessors for field names (`a.foo`).

### Name resolution (identify_name)
- `nil` → 0
- Integer/Range → returned as-is
- Symbol `:key` → returns `:key` sentinel
- Otherwise: exact match, then numeric-as-index, then fuzzy match
  (parentheses containment, space-prefix).
- `strict: true` disables fuzzy matching.

### Class helpers
- `zip_fields(array)` — transpose a list-of-lists.
- `add_zipped(source, new)` — incrementally merge zipped lists.
- `field_match(field, name)` — fuzzy matching predicate.

---

## IndiferentHash

### What it is
A module mixin for Hash instances that makes key access indifferent to
String vs Symbol. Also includes a rich set of options-processing utilities.

### Core behavior
- `setup(hash)` extends a single hash instance.
- `[](key)` — tries exact key, then alternate form (symbol ↔ string).
- `[]=(key, value)` — deletes any existing variant first, then sets.
- `include?(key)` — checks both forms.
- Nested hashes are auto-extended on read.
- `merge`, `deep_merge`, `slice`, `except`, `values_at`, `delete` — all
  form-indifferent.
- `clean_version` — returns a plain Hash with stringified keys.

### Options utilities (IndiferentHash::Options)
- `add_defaults(options, defaults)` — adds missing keys.
- `process_options(hash, *keys)` — extract-and-remove keys, with defaults.
- `pull_keys(hash, prefix)` — extract `prefix_*` keys into a new hash.
- `zip2hash(list1, list2)` — zip two lists into an IndiferentHash.
- `positional2hash(keys, *values)` — convert positional args to a hash.
- `hash2string` / `string2hash` — serialize/parse simple hashes.
- `parse_options(str)` — parse shell-like `key=value` strings.
- `print_options(options)` — serialize to space-separated string.

### CaseInsensitiveHash
Separate mixin: `setup(hash)` makes string key lookup case-insensitive
by maintaining a `original_key_by_downcase` map.

---

## SimpleOPT (SOPT)

### What it is
A lightweight command-line option parser with:
- A compact DSL for declaring options.
- `--long` / `-short` / `--key=value` parsing.
- Boolean and string-typed options.
- Usage/help text generation.

### Declaration styles
1. `SOPT.parse("-f--first* first arg")` — compact definition string.
2. `SOPT.register(short, long, asterisk, description)` — explicit.
3. `SOPT.setup(heredoc)` — parse a help-text heredoc, register options,
   and auto-consume ARGV.

### Option format
`-short--long[*] description`
- `*` marks string-valued; absence marks boolean.
- Short is optional (auto-generated if nil/true).

### Parsing (consume)
- `SOPT.consume(args = ARGV)` scans tokens, removes recognized options.
- Returns an IndiferentHash with symbol keys.
- Accumulates into `SOPT.GOT_OPTIONS`.

### Documentation generation
- `SOPT.doc` — full manpage-style help.
- `SOPT.input_format` — single-option usage fragment.
- `SOPT.usage` — print doc and exit.

### Gotchas
- `input_defaults` is **documentation-only**; parser does not apply defaults.
- Shortcut auto-generation skips punctuation (`.`, `-`, `_`).
- Boolean false must be `--flag=false` or a `false`/`F`/`no` token.

---

## Cross-module interactions

- **NamedArray depends on Annotation** — extends Annotation, declares
  `:fields` and `:key`.
- **NamedArray.to_hash depends on IndiferentHash** — returns IndiferentHash.
- **SOPT depends on IndiferentHash** — parsed options are IndiferentHash;
  `parse_options` and `print_options` from IndiferentHash::Options are used.
- **SOPT uses Log** — for colored output in doc generation.
- **Annotation.purge recursively purges** — handles nested Arrays and Hashes.

---

## Gotchas and warnings

1. **Annotation.setup with a single Hash arg and multiple attributes**: the
   condition `attrs.length != 1` is buggy — it should be `attrs.length == 1`
   (line in annotation_module.rb). This can cause unexpected behavior when
   setting up with a hash where keys don't match attribute names.
2. **IndiferentHash#[] with default/default_proc**: if the hash has a default
   and the key is not in `keys`, the default is returned **without** trying
   the alternate form. This can silently mask symbol/string mismatches.
3. **SOPT fix_shortcut may return nil** — if no unique shortcut can be found,
   the option is registered with no shortcut. No error is raised.
4. **AnnotatedArray collect vs map**: `collect` is overridden but `map` is
   not explicitly handled. In Ruby `map` is an alias for `collect`, so it
   should work, but the override uses `inject` rather than `super`, which
   loses any block-passing nuance.
5. **NamedArray#method_missing provides getters only** — no setters. Use `[]=`.
6. **IndiferentHash#keys_to_sym!** uses `rescue` for failed conversions,
   silently skipping unconvertible keys.
7. **Annotation on frozen objects**: setup dup's frozen objects, but callers
   may not expect the returned object to be a different instance.
8. **Pretty print misspelling**: the method is `prety_print` (one 't') in
   some places — check carefully.
