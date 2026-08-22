# Implementation inventory — CORE chunk (audit chunk 1)

Evidence-backed inventory of the core utility subsystems of `scout-essentials`
(v1.8.8). Every claim carries a `file:line` anchor. Disputed semantics were
settled with `ruby -Ilib` probes (see `research/behavior-probes.md`).

Entry point facts that frame everything else:

- `lib/scout-essentials.rb:1-10` — the only load entry. Requires in order:
  `scout/exceptions`, `scout/indiferent_hash`, `scout/tmpfile`, `scout/log`,
  `scout/path`, `scout/simple_opt`, `scout/resource`, `scout/resource/scout`,
  `scout/persist`, `scout/config`.
- `lib/scout.rb` **does not exist** (verified: `ls lib/scout.rb` → No such file).
  There is no `Scout` module file; `module Scout` appears only inside
  `lib/scout/config.rb:5` (as `module Scout::Config`, re-opening `Scout` created
  by `resource/scout.rb`) and `lib/scout/resource/scout.rb:1` (`module Scout;
  extend Resource; self.pkgdir = 'scout'`).
- Consequently: `NamedArray` and `Hook` are **not** loaded by
  `require 'scout-essentials'` (they need explicit
  `require 'scout/named_array'` / `'scout/misc/hook'`; probe P5).
  `Misc`, `TmpFile`, `Log`, `SOPT`, `IndiferentHash` **are** loaded — and so
  is `CMD` (transitively, via the `open`/`tmpfile` require chain; probe P5
  and follow-up `Object.const_defined?(:CMD) => true`).
- `lib/scout/tmpfile.rb:1` requires `open` (pulling `ConcurrentStream`, `Open`),
  `misc`, `log` — so `misc.rb` and `open.rb` are load-order ancestors of
  `scout-essentials`.

---

## 1. `lib/scout-essentials.rb` (10 lines)

Pure require cascade; no code. Ordering above.

What downstream consumes: the `require 'scout-essentials'` idiom itself, plus
the implicit guarantee that after it `Log`, `Misc`, `TmpFile`, `IndiferentHash`,
`SOPT`, `Path`, `Scout::Config`, `Persist`, `Scout` are defined.

Subtlety worth documenting: after a bare `require 'scout-essentials'` the
defined constants include `Misc`, `TmpFile`, `Log`, `SOPT`,
`IndiferentHash`, `Scout::Config` **and `CMD`** (CMD is pulled in
transitively, see probe P5), while **`NamedArray` and `Hook` are NOT defined**
(`tmpfile` does not require `named_array`; `misc.rb` does not require
`misc/hook`). Code assuming either is present must add
`require 'scout/named_array'` / `require 'scout/misc/hook'`.

---

## 2. `Scout::Config` — `lib/scout/config.rb` (184 lines)

### Structure
- `module Scout::Config` (`config.rb:5`) — class methods only (module with
  `self.` defs, no instances).
- State: `CACHE ||= IndiferentHash.setup({})` (`:7`) mapping
  `key_string => [[tokens_array, value], ...]`; `GOT_KEYS = []` (`:9`) audit
  trail of `[key, value, tokens]` tuples appended on every `get` (`:136`).
- Loads at require time: `self.load_config` (`:183`).

### Key public methods
- `add_entry(key, value, tokens)` (`:11-16`) — appends `[tokens, value]` under
  `key.to_s`; always ensures `key:<key>` is among tokens (`:13`).
- `load_file(file)` (`:18-26`) — line format `key value token token ...` split
  on whitespace; `#`-prefixed lines skipped (`:21`); **empty `key` lines are
  skipped** (`:24` — `if key`). Each line becomes one entry.
- `load_config` (`:28-32`) — `Path.setup("etc").config.find_all.reverse.each`,
  i.e. all `config` files in the `etc` search path, later files override by
  order of insertion into CACHE (not by load order semantics — ordering matters
  only via `unshift`/`concat` in `match`, see below).
- `set(values, *tokens)` (`:34-42`) — either a Hash of pairs, or
  `set(key, value, *tokens)` (non-Hash first arg → `{values => tokens.shift}`).
- `token_priority(token)` (`:44-68`) — token format `name[::N]`:
  explicit `::N` numeric priority wins (`:63-65`); else inferred by prefix:
  `workflow`→4, `task`→3, `file`→2, `line`→1, `key`→20, else 10 (`:49-62`).
  Returns `[token_name_without_priority, priority]`.
- `match(entries, give_token)` (`:70-87`) — builds `priorities[prio] => [values]`
  for entries whose tokens include `give_token`; **`unshift`s values**
  (`:83`), so later-loaded entries surface first at equal priority.
- `get(key, *tokens)` (`:90-150`) — resolution algorithm:
  1. pop trailing Hash options; `:default` and `:env` (`:91-95`);
  2. `:env` — first set var among comma-split names becomes `default`
     (`:97-104`);
  3. `tokens = ["key:" + key] if tokens.empty?` (`:106`) — **requires String
     key**; a Symbol key here raises `TypeError` (probe P3a: `no implicit
     conversion of Symbol into String`);
  4. caller inspection adds `file:<path>` and `line:<path>:<lineno>` tokens
     (`:109-120`), filtering frames matching rbbt-era paths
     (`rbbt/(resource.rb|workflow.rb)`, `rbbt/resource/path.rb`,
     `rbbt/util/misc.rb`, `accessor.rb`, `progress-monitor.rb`, `:110-115`) —
     **legacy rbbt regexes, not scout paths**; the caller token logic therefore
     rarely filters anything in scout code today;
  5. all matching tokens collapse into `priorities` (`:122-130`);
  6. `value = priorities.collect{|p| p }.sort_by{|p,v| p}.first.last.first`
     (`:132`) — **lowest priority number wins**, and among a priority bucket
     the **first** value wins (i.e. the last-loaded one, due to unshift);
  7. `'false'` → `false` (`:133`);
  8. `GOT_KEYS << [key, value, tokens]` (`:136`);
  9. value `env:VAR1,VAR2` → resolves to first set ENV var, else `nil`
     (`:138-144`); literal `'nil'` → `nil` (`:145`).
- `with_config` (`:152-164`) — snapshot `CACHE` (deep-dup of value arrays) and
  `GOT_KEYS`, restore in `ensure`.
- `process_config(config)` (`:166-180`) — CLI-oriented: if `config` is a
  filename that exists → `load_file`; elsif `Scout.etc.config_profile[config]`
  exists → load that; else parse `key value tok::prio ...` and `set`.

### Verified semantics (probes)
- P3: with entries `key:tk` ("plain"), `file:/some/file.rb` ("filetok"),
  `line:/some/file.rb:1` ("linetok"), `workflow::0` ("wftok") all present,
  `get("tk")` → `"wftok"` (probe P16 adds bare-vs-file). Note `workflow::0` (priority 0) beats
  `line:` (1) and `file:` (2); but the generic `key:` token has priority 20,
  i.e. the **lowest precedence** of all — the implicit key token only ever wins
  when nothing else matches.
- P3b: `get("k7", "key:k7")` with a `key:k7` entry → `"high"`; explicit tokens
  work. `get("k4", "key:k4")` on missing key → `nil` (no default). `get("k5")
  ` with `'false'` value → `false`. `get("k6")` with value `env:NOPE1,NOPE2`
  → `nil` (env fallback unset).
- P3b: `Path.setup("etc").config.find_all` → `[]` in a clean checkout (no
  `etc/config` in the search path), so `load_config` is a no-op here — all
  runtime config comes from `set`/`process_config`/ENV.

### Error handling / guarantees
- No exceptions raised on unknown keys (`get` returns default/nil).
- `get` with Symbol key and no tokens: TypeError from `:106` (documented
  footgun).
- `with_config` restores both caches even on raise.

### Concurrency
- No mutex anywhere in config.rb; CACHE is shared mutable state.

### External integrations / env vars
- Reads arbitrary ENV vars via `:env` option (`:98-103`) and `env:` value
  prefix (`:138-144`).

### Subtle points (docs plausibly wrong)
- The **priority scheme is inverted from intuition**: lower number = higher
  precedence, and the implicit `key:` token has the **worst** priority (20),
  so a config line with *any* explicit token overrides a bare `key value`
  line. `workflow` (4) beats `task` (3)? No — `task` (3) beats `workflow` (4);
  but explicit `::0` beats everything.
- Doc claims about "later files override earlier" are only half-true: within a
  priority bucket the *later inserted* (unshifted) value wins
  (`config.rb:83`), and `load_config` reads files in **reverse** find order
  (`:29`) so the last file in the path is loaded first — combined effect is
  that the *first* file in the path search order wins at equal priority.
- caller-based `file:`/`line:` tokens are derived from the call site of `get`,
  filtered by rbbt-legacy regexes (`:110-115`), so in scout code they point at
  the scout caller line — any doc describing per-workflow config file
  precedence needs this exact rule.

---

## 3. `IndiferentHash` — `lib/scout/indiferent_hash.rb` (177) + submodules

### Structure
- `module IndiferentHash` used as an **extension** (`self.setup(hash)` does
  `hash.extend IndiferentHash`, `indiferent_hash.rb:7-10`). Not a subclass of
  Hash — an extended plain Hash.
- Submodules: `indiferent_hash/options.rb` (module-level helpers),
  `case_insensitive.rb` (separate `CaseInsensitiveHash` extension),
  `serialize.rb` (`IndiferentHash.serializable`).

### Instance protocol (indiferent_hash.rb)
- `merge(other)` (`:12-19`) — returns new IndiferentHash, other's keys win.
- `deep_merge(other)` (`:21-32`) — recursive only when both sides are Hash and
  the existing value is already `IndiferentHash` (`:25`).
- `[]=(key,value)` (`:34-37`) — **deletes any dual-form key first** (`:35`), so
  writing `h[:a]=1` after `h["a"]=2` leaves a single entry.
- `[](key)` (`:43-61`) — tries the literal key, then the Symbol↔String swap
  (`:51-58`); nested Hash results get `IndiferentHash.setup` (`:47,59`). Guard
  `_default?` (`:39-41`) avoids returning a default-proc value that isn't a
  real key.
- `values_at(*keys)` (`:63-65`), `include?` (`:67-76`), `delete` (`:78-89`) —
  all dual-form aware.
- `clean_version` (`:91-97`) — plain Hash with String keys; **first** key form
  wins on collision (`:94`), so `{"a"=>1, :a=>2}.clean_version` keeps 1 (P1).
- `slice(*list)` (`:99-114`) — expands each Symbol/String into both forms,
  returns IndiferentHash.
- `keys_to_sym!` (`:116-125`) / `keys_to_sym` (`:127-138`).
- `pretty_print` (`:140-142`) → `Misc.format_definition_list(self, sep: "\n")`.
- `except(*list)` (`:144-160`) — dual-form removal.
- `dig(*keys)` (`:162-171`) — iteratively setups nested hashes.
- `self.dig(obj, *keys)` (`:173-176`).

### Module helpers (options.rb)
- `add_defaults(options, defaults = {})` (`:2-15`) — String inputs parsed via
  `string2hash`; does **not** overwrite existing keys (`:9`).
- `process_options(hash, *keys)` (`:17-28`) — **destructive**: pops the
  requested keys out of `hash` (P2/P6: after processing, `h` retains only the
  un-processed keys) and returns one value or an array. Trailing Hash = defaults.
- `pull_keys(hash, prefix)` (`:30-51`) — extracts `prefix_options` plus every
  `<prefix>_<rest>` key into a new IndiferentHash, deleting from source.
- `zip2hash(list1, list2)` (`:53-59`), `positional2hash(keys, *values)`
  (`:61-72`) — merges a trailing Hash of extras (defaults), drops nil/"" values
  and unknown keys (`:65-67`).
- `array2hash(array, default = nil)` (`:74-81`) — `[k,v]` pairs; `default.dup`
  fills nil values (raises if default lacks `dup`).
- `process_to_hash(list)` (`:83-86`) — `zip2hash(list, yield(list))`.
- `hash2string(hash)` (`:88-94`) — `k=v` joined with `#`; only
  Symbol/String/Float/Integer/Numeric/True/False/Module/Class/Object values kept
  (`:90`); Symbol keys get `:` prefix (`:91`). Note `Fixnum` in the whitelist
  is a Ruby<2.4 relic.
- `string2hash(string, sep="#")` (`:96-116`) — `#`-separated `k=v` pairs.
  Value coercion order (`:104-112`): empty→`true`; `:x`→Symbol; `/re/`→Regexp;
  `'x'`/`"x"`→unquoted String; `\d+`→Integer; `\d*\.\d+`→Float; `"true"`→`true`;
  `"false"`→**stays the String `"false"` (false-bug, see below)**; else String.
- `parse_options(str)` (`:118-154`) — whitespace-separated `k=v`, quoted values
  keep spaces, comma values split into Arrays preserving quotes (`:130-140`).
  Scalar coercions identical to `string2hash`, including the same false-bug.
  List-valued options (`a=1,2`) become Arrays of Strings and skip the scalar
  coercions entirely.
- `print_options(options)` (`:156-173`) — inverse-ish of parse_options:
  arrays become `k=a,b` with quoted elements containing spaces; scalar values
  quoted when empty or containing spaces.

### CaseInsensitiveHash (case_insensitive.rb)
- `self.setup(hash)` extend-based (`:3-5`); `downcase_keys` memoized map
  downcased→original (`:7-15`); `[](key, *rest)` falls back to the original
  key on miss (`:17-22`); `values_at` (`:24-28`). Read-only convenience — no
  `[]=`/`delete`/`include?` overrides.

### serialize.rb
- `self.serializable(obj)` (`:2-23`) — deep copy of Hashes, Arrays >100
  truncated to first 70 + last 30 + `['...', 'TRUNCATED only 100 out of N
  shown']` (`:13-18`).

### Probes
- P1: symbol/string interchange, slice, merge, clean_version first-wins, dig.
- P2: `string2hash` vs `parse_options` coercion table (P2's `g=false` line
  predates the false-bug investigation; P20 supersedes it).
- P2: `process_options` destructiveness (`h.keys` shrinks).

### Subtle points
- **`"false"` never coerces to `false`** in either `string2hash` or
  `parse_options` (`options.rb:110-111` and `:148-149`): the idiom
  `options[key] = false and next if value == "false"` assigns `false`, but the
  assignment itself evaluates to falsy `false`, so `and next` does not fire and
  the trailing `options[key] = value` overwrites it with the String `"false"`
  (probe P20; verified against the installed gem copy too). `"true"` coerces
  correctly only by luck. `Scout::Config.get` *does* coerce the String
  `'false'` (config.rb:133), so the gem's two boolean-from-string mechanisms
  disagree.
- `clean_version` keeps the **first** key encountered, not "string wins" —
  with `{:a=>1,"a"=>2}` the Symbol survives (P1: `["a","b"]` after clean on
  `{"a"=>1,:b=>2}` was a different case; the general rule is `each` order,
  `:91-96`).
- `process_options` **mutates** its argument; docs claiming a pure accessor
  would be wrong.
- (superseded by the bullet above — the two parsers actually agree, both fail
  to produce `false`; the real asymmetry is with `Scout::Config.get`.)
- `IndiferentHash` is an extension, so `IndiferentHash === h` is false for a
  plain Hash and `h.class` stays `Hash`.

---

## 4. `NamedArray` — `lib/scout/named_array.rb` (165 lines)

### Structure
- `module NamedArray; extend Annotation; annotation :fields, :key` (`:2-4`) —
  an Annotation module applied to Arrays. Requires `annotation` (`:1`).
- Loaded **only** via explicit `require 'scout/named_array'` (P5: NameError
  under bare `scout-essentials`).

### Class methods
- `field_match(field, name)` (`:10-20`) — tolerant equality: exact; `"(name)"`
  inside field or vice-versa; prefix followed by space. Non-Strings compared
  with `==`.
- `identify_name(names, selected, strict: false)` (`:22-57`) — maps a field
  selector to an index (or Range/Integer passthrough, `:27-30`); `Symbol :key`
  → `:key` (`:32`); `Symbol` otherwise recurses via `to_s` (`:32`);
  Strings: exact index (`:42-43`), numeric-string → Integer (`:44-46`),
  `strict` stops (`:47`), else `field_match` scan (`:48-49`), else nil. Note
  dead branch `when (names.nil? and String)` (`:33-38`): if `names` is nil
  and the selector is a String, the code calls
  `identify_field(key_field, fields, ...)` on **undefined locals**, so the
  branch would raise NameError if ever reached. Latent bug, noted for docs.
- `_zip_fields(array, max = nil)` (`:113-125`) / `zip_fields(array)`
  (`:127-144`, slices at 10000) / `add_zipped(source, new)` (`:146-152`).
  **Line `:119` is dead code** (P15/P15b): `v.length == 1 & max > 1` parses
  as `v.length == ((1 & max) > 1)` — `1 & max` is always 0/1 so
  `(1 & max) > 1` is always false, and singleton columns other than the
  first are NEVER repeated (observed: nil padding). Only the first column
  (`:126`, `first.length == 1 and max > 1`) can be broadcast — asymmetric
  behavior docs must not "fix" into symmetry.

### Instance protocol
- `all_fields` (`:6-8`), `identify_name(selected)` (`:59-61`),
  `positions(fields)` (`:63-71`), `[](key)`/`[]=(key,value)` by field name
  (`:73-83`, returning nil silently when the field is unknown),
  `concat(other)` handling Hash or NamedArray (`:86-99`), `to_hash`
  (`:101-107`, IndiferentHash), `values_at(*positions)` (`:109-111`),
  `method_missing` for field-name accessors (`:154-160`), `pretty_print`
  (`:162-164`).

### Probes (P15)
- `NamedArray.setup([1,2], [:a,:b])` → `.a`→1, `.b`→2, `.to_hash`→
  `{:a=>1,:b=>2}`; `identify_name([:a,:b], "b")`→1, `"zzz"`→nil;
  `positions("b")`→1, `[:a,:b]`→[0,1]; `field_match` tolerance confirmed
  (0 for exact, nil for unrelated).

### Subtle points
- `[]=` silently no-ops on unknown field (`:81-82`).
- Not auto-loaded (footgun for docs).
- `_zip_fields` boolean/bitwise expression at `:119`.

---

## 5. `Misc` — `lib/scout/misc.rb` (11 lines) + 10 submodules

`misc.rb:1-9` requires format, insist, digest, filesystem, monitor, system,
helper, matching, math — **note `hook.rb` is NOT required** by `misc.rb`
(verified: `misc.rb:1-9` list). `Hook` is a separate top-level module.

### 5.1 misc/format.rb (310 lines) — string/number formatting
- `COLOR_LIST` (`:2`), `colors_for(list)` (`:4-19`) assigns colors in order,
  memoizing per distinct element, returns `[colors, used]`.
- `format_seconds(time, extended = false)` (`:21-26`) → `HH:MM:SS` (+`.cs`).
- `CHAR_SENCONDS` (`:28`, typo for SECONDS; `"″"` unless `SCOUT_NOCOLOR`) and
  `format_seconds_short` (`:29-37`).
- `MAX_TTY_LINE_WIDTH = 120` (`:39`).
- `format_paragraph(text, size, indent, offset)` (`:40-73`) — wraps text at
  `size` (default `Log.tty_size || 120`, capped at 120), preserving
  paragraph-like separators (blank lines, markdown `*`/`-`/```/leading spaces)
  via the regex at `:48`; long words truncated with `...` (`:57`).
- `format_definition_list_item(dt, dd, indent, size, color: :yellow)`
  (`:75-100`) and `format_definition_list(defs, ...)` (`:102-111`) — used by
  `IndiferentHash#pretty_print`, `NamedArray#pretty_print`, SOPT docs.
- `camel_case` (`:113-118`, note the misleading `return` inside a guard:
  `return string if string !~ /_/ && string =~ /[A-Z]+.*/`), 
  `camel_case_lower` (`:120-124`), `snake_case` (`:126-134`).
  Probes: `snake_case("SomeCamelCase")`→"some_camel_case";
  `camel_case("some_snake_case")`→"SomeSnakeCase";
  `camel_case("ABCdef")`→"ABCdef" (acronym preserved);
  `camel_case_lower`→"someSnakeCase".
- `humanize(value, options = {})` (`:138-178`) — formats `:sentence` (default),
  `:allcaps`, `:class`, `:nocaps`; acronym-aware (Miguel Vazquez edit note at
  `:146`). Probes: "some_field_name"→"Some field name";
  `format: :class`→"SomeFieldName"; "ABC_acronym_x"→"ABC acronym x".
- `fixascii`/`to_utf8`/`fixutf8` (`:180-204`) — encoding repair;
  `fixutf8` has an operator-precedence-laden guard at `:194-195`.
- `humanize_list(list)` (`:206-213`).
- `human_number(n)` (`:215-237`) — K/M/B/T units. Probes: 0→"0", 950→"950",
  1234→"1.2K", -2500000→"-2.5M".
- `parse_sql_values(txt)` (`:239-277`) — minimal INSERT-values parser.
  Probe: `('a','b,c'),(1,2)` → `[["a","b,c"],["1","2"]]` (all values Strings).
- `timespan(str, default = "s")` (`:279-309`) — leading `-` negates
  (`:281`); `HH:MM:SS`/`MM:SS` handled (`:283-286`, note the
  `seconds, minutes, hours` naming of the reversed split — a 2-part
  `"01:02"` string is minutes:seconds); token table `:288-300` (`s,sec,m,min,
  ','',h,d,w,mo,y`); `tokens[nil]`/`tokens[""]` default (`:302-303`);
  aggregates `(\d+)(\w*)` pairs (`:305-307`).
- **Compound timespans and unknown units raise `TypeError`** (P7/P15,
  confirmed against the library itself):
  `Misc.timespan("1h30m")` and `Misc.timespan("1x")` both raise
  `TypeError: nil can't be coerced into Integer`, because the scan yields the
  unit string `"h30m"` (or `"x"`) which is absent from the token table, and
  `amount.to_i * nil` blows up. Working forms: `"10"`→10, `"10s"`→10,
  `"01:02:03"`→3723, `"01:02"`→62, `"1,30"`→31, `"1'30''"`→31,
  `"-10s"`→-10, `"1d"`→86400, `"1mo"`→2678400, `"1y"`→31536000.
  Docs claiming `"1h30m"`-style compound parsing or lenient unknown-unit
  handling are wrong.

### 5.2 misc/digest.rb (93 lines) — content digests
- `MAX_ARRAY_DIGEST_LENGTH = 100_000` (`:2`).
- `digest_str(obj)` (`:4-51`) — recursive stable string; Strings that look
  like existing files are digested as paths with a memo cache (`:10-14`,
  `@@digest_str_cache`); Integers/Symbols `to_s`; huge Arrays (>100k) sampled
  at positions 1,2,mid,len-2,len-1 (`:19-26`); Floats formatted by magnitude
  (`:32-40`); Procs → digest of `source_location` (`:45-46`); else `inspect`.
- `digest(obj)` (`:53-56`) — MD5 hex of `digest_str` (Strings used verbatim).
- `file_md5(file)` (`:58-66`) — `Digest::MD5.file`; on failure falls back to
  hashing the *path string* (`:63-65`) — intentional but surprising.
- `fast_file_md5(file, sample = 3_000_000)` (`:68-79`) — MD5 of
  `size:` + first/middle/last 3MB samples; note `f.seek(size - sample - 1)`
  (`:75`) can go negative for small files (seek to negative offset) — in
  practice guarded by callers comparing `File.size(file) > 10_000_000`
  (`:87`).
- `digest_file(file)` (`:81-92`) — honours a sibling `<file>.md5` file
  (`:84-86`); >10MB → fast_file_md5 else file_md5 (`:87-91`).

### 5.3 misc/filesystem.rb (86 lines)
- `in_dir(dir)` (`:2-11`) — mkdir_p + chdir with ensure-restore.
- `path_relative_to(basedir, path)` (`:13-24`).
- `tarize_cmd(path, dest)` (`:26-34`) — shells out to `tar cvfz` via CMD.
- `tarize(source_dir, archive_path)` (`:36-73`) — pure-Ruby tar.gz writer
  using `Gem::Package::TarWriter` + `Zlib::GzipWriter`.
- `untar(file, target)` (`:75-85`) — `tar xvfz` via CMD.

### 5.4 misc/helper.rb (78 lines) — array helpers
- `intersect_sorted_arrays(a1, a2)` (`:2-19`) — **destructive on inputs**
  (uses `shift`).
- `counts(array)` (`:21-29`) — Hash tally. Duplicated verbatim in math.rb:75-83.
- `chunk(array, size)` (`:34-49`), `divide(array, num)` (`:53-62`, round-robin
  distribution), `ordered_divide(array, num)` (`:66-76`, contiguous slices).
  Probes/test: `chunk(%w(1..9),2)[0]`==%w(1 2); `ordered_divide(...,2).length`==5.

### 5.5 misc/hook.rb (50 lines) — top-level `Hook`
- `Hook.extended(hook_class)` (`:2-4`), `Hook.apply(hook_class, base_class)`
  (`:6-43`) — wraps singleton and instance methods of `base_class` so each
  registered hook gets a chance (`claim` predicate opt-in), falling back to
  `orig_<method>`; `Hook.hook_method` (`:45-49`).
- Not required by `misc.rb`; loaded only when explicitly required
  (`test/scout/misc/test_hook.rb` does `require 'scout/util/misc'`-style load
  or direct).

### 5.6 misc/insist.rb (56 lines) — retry block
- `insist(times = 4, sleep = nil, msg = nil)` (`:2-55`):
  - `TryAgain` → sleep+retry unconditionally (no counter) (`:22-24`);
  - `StopInsist` → re-raise the wrapped exception (`:25-26`);
  - `Aborted`/`Interrupt` → warn and re-raise, no retry (`:27-33`);
  - other `Exception` → warn (unless `msg == false`), backoff using either a
    caller-supplied sleep, an Array of sleeps (`times` as Array, `:10-14`),
    or a synthesized ladder `[0, 0.001, 0.01, 0.1, 0.5]` (`:17`), retry while
    `try < times` (`:51-52`), else re-raise (`:53`).
  - `SCOUT_LOG_INSIST=true` triggers `Log.exception` on each failure (`:35`).

### 5.7 misc/matching.rb (47 lines)
- `_convert_match_condition(condition)` (`:2-11`) — `'true'`→true,
  `'false'`→false, `/re/`→Regexp, `<=x`/`>=x`/`<x`/`>x`→`[:cmp, op, x.to_f]`,
  `!x`→`[:invert, ...]`, else the raw String.
- `match_value(value, condition)` (`:13-42`) — nil/nil→true (`:16`), nil
  value→false (`:17`); Regexp; TrueClass/FalseClass conditions accept the
  class objects or the strings "true"/"false" (`:22-25`); String condition
  numeric-compares when value is Numeric (`:27`); Array conditions handle
  `:cmp`, `:invert`, and OR-of-conditions (`:30-38`); unknown → raise
  (`:39-41`).
- `tokenize(str)` (`:44-46`) — `"`/`'`/bare tokens.

### 5.8 misc/math.rb (121 lines)
- `log2`/`log10` with precomputed multipliers (`:3-11`), `max`/`min`
  nil-skipping (`:13-29`), `std_num_vector` (`:31-38`), `sum` (`:40-42`),
  `mean` (`:44-46`), `median` (`:48-52`), `variance` (sample, n-1, `:54-67`),
  `sd` (`:69-73`), `counts` (duplicate of helper.rb's, `:75-83`),
  `proportions(array)` (`:85-101`, with a singleton `to_s` override that
  prints a sorted tally), `zscore` (`:103-107`), `softmax` (`:109-120`).

### 5.9 misc/monitor.rb (67 lines)
- `pid_alive?(pid)` (`:2-5`), `benchmark(repeats, message)` (`:7-27`),
  `profile(options)` (`:29-45`, requires `ruby-prof` at call time),
  `exec_time(&block)` (`:47-56`), `wait_for_interrupt` (`:58-66`, sleeps until
  Interrupt).

### 5.10 misc/system.rb (118 lines)
- `add_libdir(dir)` (`:3-6`), `hostname` (`:8-12`, `ENV["HOSTNAME"]` or
  backticks), `children(ppid)` (`:14-19`, `sys/proctable`), `wait_child(pid)`
  (`:21-26`), `abort_child(pid, wait)` (`:28-35`, TERM),
  `env_add(var, value, sep = ":", prepend = true)` (`:37-49`, idempotent;
  test: appending `test_value1:test_value2`),
  `with_env_hash`/`with_env`/`with_envs` (`:51-82`, ENV snapshot/restore),
  `update_git(gem_name = 'scout-essentials')` (`:85-113`, git pull +
  submodule update + rake install via `CMD.cmd_log`), `processors`
  (`:115-117`, `Etc.nprocessors`).

### Env vars read by Misc files
`SCOUT_NOCOLOR` (format.rb:28), `HOSTNAME` (system.rb:10),
`SCOUT_LOG_INSIST` (insist.rb:35).

### Subtle points
- `Misc.counts` defined twice (helper.rb:21, math.rb:75) — identical.
- `intersect_sorted_arrays` mutates its arguments.
- `file_md5` fallback hashes the path string, not the content.
- `Hook` is top-level and not auto-required.
- `timespan` raises TypeError for unknown units *and* for compound strings
  like `"1h30m"` (nil multiplier, P7/P15) — it only accepts a single
  `(<digits>)(<unit>)` pair.

---

## 6. `TmpFile` — `lib/scout/tmpfile.rb` (131 lines)

### Structure / conventions
- `MAX_FILE_LENGTH = 150` (`:7`).
- `user_tmp(subdir = nil)` (`:9-15`) — **`ENV["HOME"]/tmp/scout[/<subdir>]`**
  (home-relative, not `/tmp`!). `tmpdir` defaults to
  `user_tmp('tmpfiles')` (`:21-23`), overridable via `TmpFile.tmpdir=`.
- `random_name(prefix = 'tmp-', max = 1_000_000_000)` (`:27-30`),
  `tmp_file(prefix, max, dir)` (`:33-37`, Path-aware).
- `with_file(content = nil, erase = true, options = {})` (`:39-75`) — flexible
  arg shifts (Hash-only call, Hash-as-second-arg); options `:prefix`,
  `:tmpdir`, `:max`, `:extension`; IO content streamed in 1024-byte chunks
  (`:57-65`); file removed in all cases after the block when `erase`
  (`:72`).
- `with_dir(erase = true, options = {})` (`:77-88`), `in_dir(*args)`
  (`:90-96`, wraps `Misc.in_dir`).
- `SLASH_REPLACE = '·'` (`:98`) — **MIDDLE DOT U+00B7**, not a hyphen.
- `tmp_for_file(file, tmp_options = {}, other_options = {})` (`:99-130`):
  - explicit `:file` in tmp_options short-circuits (`:100-101`);
  - base name = `prefix + ":" + file` (or bare file), `.gz`/`.bgz` stripped
    (`:103-107`), `[key]` appended for `:key` (`:109`);
  - `other_options[:filters]` adds `&F[match=<digest>]` segments (`:111-115`);
  - whitespace → `_`, `/` → `·` (`:120`);
  - names longer than `MAX_FILE_LENGTH + 10` are truncated at 150 with the
    MD5 of the tail appended (`:125`);
  - non-empty remaining `other_options` (minus `:unnamed`, `:122-123`) append
    `:<md5 of options>` (`:127`);
  - result is a `Path` inside `persistence_dir` (`:117-129`).

### Probes (P4)
- `user_tmp` → `/home/mvazque2/tmp/scout`; `user_tmp('foo')` →
  `.../tmp/scout/foo`; `tmpdir` → `.../tmp/scout/tmpfiles`.
- `tmp_file('pfx-')` → `.../tmpfiles/pfx-332333330` (random).
- `random_name` → `"tmp-57604039"`.
- `tmp_for_file("/a/b/c.tsv")` →
  `.../tmpfiles/·a·b·c.tsv` (slashes → middle dots).
- `tmp_for_file("/a/b/c.tsv", {}, {filters: {...}})` → 32-char md5 suffix
  (P4/P19).
- `tmp_for_file("/a/b/c.tsv", {prefix: "P", key: "K"}, {unnamed: 1})` →
  `.../tmpfiles/P:·a·b·c.tsv[K]` — note `:unnamed` excluded from the digest
  suffix, and with only `:unnamed` present no `:`-digest is appended.

### Conventions summary (doc-relevant)
- Temp root is `$HOME/tmp/scout`, subdir `tmpfiles`.
- Deterministic cache names use `·` for `/`, optional `PREFIX:` and `[key]`
  decorations, optional `&F[...]` filter markers, and a trailing
  `:md5` when extra options survive filtering.

### Error handling
`with_file`/`with_dir` attempt removal **only in the success path** — an
exception propagating out of the block skips cleanup (`:70-74`: no `ensure`
around the `yield`; verified by probe P12, which observed the temp file
surviving a raised block). Docs claiming "always cleaned up" would be wrong.

---

## 7. Exceptions — `lib/scout/exceptions.rb` (39 lines)

All top-level constants (no `Scout::` namespace). Verified hierarchy (probe
P9):

| Constant | Superclass | Notes |
|---|---|---|
| `ScoutDeprecated` | StandardError | `:1` |
| `ScoutException` | StandardError | `:2` |
| `FieldNotFoundError` | StandardError | `:3` |
| `TryAgain` | StandardError | `:5` |
| `StopInsist` | **Exception** | `:6-11`, wraps `#exception` accessor |
| `Aborted` | StandardError | `:13` |
| `ParameterException` | ScoutException | `:15` |
| `MissingParameterException` | ParameterException | `:16-20`, msg "Missing parameter 'x'" |
| `ProcessFailed` | StandardError | `:21-36`, `pid`,`msg` accessors; `new(nil,msg)` → "Failed to run msg" |
| `ConcurrentStreamProcessFailed` | ProcessFailed | `:37-43`, `#concurrent_stream` = filename if available |
| `OpenURLError` | StandardError | `:45` |
| `DontClose` | **Exception** | `:47-53`, `#payload` |
| `DontPersist` | **Exception** | `:55` |
| `KeepLocked` | DontPersist | `:56-61`, `#payload` |
| `KeepBar` | **Exception** | `:63-68`, `#payload` |
| `LockInterrupted` | TryAgain | `:70` |
| `ClosedStream` | StandardError | `:72` |
| `ResourceNotFound` | ScoutException | `:74` |
| `CMD::Timeout` | ProcessFailed | cmd.rb:22-29 (see §11) |

Probes: `ProcessFailed.new(123,"msg").message` → "Process 123 failed - msg";
`ProcessFailed.new(nil,"cmd").message` → "Failed to run cmd";
`StopInsist.new(ArgumentError.new("x")).exception` → the ArgumentError.

Key design fact: several control-flow signals (`StopInsist`, `DontClose`,
`DontPersist`, `KeepLocked`, `KeepBar`) derive from **Exception, not
StandardError**, so a blanket `rescue => e` (which catches StandardError)
will *not* intercept them. This is deliberate and a classic doc-trap.

`ScoutDeprecated` and `FieldNotFoundError` appear unused within this chunk
(search of lib/ found `module Scout` only in config.rb / resource; no other
references inspected here) — flag for the doc-writer to verify usage in
downstream repos.

---

## 8. `Log` — `lib/scout/log.rb` (453) + `log/{color,color_class,fingerprint,trap}.rb`

### 8.1 log.rb core
- Severity constants and names (`:14-20`): `DEBUG LOW MEDIUM HIGH INFO WARN
  ERROR NONE` = 0..7. `SEVERITY_NAMES` frozen via `||=`.
- `default_severity` (`:21-33`) — reads `$HOME/.scout/etc/log_severity`, else
  `INFO` (4). Memoized in `@@default_severity`.
- ENV `SCOUT_LOG` maps names to severities; unset or unrecognized →
  default_severity (`:35-54`).
- `tty_size` (`:56-72`) — `IO.console.winsize.last`, fallback `tput cols`,
  fallback `ENV["TTY_SIZE"]` or 80; wrapped in `ignore_stderr`; memoized.
- `last_caller(stack)` (`:75-83`) — first frame not from `scout/log.rb`.
- `get_level(level)` (`:85-98`) — Numeric → int, String/Symbol → const, else
  0; on bad name calls `Log.exception` (which returns nil → `|| 0`).
- `with_severity(level)` (`:100-108`).
- `logfile(file=nil)` (`:110-124`) — nil resets, String opens append+sync,
  IO accepted, else raise. Note `Log.logfile` with no args *resets* rather
  than reads — trap.rb:7 relies on this returning the old value? No: `:7`
  calls `Log.logfile` (no args) then restores with `Log.logfile = old_logfile`
  via the attr_writer — actually `trap.rb:7,36` reads then re-assigns; the
  attr_writer is declared at `:11` (`attr_writer :tty_size, :logfile`).
- `up_lines/down_lines/return_line/clear_line` (`:125-139`) — ANSI cursor
  movement, all no-ops under `nocolor`.
- `MUTEX`-synchronized `log_write`/`log_puts` (`:141-166`) — write to
  `@@logfile` if set else STDERR; IOError swallowed.
- `logn(message, severity = MEDIUM)` (`:169-190`) — prefix
  `MM/DD/YY-HH:MM:SS.mmm[SEVERITY]`; `[pid]` included when
  `SCOUT_DEBUG_PID=true` (`:178-182`); messages at severity >= INFO are
  highlighted (`:183`); updates `Log::LAST` to "log" (`:188`) — the shared
  string used for interleaving control with progress bars.
- `log(message, severity = MEDIUM, &block)` (`:192-198`) — appends "\n",
  lazy block evaluation.
- `log_obj_inspect` / `log_obj_fingerprint` (`:200-224`).
- Severity helpers `debug/low/medium/high/info/warn/error` (`:226-252`).
- `exception(e)` (`:254-268`) — messages containing "NOLOG" are dropped
  (`:255`); "NOSTACK" suppresses backtrace (`:260`); default prints reversed
  (innermost-first) backtrace unless `SCOUT_ORIGINAL_STACK=true` (`:261-267`).
- `deprecated(m)` (`:270-274`), `color_stack` (`:276-288`, colorizes
  workflow/scout-/rbbt- frames), `tsv(tsv, example)` (`:290-316`),
  `stack(stack)` (`:318-330`), `count_stack`/`with_stack_counts`
  (`:332-355`).
- Kernel-level debug helpers defined at top level (`:358-451`): `ppp`, `fff`,
  `ddd/lll/mmm/iii/wwww/eee` (inspect at each severity), `ddf/llf/mmf/iif/
  wwwf/eef` (fingerprint variants), `sss(level,&block)` (severity switch),
  `ccc(obj,&block)` (conditional on `$scout_debug_log`).

### 8.2 log/color.rb (228 lines)
- `module Colorize` (`:6-128`): `colors` (name→hex IndiferentHash, `:11-19`),
  `diverging_colors` (`:25-40`, 12 hex values), `from_name(color)`
  (`:42-62`, hex passthrough, name lookup, special white/black/green/red/
  yellow/blue remaps), `continuous(array, start, eend, percent)`
  (`:64-80`), `gradient`/`rank_gradient` (`:82-94`), `distinct(array)`
  (`:97-112`, cycles diverging colors darkened by 0.3/times), `tsv(tsv,
  options)` (`:114-127`).
- `module Log` extends `Term::ANSIColor` (`:130-131`); `nocolor` accessor
  initialized from `ENV["SCOUT_NOCOLOR"] == 'true'` (`:137`).
- `WHITE, DARK, GREEN, YELLOW, RED = Color::SOLARIZED.values_at :base0,
  :base00, :green, :yellow, :magenta` (`:139`) — note GREEN maps to
  SOLARIZED[:green] but YELLOW maps to :magenta and RED to :magenta too
  (last assignment wins for the tuple order base0, base00, green, yellow,
  magenta → WHITE, DARK, GREEN, YELLOW, RED). Actually `values_at` returns 5
  values; YELLOW←:yellow, RED←:magenta per the source order `:base0, :base00,
  :green, :yellow, :magenta`.
- `SEVERITY_COLOR` (`:141`) = `[reset, cyan, green, magenta, blue, yellow,
  red]` indexed by severity int.
- `CONCEPT_COLORS` (`:142-162`) — named concepts (title, path, value, error,
  done, started, ...).
- `HIGHLIGHT = "\033[1m"` (`:163`).
- `uncolor(str)` (`:165-167`), `reset_color` (`:169-171`).
- `color(color, str = nil, reset = false)` (`:173-216`) — returns plain dup
  under nocolor; special-cases `:integer`/`:float` (sign/magnitude coloring,
  `:176-184`) and `:status` (`:186-201`); Integer color indexes
  SEVERITY_COLOR; concept names resolve via CONCEPT_COLORS; other Symbols via
  `Term::ANSIColor`; nil str → just the color string.
- `highlight(str = nil)` (`:218-226`).

### 8.3 log/color_class.rb (269 lines)
- Vendored `class Color` (McClain Looney, 2007, MIT) with `SOLARIZED` palette
  (`:33-52`), rgba accessors (`:90-93`), `Color.parse` (`:96`),
  `lighten/darken/blend` (`:161-234`), hex conversion helpers, and a
  top-level `rgb(*args)` convenience (`:265`).

### 8.4 log/fingerprint.rb (82 lines)
- `FP_MAX_STRING = 150`, `FP_MAX_ARRAY = 20`, `FP_MAX_HASH = 10` (`:3-5`).
- `truncate_string(string, max)` (`:7-16`) — keeps head/tail around
  `<...length - md5[0..4]...>`.
- `fingerprint(obj)` (`:18-81`) — dispatches to `obj.fingerprint` when
  available (`:19`); nil/true/false/Symbol; Strings quoted with `'` and
  newlines escaped (`:30-32`); ConcurrentStream (`:33-36`); IO/File
  (`:37-40`); Arrays truncated to first/2nd/mid/last-2/last with length
  prefix (`:41-46`); Hashes >10 entries collapse to `H:{keys;values}`
  (`:47-61`); Floats by magnitude — `>10`→`%.1f`, `>1`→`%.3f`, else
  `%.6f` (`:62-69`); Thread → `thread["name"]`; Set → array; else `to_s`.
- Probes (P8): `Log.fingerprint("a"*250)` → `'aaa...<...250 -
  63c7c...>...aaa'`; `[1,2]`→`"[1, 2]"`; `{:a=>1}`→`"{:a=>1}"`;
  `3.5`→`"3.500"`; `100.0`→`"100.0"`; `2.5`→`"2.500"`; `0.000123`→
  `"0.000123"`; nil/true/:sym as expected.

### 8.5 log/trap.rb (107 lines)
- `trap_std(msg = "STDOUT", msge = "STDERR", severity = 0, severity_err =
  nil)` (`:2-38`) — replaces STDOUT/STDERR with pipes, spawns two reader
  threads that `Log.logn` each line, redirects Log's own output to the saved
  STDERR dup, restores in ensure and joins threads.
- `trap_stderr(msg = "STDERR", severity = 0)` (`:40-62`).
- `_ignore_stderr`/`ignore_stderr` (`:64-84`) and
  `_ignore_stdout`/`ignore_stdout` (`:86-106`) — reopen to /dev/null with
  restore; fall back to plain yield if /dev/null is missing.

### Env vars read
`HOME` (log.rb:23), `SCOUT_LOG` (:35), `TTY_SIZE` (:64,66), `SCOUT_DEBUG_PID`
(:178), `SCOUT_ORIGINAL_STACK` (:261,319), `SCOUT_NOCOLOR` (color.rb:137).

### Subtle points
- `Log.logfile` with no argument **resets** the logfile (log.rb:111-113); it
  is not a reader. `trap.rb:7,43` therefore capture/restore semantics rely on
  the writer (`Log.logfile = ...`).
- Default severity is INFO (4): DEBUG/LOW/MEDIUM/HIGH messages are **not**
  printed by default (P11).
- The reversed-backtrace default in `Log.exception` and `Log.stack`.
- `Log::LAST` is a single shared mutable String used as a protocol flag
  between `logn` and progress-bar printing.

---

## 9. `Log::ProgressBar` — `log/progress.rb` (106) + `progress/{util,report}.rb`

### 9.1 progress.rb
- `Log.no_bar=`/`no_bar` (`:5-12`) — class var plus
  `ENV["SCOUT_NO_PROGRESS"] == "true"`.
- `ProgressBar` (`:14-105`): class attrs `default_file`, `default_severity`
  (`:16-19`); instance attrs `max ticks frequency depth desc file bytes
  process callback severity` (`:21`).
- `initialize(max = nil, options = {})` (`:23-43`) — options pulled with
  `IndiferentHash.process_options` (destructive), defaults
  `:depth => 0, :frequency => 2, :severity => default_severity`; `max = nil`
  when `TrueClass === max` (`:28`); desc newlines stripped (`:38`).
- `percent` (`:45-49`) — 0 when no ticks, **100 when max == 0** (`:47`).
- `init` (`:55-62`), `tick(step = 1)` (`:64-86`) — no-op under `no_bar`;
  reports when `diff >= frequency` or when the percent advanced and
  `diff > 0.3` (`:77,85`).
- `pos(pos)` (`:88-91`), `process(elem)` (`:93-104`) — the `process` callback
  may return false (ignore), true (tick), Integer (pos) or Float (fraction
  of max).

### 9.2 progress/util.rb (173 lines)
- `BAR_MUTEX`, `BARS`, `REMOVE`, `SILENCED` (`:4-7`).
- `add_offset`/`remove_offset`/`offset` (`:9-28`) — nesting offset for bars
  created by threads.
- `new_bar(max, options = {})` (`:30-40`) — Hash-only call supported
  (`:31-32`); `cleanup_bars` first; depth default = `BARS.length + offset`.
- `cleanup_bars` (`:42-63`), `remove_bar(bar, error = false)` (`:65-79`,
  calls `bar.error`/`bar.done`), `remove(error)` instance wrapper (`:81-83`).
- `with_bar(max = nil, options = {})` (`:85-99`) — honors `options[:bar]`;
  rescues `KeepBar` to keep the bar, any other exception marks error and
  re-raises.
- `guess_obj_max(obj)` (`:101-137`) — `wc -l` via CMD for Step paths and
  files (nil for gzip/bgzip/remote), `length`/`size` for TSV/Array/Hash.
- `get_obj_bar(obj, bar = nil)` (`:139-165`) — String→desc, true→auto max,
  Numeric→explicit max, Hash→options with `:max`, ProgressBar→reused (max
  filled in), Step→desc+file.
- `with_obj_bar(obj, bar = true)` (`:167-170`).

### 9.3 progress/report.rb (244 lines)
- `print(io, str)` (`:4-9`) — gated by bar severity vs `Log.severity` and
  `Log.no_bar`; writes via `Log.log_write`; sets `Log::LAST` = "progress".
- `thr_msg` (`:12-85`) — throughput estimate from a bounded history window
  (max 30 samples, growth heuristics `:18-35`); mean/mean_max tracked
  (`:41-53`); formats "N per sec." or "X secs each".
- `eta_msg` (`:88-117`) — 10-dot indicator, percent, `HH:MM:SS` ETA and used
  time, ticks of max, bytes/items.
- `report_msg` (`:119-136`), `load(info)` (`:138-159`), `save` (`:161-166`,
  YAML to `file`), `report(io = STDERR)` (`:168-197`) — redraws the stack of
  active bars using cursor up/down lines, appends itself to BARS, saves to
  file.
- `done(io = STDERR)` (`:199-218`) — prints summary, removes the YAML file,
  invokes `callback`.
- `error(io = STDERR)` (`:220-242`) — same but red, and callback failures are
  swallowed with a debug log.

### Concurrency
Single `BAR_MUTEX` guards BARS/REMOVE/SILENCED; per-bar state (`ticks`,
history) is **not** synchronized — `tick` from multiple threads races by
design. `with_bar` handles KeepBar.

### Env vars
`SCOUT_NO_PROGRESS` (progress.rb:11).

### Subtle points
- Bars persist state to YAML in `file` (progress report.rb:161-166) and are
  removed on done/error — a doc claiming progress state is ephemeral would be
  wrong for filed bars.
- `percent` returns 100 when `max == 0` regardless of ticks.
- `Log.no_bar` short-circuits `tick` entirely (no bookkeeping at all).

---

## 10. `SOPT` — `lib/scout/simple_opt.rb` (5 lines) + 5 submodules

### 10.1 accessor.rb (54 lines)
- Module-level state: `all`, `shortcuts`, `inputs`, `input_shortcuts`,
  `input_types`, `input_descriptions`, `input_defaults` (`:6-32`), writers
  (`:3`), `reset` (`:34-37`), `delete_inputs(inputs)` (`:39-48`),
  `usage` (`:50-53`, prints doc and `exit 0`).

### 10.2 parse.rb (69 lines)
- `fix_shortcut(short, long)` (`:2-35`) — collision resolution: keep the
  requested short unless taken (`:3`); if the long name already owns a
  shortcut, reuse it (`:5-6`); else derive from initials (`:13-16`) or digit
  (`:17-20`), then extend letter by letter skipping `.-_` (`:24-30`); returns
  nil when unresolvable.
- `register(short, long, asterisk, description)` (`:37-46`) — the presence of
  an asterisk means `:string`, otherwise `:boolean` (`:45`).
- `parse(opt_str)` (`:48-68`) — splits on newlines **or colons** (`:51-55`);
  each entry `"-s--long[*] description"` parsed with the regex at `:61`.
  Returns the list of long names.

### 10.3 get.rb (59 lines)
- `GOT_OPTIONS` module constant IndiferentHash (`:2`).
- `consume(args = ARGV)` (`:6-47`) — walks args; stops at `--` (`:11`);
  matches `--?(key)(=value)?`; unknown options are **skipped in place**
  (`:18-20`); recognized ones are deleted from the array (`:22`);
  `:string` inputs take the next arg as value (`:29-31`); booleans accept
  `=false`/`F`/`FALSE`/`no` (with a warning when passed as a separate token,
  `:33-36`) and otherwise evaluate true (`:37`); result keys are symbolized
  with `keys_to_sym!` (`:42`) and merged into `GOT_OPTIONS` (`:44`).
- `get(opt_str)` (`:49-52`) = parse + consume(ARGV).
- `require(options, *parameters)` (`:54-58`) — raises `ParameterException`
  for nil values (note: a `false` value passes).

### 10.4 doc.rb (126 lines)
- `command` (`:8-10`, `File.basename($0)`), `summary`, `synopsys`
  (deliberate misspelling of synopsis, `:16-23`), `description`.
- `input_format(name, type, default, short)` (`:29-47`) — renders
  `-s,--name` plus type-specific suffixes (`[=false]`, `=<file|->` for
  :tsv/:text, `=<list|file|->` for :array, `=<type>` otherwise) and
  `(default: ...)`.
- `input_array_doc(input_array)` (`:49-70`), `input_doc(...)` (`:72-101`)
  both auto-register options via `register`.
- `doc` (`:104-125`) — man-page-ish rendering with SYNOPSYS/DESCRIPTION/
  OPTIONS sections.

### 10.5 setup.rb (26 lines)
- `setup(str)` (`:3-25`) — splits the doc string on blank lines; first part
  = summary (unless it starts with `$-`), next `$`-prefixed part = synopsys
  (`$ ` prefix stripped, `:17`), following non-`-` parts = description, the
  rest of `-` lines = options; then `SOPT.parse` and `SOPT.consume`.

### Probes (P10)
- `SOPT.parse("-f--first* first arg:-f--fun")` → inputs `["first","fun"]`,
  shortcuts `{"f"=>"first","fu"=>"fun"}` (note `f` collision resolved to
  `fu`), types `{"first"=>:string,"fun"=>:boolean}`, descriptions
  `{"first"=>"first arg","fun"=>""}`.
- `SOPT.consume(["-f","myfile","--fun"])` → `{:first=>"myfile",
  :fun=>true}`; consuming again with extra unknown options
  (`-x --other val`) leaves them in the args and merges
  `{:flag=>true,:other=>"val"}` when registered.
- `SOPT.consume` stops at `--` and leaves `["--","positional"]` untouched
  (P10).
- `fix_shortcut("f","fun")` → "fu".
- `parse` with `:` vs `\n` separators both work (P10: newline-separated
  entries parsed identically).

### Subtle points
- Boolean false values are recognized only via `=F`/`=false`/`=FALSE`/`=no`
  (get.rb:37); a *separate* following token from that same set is consumed
  with a warning (get.rb:33-36) — but note the truthiness shortcut means
  `--flag anything` (a non-false next token) is NOT consumed, so a stray
  positional after a boolean flag silently stays in args.
- `SOPT.require` treats `false` as present.
- `synopsys` is the actual method name (misspelled) — docs must use it.
- `consume` mutates the passed array (deletes recognized args).

---

## 11. `CMD` — `lib/scout/cmd.rb` (666 lines)

### Structure
- `require`s: indiferent_hash, concurrent_stream, log, exceptions,
  open/stream, stringio, open3, fileutils (`:1-8`).
- `TIMEOUT_KILL_GRACE = 1.0` (`:14`).
- `CMD::Timeout < ProcessFailed` (`:22-29`) — carries `command`, `timeout`;
  message "command 'X' exceeded timeout of N seconds".
- `TOOLS` IndiferentHash (`:31`).

### Tool management
- `tool(tool, claim = nil, test = nil, cmd = nil, &block)` (`:32-34`) —
  registers `[claim, test, block, cmd]`.
- `conda(tool, env, channel = 'bioconda')` (`:36-42`).
- `get_tool(tool)` (`:45-89`) — if a test or `command -v` fails, installs via
  `claim.produce`, a block returning a Hash (→ `Resource.install`), then
  probes `--version`/`-version`/`--help`/no-flag to cache a version string in
  `@@init_cmd_tool`.
- `scan_version_text(text, cmd)` (`:91-109`) — several regex heuristics for
  version strings.
- `versions` (`:110-113`).
- `bash(cmd)` (`:115-118`) — wraps in `bash -l` heredoc with `:autojoin`.

### Option processing
- `process_cmd_options(options = {})` (`:120-146`) — validates option keys
  against `^[a-z_0-9\-=.]+$/i` (raises otherwise, `:125`), escapes single
  quotes in values (`:127`), `:add_option_dashes` prefixes `--`, booleans
  render as bare flags, nil/false are dropped, `x=` keys render `x='value'`.
  Probe: `{"o1"=>"v1",:o2=>true,:o3=>false,"o4="=>"v"}` →
  `"o1 'v1' o2 o4='v'"`; with dashes → `"--a '1' --long_opt 'x'"`. A key with
  an apostrophe raises RuntimeError.
- `process_cmd_options_array(options)` (`:151-176`) — same semantics
  returning an argv array (no quoting), used for the no-shell array mode.

### `cmd(tool, cmd = nil, options = {}, &block)` (`:178-611`)
- Normalizes the `(Hash)` second-arg form (`:179`).
- Defaults `:stderr => Log::DEBUG` (`:181`); pops `:in :stderr :sudo :post
  :pipe :log :no_fail/:nofail :no_wait :xvfb :progress_bar :save_stderr
  :autojoin :timeout :dont_close_in` (`:182-222`).
- `:save_stderr` accepts true (accumulate in `out.std_err`), a path
  (String/Pathname/Path — opened 'w', mkdir_p of dirname, closed by CMD) or
  any `write`/`<<` object (never closed) (`:195-216`).
- `array_mode = Array === tool` (`:226`) — argv execution via
  `Open3.popen3(ENV, *cmd_array)` (`:288-293`), no shell; otherwise a
  single shell string via `get_tool` resolution and `process_cmd_options`
  (`:249-284`). `'{opt}'` placeholder substitution (`:275-279`).
- `:xvfb` wraps with `xvfb-run` (`:232-237, 262-268`).
- `:sudo` prefixes sudo (`:245, 281-283`).
- Spawn failure → warn, close any opened stderr file, `raise ProcessFailed,
  nil, cmd unless no_fail` (or `return`) (`:294-301`).
- `:timeout` (Numeric > 0) → watchdog thread (`:310-408`): waits
  `wait_thr.join(timeout)`, on expiry sets `timed_out`, `Log.low`, then for
  pipe mode `sout.abort(timeout_exception)` + reap, else
  `caller_thread.raise`; reaping escalates INT → KILL after
  `TIMEOUT_KILL_GRACE` and always waits the pid (`:341-370`). Watchdog is
  not registered in `sout.threads`.
- stdin handling thread when `:in` responds to `read` (`:410-440`), else
  `sin.close`.
- **pipe mode** (`:444-497`): `ConcurrentStream.setup sout` with
  `:pids/:autojoin/:no_fail`; `:post` becomes `sout.callback`; an err thread
  feeds `bar.process(line)` (progress), `sout.log` (last line),
  `sout.std_err` accumulation, the save_stderr destination, and `Log.log` at
  the configured severity; threads `[in_thread, err_thread, wait_thr]`
  attached; returns the stream.
- **non-pipe mode** (`:498-610`): reads stdout into a StringIO, waits the
  status, joins the watchdog, raises CMD::Timeout if timed out, annotates the
  output with `exit_status`, fills `std_err`, writes the accumulated stderr
  to the destination, raises `ProcessFailed` (message includes the captured
  stderr) on non-success unless `no_fail`, else logs stderr at the given
  severity; Timeout path aborts the internal stream and re-raises; ensure
  closes the destination when CMD owns it and runs `post`.

### Convenience wrappers
- `cmd_pid(*args)` (`:613-659`) — forces `:pipe`, streams chars to STDERR
  honouring a log level, feeds `progress_bar`, joins and removes the bar.
- `cmd_log(*args)` (`:661-664`) — `cmd_pid` + nil.

### External integrations
`Open3.popen3`, `xvfb-run`, `sudo`, `tar` (from misc), `bash -l`, `command -v`,
conda (bioconda), Resource installation. Gems: none beyond stdlib here
(`term-ansicolor` arrives via log).

### Concurrency
Threads: watchdog (timeout), stdin feeder, stderr drainer, `wait_thr`; all
named; `report_on_exception = false` on helpers; ConcurrentStream carries
`pids` and `threads` for join semantics.

### Probes
- P14: `CMD.cmd(["echo","a","b"]).read` → `"a b\n"`; save_stderr to a path
  captures `"E1\n"`; `process_cmd_options` quoting as above; invalid key
  raises.
- `CMD.tool("echo", nil, nil, "echo")` + `get_tool` → `"echo"`.

### Subtle points
- The **default** stderr severity is `Log::DEBUG` (`:181`), so stderr is only
  echoed at DEBUG or when explicitly given a severity; `:stderr => true`
  maps to `Log::HIGH` (`:239-241, 270-272`).
- `no_fail` also suppresses the spawn-time ProcessFailed (`:299-300`).
- `{opt}` placeholder must be quoted in the command string (`:275-276`).
- `:save_stderr` with a path **truncates** ('w') and creates parent dirs.
- Timeout in pipe mode surfaces through `ConcurrentStream#abort` semantics,
  not a direct raise (documented in the comment block `:310-325`).

---

## 12. Packaging / root files (read for context)

- `VERSION` → `1.8.8` (single line).
- `Gemfile` → no runtime deps; dev group only (`shoulda`, `rdoc ~> 3.12`,
  `bundler ~> 1.0`, `juwelier ~> 2.1.0`, `simplecov`).
- `scout-essentials.gemspec` → juwelier-generated (`:1-2`), `s.name`/:8,
  `s.version = "1.8.8"`/:9; no `add_dependency` lines (runtime deps live in
  the Rakefile block instead).
- `Rakefile` → `ENV["BRANCH"] = 'main'`/:3; Juwelier::Tasks block
  `gem.add_runtime_dependency 'term-ansicolor' | 'yaml' | 'rake' | 'listen'`
  (:18-21); Rake::TestTask pattern `test/**/test_*.rb` (:26-28) with
  `test.libs << 'lib' << 'test'`.
- `lib/scout.rb` does **not exist** (only `lib/scout-essentials.rb` and the
  `lib/scout/` tree), so `require 'scout'` is not a supported entry point.
- Runtime gem dependencies actually observable from the audited files:
  `term-ansicolor` (lib/scout/log/color.rb:4), stdlib `io/console`
  (lib/scout/log.rb:6),
  `open3`, `stringio`, `fileutils`, `yaml`
  (lib/scout/log/progress/report.rb:1).

---

## Files covered checklist (CORE chunk)

Read in full (line-anchored above):

- [x] lib/scout-essentials.rb
- [x] lib/scout/indiferent_hash.rb
- [x] lib/scout/indiferent_hash/case_insensitive.rb
- [x] lib/scout/indiferent_hash/options.rb
- [x] lib/scout/indiferent_hash/serialize.rb
- [x] lib/scout/named_array.rb
- [x] lib/scout/misc.rb
- [x] lib/scout/misc/digest.rb
- [x] lib/scout/misc/filesystem.rb
- [x] lib/scout/misc/format.rb
- [x] lib/scout/misc/helper.rb
- [x] lib/scout/misc/hook.rb
- [x] lib/scout/misc/insist.rb
- [x] lib/scout/misc/matching.rb
- [x] lib/scout/misc/math.rb
- [x] lib/scout/misc/monitor.rb
- [x] lib/scout/misc/system.rb
- [x] lib/scout/tmpfile.rb
- [x] lib/scout/exceptions.rb
- [x] lib/scout/config.rb
- [x] lib/scout/log.rb
- [x] lib/scout/log/color.rb
- [x] lib/scout/log/color_class.rb
- [x] lib/scout/log/fingerprint.rb
- [x] lib/scout/log/trap.rb
- [x] lib/scout/log/progress.rb
- [x] lib/scout/log/progress/report.rb
- [x] lib/scout/log/progress/util.rb
- [x] lib/scout/simple_opt.rb
- [x] lib/scout/simple_opt/accessor.rb
- [x] lib/scout/simple_opt/doc.rb
- [x] lib/scout/simple_opt/get.rb
- [x] lib/scout/simple_opt/parse.rb
- [x] lib/scout/simple_opt/setup.rb
- [x] lib/scout/cmd.rb

Supporting files read:

- [x] Gemfile
- [x] scout-essentials.gemspec
- [x] Rakefile
- [x] VERSION
- [x] (lib/scout.rb — confirmed absent)

Tests consulted for semantics:

- [x] test/scout/test_config.rb
- [x] test/scout/test_tmpfile.rb
- [x] test/scout/test_indiferent_hash.rb
- [x] test/scout/indiferent_hash/test_options.rb
- [x] test/scout/indiferent_hash/test_case_insensitive.rb (listed, semantics via source)
- [x] test/scout/test_named_array.rb
- [x] test/scout/test_misc.rb (empty)
- [x] test/scout/misc/{test_digest,test_helper,test_system,test_matching,test_math,test_filesystem,test_hook,test_insist}.rb
- [x] test/scout/test_log.rb
- [x] test/scout/log/{test_color,test_fingerprint,test_progress}.rb
- [x] test/scout/simple_opt/{test_parse,test_get,test_doc,test_setup}.rb
- [x] test/scout/test_cmd.rb
- [x] test/scout/test_cmd_save_stderr.rb (listed)
- [x] test/test_helper.rb
