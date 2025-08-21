# IndiferentHash

IndiferentHash provides Hash utilities and a mixin that makes hash access indifferent to String vs Symbol keys. It also includes a set of helper utilities for parsing, merging and transforming option hashes used across the framework.

Two main pieces:
- IndiferentHash mixin (extend any Hash instance with IndiferentHash to get indifferent access behavior and extra hash helpers).
- CaseInsensitiveHash mixin (separate mixin to allow case-insensitive string keys).

---

## Quick usage

Make a Hash indifferent (string/symbol interchangeable):

```ruby
h = { a: 1, "b" => 2 }
IndiferentHash.setup(h)   # returns h extended with IndiferentHash

h[:a]      # => 1
h["a"]     # => 1
h[:b]      # => 2
h["b"]     # => 2
```

Make a Hash case-insensitive (string keys compared case-insensitively):

```ruby
h = { a: 1, "b" => 2 }
CaseInsensitiveHash.setup(h)

h[:a]      # => 1
h["A"]     # => 1
h[:A]      # => 1
h["B"]     # => 2
```

---

## IndiferentHash mixin (methods added to a Hash)

Call IndiferentHash.setup(hash) to extend a hash instance.

Behavior highlights:
- Access by Symbol or String: h[:k] and h["k"] resolve to the same entry when possible.
- Nested hashes returned from [] are automatically set up with IndiferentHash.
- Values are stored normally, but deletion and inclusion checks accept Symbol/String interchangeably.

Methods and behaviors:

- IndiferentHash.setup(hash)
  - Extends the given hash with IndiferentHash and returns it.

- merge(other)
  - Returns a new IndiferentHash with keys from self merged with other (other wins). The result is an IndiferentHash.

- deep_merge(other)
  - Recursively merges nested hashes: if both have same key and values are hash-like, merges them deeply (preserving IndiferentHash behavior on nested hashes).

- [](key)
  - Returns value for key. If not found directly, attempts the alternate form:
    - If given Symbol/Module, will try the String key.
    - If given String, will try the Symbol key.
  - If the value is itself a Hash, it will be extended with IndiferentHash before returning.
  - Note: behavior pays attention to hash default/default_proc. If a default exists and the key isn't explicitly present in keys, it returns the default without attempting alternative forms.

- []=(key, value)
  - Deletes any existing matching key (either symbol or string) before setting the new one. This avoids duplicate representations of the same logical key.

- values_at(*keys)
  - Returns an array of values for the provided keys (indifferent to symbol/string form).

- include?(key)
  - Returns true if either symbol or string form exists.

- delete(key)
  - Deletes by key; will try symbol and string form and return deleted value if found.

- clean_version
  - Produces a plain Ruby hash where keys are strings (stringified keys), preferring the first occurrence.

- slice(*keys)
  - Returns a new IndiferentHash containing only the requested keys. Accepts symbol or string forms; ensures both forms are considered.

- keys_to_sym! and keys_to_sym
  - keys_to_sym! converts string keys in-place to symbols (best-effort; rescue on any failed conversion).
  - keys_to_sym returns a new IndiferentHash with keys converted to symbols.

- prety_print
  - A convenience wrapper that calls Misc.format_definition_list(self, sep: "\n") (keeps existing behavior/name `prety_print` as in code).

- except(*list)
  - Returns a hash copy excluding provided keys. Accepts symbol/string forms; returns a result consistent with Hash#except but extended to be indifferent.

Notes:
- The implementation ensures nested hashes returned from [] or merges are set up with IndiferentHash automatically.
- Some method names are intentionally spelled as in the implementation (`prety_print`).

---

## CaseInsensitiveHash

A separate mixin to make key lookup case-insensitive (for string keys). Use CaseInsensitiveHash.setup(hash) to extend a hash.

Behavior:
- On lookup, it first tries the provided key directly. If no value, it converts the key to lowercase string and looks up a precomputed map (original_key_by_downcase) to find the actual stored key. This permits "A" and "a" to refer to the same entry.
- values_at returns values for provided keys using the case-insensitive lookup.

Example:

```ruby
h = { a: 1, "b" => 2 }
CaseInsensitiveHash.setup(h)

h["A"]  # => 1
h[:A]   # => 1
h["B"]  # => 2
```

---

## Options helpers (IndiferentHash::Options functions)

These utilities are useful for parsing and handling option hashes and strings.

- add_defaults(options, defaults = {})
  - Ensures options is an IndiferentHash, accepts defaults as Hash or string (string gets parsed). Adds defaults only for keys not present in options.
  - Returns the options (modified/extended).

- process_options(hash, *keys)
  - Sets up IndiferentHash on hash.
  - If the last argument is a Hash, it is used as defaults (added first).
  - If a single key passed, returns and removes that key from hash (prefers symbol then string).
  - If multiple keys passed, returns array of removed values for each key.
  - Example: IndiferentHash.process_options(h, :limit) or IndiferentHash.process_options(h, :a, :b, default: 1)

- pull_keys(hash, prefix)
  - Pulls keys with prefix_... from hash and returns a new IndiferentHash with the suffixes as keys.
  - Also consumes "#{prefix}_options" if present and merges into result.
  - Example: given { foo_bar: 1, "foo_x" => 2 }, pull_keys(h, :foo) => { bar: 1, x: 2 } (keys matched as string/symbol appropriately).

- zip2hash(list1, list2)
  - Zips two lists into a hash (keys from list1, values from list2) and sets it up as IndiferentHash.

- positional2hash(keys, *values)
  - Converts positional values into a hash keyed by keys.
  - Supports the common pattern where the last argument is a Hash of extra/defaults. In that case:
    - Combines given values into a hash, removes nil/empty values, adds defaults from the extras, and prunes keys not in the original keys set.
  - Example: IndiferentHash.positional2hash([:one,:two], 1, two: 2, extra: 4) => { one: 1, two: 2 }

- array2hash(array, default = nil)
  - Accepts an array of [key, value] pairs and builds an IndiferentHash.
  - If value is nil and default provided, uses a dup of default for that key.

- process_to_hash(list) { |list| ... }
  - Yields list to block, expects a result list; zips original list with returned list into an IndiferentHash.

- hash2string(hash)
  - Serializes a simple hash into a string representation (sorted by key). Only handles values of certain simple classes; others are omitted. Uses ":" prefix for symbol keys/values in output.
  - Output format is key=value pairs joined with "#".

- string2hash(string, sep = "#")
  - Parses the string produced by hash2string (or similar) and converts back into an IndiferentHash. Supports:
    - :symbol keys/values (leading ":")
    - quoted strings, integers, floats, booleans, regexps (/.../)
    - empty values treated as true
  - Example roundtrip: IndiferentHash.string2hash(IndiferentHash.hash2string(h)) == h (for supported types).

- parse_options(str)
  - Parses a shell-like option string of key=value pairs, supporting quoted values and comma-separated lists (preserving quoted items with spaces).
  - Returns an IndiferentHash.
  - Example: IndiferentHash.parse_options('blueberries=true title="This is a title" list=one,two,"and three"')

- print_options(options)
  - Serializes an options hash into a space-separated string of key=value pairs; array values become CSV (properly quoted if containing spaces).

---

## Examples (from tests and usage)

Indifferent access:

```ruby
h = { a: 1, "b" => 2 }
IndiferentHash.setup(h)
h[:a]  # => 1
h["a"] # => 1
h["b"] # => 2
h[:b]  # => 2
```

Deep merge:

```ruby
o = { h: { a: 1, b: 2 } }
n = { h: { c: 3 } }
IndiferentHash.setup(o)
o2 = o.deep_merge(n)
o2[:h]["a"]  # => 1
o2[:h]["c"]  # => 3
```

Options parsing:

```ruby
opts = IndiferentHash.parse_options('blueberries=true title="A title" list=one,two,"and three"')
opts["title"]                # => "A title"
opts["list"]                 # => ["one", "two", "and three"]
```

String <-> hash roundtrip:

```ruby
h = { a: 1, b: :sym, c: true }
s = IndiferentHash.hash2string(h)
h2 = IndiferentHash.string2hash(s)
# h2 should equal h for the supported/simple types
```

pull_keys example:

```ruby
h = { "foo_bar" => 1, :foo_baz => 2, "other" => 3 }
IndiferentHash.setup(h)
prefixed = IndiferentHash.pull_keys(h, :foo)
# prefixed => { "bar" => 1, :baz => 2 } (returned as IndiferentHash)
# and h no longer contains those entries
```

---

## Implementation notes / caveats

- IndiferentHash.setup extends a single hash instance (not the Hash class). Use it on any hash instance you want to treat indifferently.
- Nested hashes returned from [] or created by zip/positional helpers get extended automatically with IndiferentHash.
- The [] lookup has special handling with Hash defaults: if the hash has a default or default_proc
  and the requested key is not present in keys, it will return the default without trying the alternate symbol/string form.
- CaseInsensitiveHash is independent of IndiferentHash; you can mix both if needed, but their behaviors are separate.
- Some helper names are spelled as in the codebase (e.g., prety_print), used for compatibility.

This module covers common patterns required for flexible option handling in the framework: indifferent access, easy merging and defaulting, parsing/printing option strings, and extracting prefixed option subsets.