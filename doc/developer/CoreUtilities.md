# Core Utilities

The small modules everything else in the stack is built on:
`IndiferentHash`, `NamedArray`, the `Misc.format` family, `TmpFile` and
`Hook`. Each is tiny, each is load-bearing. Sources:
`lib/scout/indiferent_hash.rb` + `lib/scout/indiferent_hash/{options,serialize,case_insensitive}.rb`,
`lib/scout/named_array.rb`, `lib/scout/misc/format.rb`,
`lib/scout/tmpfile.rb`, `lib/scout/misc/hook.rb`.

## IndiferentHash

`IndiferentHash.setup(hash)` does not create a class; it extends a plain
`Hash` with the module, so an IndiferentHash IS an Array/Hash of its base
type and every `Hash` operation still works. Reads and writes are
indifferent between String and Symbol keys.

Verified by `tmp/rewrite_D/probe_06_indiferent_misc.rb`:

```ruby
h = IndiferentHash.setup({ 'a' => 1 })
h[:b] = 2
h[:a]      # => 1
h['b']     # => 2
h.keys     # => ["a", "b"]      (first-written form is kept)
```

- **`slice`** — `{'a'=>1,'b'=>2}.slice(:a)` => `{"a"=>1}`
- **`merge` keeps existing keys, and keeps the FIRST key's form**:
  `{'a'=>1,'b'=>2}.merge('a'=>9,'c'=>3).keys` => `["b","a","c"]`; with a
  duplicate `{'k1'=>1, :k1=>2}` both keys survive and `[:k1]` returns `2`.
- **`clean_version`** — a fresh copy without the module's bookkeeping:
  `{'a'=>1,'b'=>2}`.
- **`dig`** — module-level `IndiferentHash.dig(h, :x, :y)` works
  symbol-first on a String-keyed hash => `1`.
- `add_defaults(options, defaults)` only fills missing keys:
  `add_defaults({:a=>1}, {:b=>2})` => `{:a=>1, :b=>2}`.

### The destructive pair

`process_options(hash, *keys)` **destroys** the keys it extracts — it
`delete`s them (verified: `process_options(opts, :a, :b)` leaves
`{:extra=>3}`). `pull_keys(hash, :prefix)` returns the sub-hash under that
prefix key AND removes it from the original
(`pull_keys({persist: true, x: 1}, :persist)` => `{:persist=>true}`, hash
left with `{:x=>1}`).

### `string2hash` / `parse_options`

`string2hash(string, sep="#")` splits on `sep`, then per pair applies, in
order: bare key => `true`; `:sym` values; `/regex/`; quoted strings;
`Integer`; `Float`; `"true"`; else the raw String
(`lib/scout/indiferent_hash/options.rb:96-114`). Note `"false"` is *not*
in the coercion list — see the asymmetry below.

`parse_options(str)` scans `key=value` pairs on whitespace
(`/\w+=(\"[^\"]*\"|[^\s\"]+)/`), strips surrounding quotes, and splits a
value containing a comma into an Array. Its coercion ladder is shorter than
`string2hash`'s: `true`/`false` are **not** special-cased at all, so both
survive as Strings (verified `tmp/rewrite_D/probe_20_parse_options_false.rb`:
`parse_options('a=false')` => `{"a"=>"false"}`,
`parse_options('a=1,b=2')` => `{"a"=>["1", "b=2"]}` — the comma split eats
the second pair — and `parse_options('a="x y"')` => `{"a"=>"x y"}`).
`print_options(options)` is the inverse, re-quoting values with spaces.

**Known asymmetry (bug candidate).** In `string2hash`, the `== "false"`
branch (`options.rb:110`) is dead code for the plain case: `a=false` goes
through `options[key] = value` and the String survives. The only way the
branch is reached is when `false` is the *value* of a pair that the default
`#` separator has already split off — and the executed result is still
`"false"` in every probed form (`tmp/rewrite_D/probe_21_s2h_false_traced.rb`).
`parse_options` has no boolean branches at all. `Scout::Config.get`, by
contrast, turns a stored `'false'` into the boolean `false` (see
[Configuration.md](Configuration.md)). Verified by
`tmp/rewrite_D/probe_19_false_coercion.rb` and `probe_20_parse_options_false.rb`:

```text
string2hash('a=true')            => {"a"=>true}
string2hash('a=false')           => {"a"=>"false"}
string2hash('a=false#b=1')       => {"a"=>"false", "b"=>1}
parse_options('a=true')          => {"a"=>true}
parse_options('a=false')         => {"a"=>"false"}
Scout::Config.get('fc')          => false     (set from the String 'false')
```

So a boolean-looking option that arrives through a string carries no
guarantee of being a boolean: check the specific path, and treat values
coming out of `parse_options` as Strings unless you coerce them yourself.
(`string2hash` also expects `#`-separated pairs; `'a=false b=1'` is a
single pair because the separator never appears — the value is the literal
`"false b=1"`.)

### `serializable`

`IndiferentHash.serializable(obj)` (`serialize.rb`) returns a deep copy of
Hash/Array structures. Arrays longer than 100 are truncated: first 70 +
`'...'` + last 30 + the marker `"TRUNCATED only 100 out of N shown"`
(probe_06: 250-element array => 102 elements, marker last). Use it for
logging fingerprints, not for round-tripping data.

### CaseInsensitiveHash

`lib/scout/indiferent_hash/case_insensitive.rb` — **not auto-loaded**;
`require 'scout/indiferent_hash/case_insensitive'` first. Only `[]` and
`values_at` are overridden; writes are plain `Hash` writes. Reads are
downcase-mapped against the *first* case seen for each key, so a Symbol
key can never be found by a String lookup (Symbol has no meaningful
downcase mapping in `downcase_keys`). Verified by
`tmp/rewrite_D/probe_24_cihash_writes.rb`:

```text
ci = CaseInsensitiveHash.setup({"Key" => 1})
ci["Other"] = 5   keys => ["Key", "Other"]
ci["other"], ci["OTHER"]   => 5, 5          (case-insensitive read)
ci[:third]  = 7   keys => ["Key", "Other", :third]
ci["third"]     => nil                     (String lookup misses a Symbol key)
ci[:third]      => 7
```

Treat it as a read-side convenience for String-keyed hashes; it is not an
indifferent-access container.

## NamedArray

`require 'scout/named_array'` (also **not** auto-required by the gem root).
`NamedArray.setup(array, fields, key)` extends an ordinary Array — it is
the `Annotation` module applied to Arrays, **not** a String type, and it
does **not** extend `AnnotatedArray` (that is for annotated Strings; see
[AnnotationSystem.md](AnnotationSystem.md)).

```ruby
na = NamedArray.setup([1,2,3], [:first, :second, :third], 'mykey')
na.class                 # => Array
na.first                 # => 1   (Array#first shadows nothing here)
na[:first]               # => 1
na['first']              # => 1
na.second                # => 2   (method_missing field accessor)
na.respond_to?(:second)  # => false  (fields are not real methods)
na.zip([4,5,6])          # => [[1,4],[2,5],[3,6]]  (Array#zip wins)
na.count                 # => 3
```

So `count`/`first`/`last`/`zip` are Array's, and any field that happens to
be named like an Array method is unreachable through the accessor. The
`key` is exposed via `all_fields` (`[key, fields].compact.flatten`).

## Misc.format family

All from `lib/scout/misc/format.rb`, verified by probe_06/probe_15:

| call | result |
|---|---|
| `Misc.snake_case('FooBar')` | `"foo_bar"` |
| `Misc.camel_case('foo_bar')` | `"FooBar"` |
| `Misc.humanize('foo_bar')` | `"Foo bar"` |
| `Misc.human_number(1234567)` | `"1.2M"` |
| `Misc.format_paragraph(text, 30)` | re-wraps to the given width |
| `Misc.format_definition_list([[dt, dd]])` | aligned dt/dd block |

### `Misc.timespan` takes ONE unit per token

`timespan(str, default="s")` (`lib/scout/misc/format.rb:279`) supports the
unit tokens `s sec m min '' ' h d w mo y`, `HH:MM[:SS]` clock strings, and a
leading `-` for negatives. The parser is `str.scan(/(\d+)(\w*)/)` and `\w*`
is greedy, so **each number may be followed by only one unit token**.
`"1h30m"` is scanned as the single pair `["1", "h30m"]`; `"h30m"` is not in
the token table, so the product becomes `1 * nil` and raises
`TypeError: nil can't be coerced into Integer`. Verified by probe_06 and
`tmp/rewrite_D/probe_16_timespan_exact.rb`:

```text
Misc.timespan('1h')    => 3600
Misc.timespan('1d')    => 86400
Misc.timespan('2w')    => 1209600
Misc.timespan('3mo')   => 8035200
Misc.timespan('1y')    => 31536000
Misc.timespan('1:30')  => 90    (HH:MM clock form)
Misc.timespan('-1h')   => -3600
Misc.timespan('1h30m') => TypeError: nil can't be coerced into Integer
Misc.timespan('1x')    => TypeError: nil can't be coerced into Integer
Misc.timespan('2')     => 2   (bare number uses the default unit, seconds)
```

So: one number, one unit, per token; combine durations with `HH:MM:SS` or
add the seconds yourself.

## Misc.digest and `file_md5`

`Misc.digest(obj)` produces a 32-char MD5 hex (`Misc.digest('x')` =>
`"9dd4e461268c8034f5c8564e155c67a6"`). `Misc.file_md5(path)` hashes the
file **contents**; when the digest falls back to a plain `Misc.digest` on a
path string, it hashes the **path string**, not the content — a missing
`/nope/x` still yields a digest (`14470bb0...`) instead of raising
(probe_06). Check `File.exist?` yourself if that distinction matters.

## `Misc.insist`

See [ErrorHandling.md](ErrorHandling.md) for the retry protocol with
`TryAgain`/`StopInsist`/`Aborted`.

## Hook

`lib/scout/misc/hook.rb` defines a top-level `Hook` module — **not
auto-required** (verify with `defined?(Hook)` => nil after
`require 'scout-essentials'`; it becomes a constant only after
`require 'scout/misc/hook'`). It exposes `Hook.extended`, `Hook.apply` and
`hook_method` (probe_06). `Hook.apply(hook_class, base_class)` redefines the
methods the two classes share on `base_class`, aliasing the originals as
`orig_<name>` and dispatching first to the registered hooks, honouring an
optional `claim(*args)` predicate on each hook. It is the mechanism behind
tool registration in `CMD::TOOLS`-style setups.

## TmpFile

Root: `TmpFile.tmpdir` => `$HOME/tmp/scout/tmpfiles` (here
`/home/mvazque2/tmp/scout/tmpfiles` — a machine-specific example value),
overridable with `TmpFile.tmpdir=`;
`TmpFile.user_tmp('sub')` => `$HOME/tmp/scout/sub` (probe_05/probe_15).

### Naming conventions (`tmp_for_file`, `lib/scout/tmpfile.rb:98-118`)

| piece | meaning |
|---|---|
| `·` (U+00B7) | each `/` in the source path |
| `PREFIX:` | `:prefix` option |
| `[key]` | `:key` option |
| `&F[match=...]` | `:filters` option (the "other options" hash) |
| `:md5` tail | digest of the remaining options |
| `MAX_FILE_LENGTH = 150` | names longer than this are truncated |

Verified shapes (probe_05, re-run as probe_13 for gate 2; `...` is
`TmpFile.tmpdir`, here `~/tmp/scout/tmpfiles`):

```text
tmp_for_file('/a/b/c')                        => .../·a·b·c
tmp_for_file('/a/b/c', :prefix => 'P')        => .../P:·a·b·c
tmp_for_file('/a/b/c', :key => 'k')           => .../·a·b·c[k]
tmp_for_file('/a/b/c', {}, :filters => {:m=>1}) => .../·a·b·c&F[m=c4ca4238a0b923820dcc509a6f75849b]:4db87253e0818c624c185ac939aa99c1
tmp_for_file('/a/b/c', {}, :other => 2)       => .../·a·b·c:9e984fda99565456fdde6f77833b61b4
```

The `:filters` form embeds `Misc.digest(value)` (here the digest of `1`) in
the name and, because `other_options` is then non-empty, still gets the
`:md5` tail of the whole options hash (tmpfile.rb:112-115, 129).

**`nil` is not `#{}`**: `tmp_for_file('/a/b/c', nil, ...)` raises
`NoMethodError: super: no superclass method 'include?' for nil` from
`process_options` — pass an explicit empty Hash as the second argument when
you use `other_options` (probe_13).

### `with_file` leaks on raise

`TmpFile.with_file(content, erase, options)` writes the temp file, yields
it, then `Open.rm_rf tmpfile if Open.exist?(tmpfile) && erase` — there is
**no `ensure`**. If the block raises, the temp file stays on disk
(probe_05: file still present after `raise "boom"`; removed normally when
the block succeeds). Add your own `begin/ensure` around `with_file` when the
block can fail. See [ErrorHandling.md](ErrorHandling.md).

## Related pages

- [AnnotationSystem.md](AnnotationSystem.md) — the `Annotation` module
  `NamedArray` builds on.
- [ErrorHandling.md](ErrorHandling.md) — `Misc.insist`, cleanup limits.
- [PathResolution.md](PathResolution.md) — how `tmpfiles` fits into the
  `tmp` map.
