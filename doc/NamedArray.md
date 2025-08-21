# NamedArray

NamedArray is a small utility mixin built on top of the Annotation system that gives arrays named fields and name-based accessors. It lets you treat an Array like a record/tuple where elements can be accessed by name (symbol or string), supports fuzzy name matching, conversion to a hash (indifferent to string/symbol keys), and provides helpers for zipping/combining lists of named values.

NamedArray extends Annotation and declares two annotation attributes:
- fields — an ordered list of names for each position in the array
- key — an optional primary key field name

Since NamedArray extends Annotation, you can apply it to an array via NamedArray.setup(array, fields, key: ...), or by extending an instance.

Examples:
```ruby
a = NamedArray.setup([1,2], [:a, :b])
a[:a]    # => 1
a["b"]   # => 2
a.a      # => 1   # method_missing lookup
a.to_hash  # => IndiferentHash { a: 1, b: 2 }
```

## Core instance API

- fields, key
  - Provided by Annotation (accessors). fields is an Array of field names associated with array positions.

- all_fields
  - Returns [key, fields].compact.flatten — useful if you want the key included with other fields.

- [](name_or_index)
  - Accepts a field name (symbol or string) or numeric index. Name is resolved to a numeric position via identify_name; if unresolved returns nil.
  - Example: a[:a], a["a"], a[0]

- []=(name_or_index, value)
  - Sets element by name (resolved to a position) or index; returns nil if name not found.

- positions(fields)
  - Resolve one or many fields to their positions (delegates to NamedArray.identify_name).

- values_at(*positions)
  - Accepts named fields or positions; it will translate names to indices before calling Array#values_at.

- concat(other)
  - If other is a Hash: appends values of the hash in iteration order and adds the hash keys to this array's fields list.
    Example:
      a.concat({c: 3, d: 4})  # adds 3 and 4 to array and [:c, :d] to fields
  - If other is another NamedArray: standard concat and fields from other are appended.
  - Otherwise behaves like Array#concat.

- to_hash
  - Returns a hash mapping fields => value for each field position. The returned hash is extended with IndiferentHash (so both string and symbol lookups work).
  - Example: a.to_hash[:a] => 1

- prety_print
  - Convenience pretty-print wrapper: uses Misc.format_definition_list(self.to_hash, sep: "\n").

- method_missing(name, *args)
  - If name resolves to a field (via identify_name) returns self[name]; otherwise calls super. This gives quick accessors like a.foo

## Name resolution and matching

NamedArray provides flexible name resolution via:

- NamedArray.identify_name(names, selected, strict: false)
  - names: array of field names (usually the NamedArray#fields)
  - selected: value to resolve — may be nil, Range, Integer, Symbol, or String
  - Returns:
    - Integer index (position) for a single field selection
    - Range (unchanged) if a Range is passed
    - 0 for nil (treat nil as first field)
    - :key for Symbol :key (special sentinel)
    - nil if unresolved

Resolution rules:
- nil => 0
- Range => returned as-is
- Integer => returned as-is
- Symbol:
  - if :key => returns :key
  - otherwise finds first field whose to_s equals the symbol name
- String:
  - exact string match first
  - if string is numeric (^\d+$) it is treated as an index
  - unless strict: fuzzy match using NamedArray.field_match
    - field_match returns true if:
      - exact equality
      - one contains the other inside parentheses
      - one starts with the other followed by a space
  - returns the index found or nil if none

Instance helper identify_name(selected) delegates to the class method using this NamedArray's fields.

Note: identify_name accepts arrays for selected (returns an array of resolved positions), so values_at and other helpers can pass multiple names.

## Class-level helpers for lists

- NamedArray.field_match(field, name)
  - Helper used by identify_name for fuzzy matching of two strings (parentheses and prefix matching).

- NamedArray._zip_fields(array, max = nil)
  - Internal helper to zip together an array of lists, expanding single-element lists to match `max`.

- NamedArray.zip_fields(array)
  - Zips a list-of-lists into per-position combined lists. Optimized to slice large inputs when array length is huge.

  Example:
  ```ruby
  NamedArray.zip_fields([ %w(a b), %w(1 1) ]) # => [["a","1"], ["b","1"]]
  ```

- NamedArray.add_zipped(source, new)
  - Given two zipped-lists (source and new), concatenates each corresponding sub-array from `new` into `source` (skips nil entries).
  - Useful to merge results incrementally.

## Concatenation with Hash

Calling concat with a Hash behaves like:
```ruby
a = NamedArray.setup([1,2], [:a, :b])
a.concat({c: 3, d: 4})
# resulting array becomes [1,2,3,4] and fields => [:a, :b, :c, :d]
```

This is handy when building named rows incrementally from keyed data.

## Integration with Annotation

Because NamedArray extends Annotation:
- You can call NamedArray.setup(array, fields) to set the `@fields` annotation on the array and extend it with NamedArray behavior.
- NamedArray.setup delegates to the Annotation::AnnotationModule.setup implementation for assigning @fields/@key values to the array.

Example:
```ruby
a = NamedArray.setup([1,2], [:a, :b])
a.fields  # => [:a, :b]
```

## Examples (from tests)

Identify names:
```ruby
names = ["ValueA", "ValueB (Entity type)", "15"]
NamedArray.identify_name(names, "ValueA")    # => 0
NamedArray.identify_name(names, :key)        # => :key
NamedArray.identify_name(names, nil)         # => 0
NamedArray.identify_name(names, "ValueB")    # => 1  (fuzzy match)
NamedArray.identify_name(names, 1)           # => 1
```

Basic named array usage:
```ruby
a = NamedArray.setup([1,2], [:a, :b])
a[:a]      # => 1
a[:c]      # => nil
a.a        # => 1   (method_missing provides a getter)
a.to_hash  # => IndiferentHash { a: 1, b: 2 }
```

Zipping and adding zipped:
```ruby
NamedArray.zip_fields([ %w(a b), %w(1 1) ]) # => [["a","1"], ["b","1"]]

a = [%w(a b), %w(1 1)]
NamedArray.add_zipped(a, [%w(c), %w(1)])
NamedArray.add_zipped(a, [%w(d), %w(1)])
# a => [%w(a b c d), %w(1 1 1 1)]
```

## Notes & caveats

- Name matching is intentionally forgiving (parentheses and space-prefix checks). Use `identify_name(..., strict: true)` to force exact matches only.
- The `fields` annotation must correspond to element positions in the array. If fields and array lengths differ, name resolution may return nil or indices outside current array bounds.
- to_hash returns an IndiferentHash (so consumers can use either string or symbol keys).
- method_missing exposes field getters only; it does not create setters (use []= to assign by name).

NamedArray is small but convenient when treating Arrays as records/rows with named columns and needing flexible lookup and composition tools.