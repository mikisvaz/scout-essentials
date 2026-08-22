# Implementation inventory — chunk 3: Path / Persist / Resource / Annotation

Phase 1 forensic documentation audit of `/bulk/mvazque2/git/scout-essentials`.
Source under `lib/scout/` is authoritative; every claim below carries a `file:line`
anchor and, where behaviour is non-obvious, references a probe from
`research/behavior-probes.md` (P34–P44, scripts under `tmp/probe3*.rb`/`tmp/probe4*.rb`).

Scope (22 files):
`lib/scout/path.rb`, `path/digest.rb`, `path/find.rb`, `path/tmpfile.rb`, `path/util.rb`;
`lib/scout/persist.rb`, `persist/open.rb`, `persist/path.rb`, `persist/serialize.rb`;
`lib/scout/resource.rb`, `resource/open.rb`, `resource/path.rb`, `resource/produce.rb`,
`resource/produce/rake.rb`, `resource/scout.rb`, `resource/software.rb`, `resource/sync.rb`,
`resource/util.rb`; `lib/scout/annotation.rb`, `annotation/annotated_object.rb`,
`annotation/annotation_module.rb`, `annotation/array.rb`.

---

## 1. Path subsystem

### 1.1 `lib/scout/path.rb` — the Path model itself

`Path` is a **module**, not a class, and it *is itself an annotated type*:
- `module Path; extend Annotation; annotation :pkgdir, :libdir, :path_maps, :map_order, :where, :original` (path.rb:6-8).
  So `Path.setup(str)` produces a String extended with `Path` whose annotation set is
  those six keys, and `annotation_types` of such a Path is `[Path]` (verified P36f).

Instance methods:
- `Path.default_pkgdir` → `'scout'` (path.rb:10-12); `Path.default_pkgdir=` writer (path.rb:14-16).
- `#pkgdir` → `@pkgdir ||= Path.default_pkgdir` (path.rb:18-20).
- `#libdir` → `@libdir || Path.caller_lib_dir` (path.rb:22-24) — falls back to a **caller-stack**
  scan (`find.rb:24-49`) that walks up from the calling file looking for a dir containing
  any of `lib`, `bin`, `README.md` (find.rb:24, default `relative_to = ['lib','bin','README.md']`).
- `#path_maps` → `@path_maps ||= Path.path_maps.dup` (path.rb:26-28) — per-instance copy;
  mutations on an instance do not leak to the global table.
- `#join(subpath = nil, prevpath = nil)` (path.rb:30-40): `Symbol` args are stringified,
  `prevpath` is prepended, empty receiver yields the subpath itself; result is re-annotated
  with `self.annotate(new)` (path.rb:38). Aliases `[]` and `/` (path.rb:42-43).
- `#method_missing(name, prev = nil, *args, &block)` (path.rb:45-51): if a block is given
  or the name starts with `to_` it defers to `super`; **otherwise** it builds a path
  segment — i.e. `Scout.share.data` ≡ `Scout.share.join(:data)`. This is the
  `Scout.etc["path_maps"]` / `Scout.share.software` mechanism.
- `Path` instances also carry `#where` (find.rb:211-213) and `#original`
  (find.rb:215-217) readers, written by `#annotate_found_where` (find.rb:204-209) —
  the map name a `find` succeeded under, and a self-annotated copy of the *unlocated*
  original path.

Requires: `annotation`, `path/util`, `path/tmpfile`, `path/digest` (path.rb:1-4) and,
at the bottom, `path/find` (path.rb:53) — `find` is deliberately loaded after the
Path module body so `Path.extend Annotation` is in place first.

### 1.2 `lib/scout/path/find.rb` — resolution algorithm

Global (module-function) state, all memoised in class variables:
- `Path.path_maps` (find.rb:85-101): `IndiferentHash` of 13 default maps:
  `:current "{PWD}/{TOPLEVEL}/{SUBPATH}"`, `:home "{HOME}/{TOPLEVEL}/{PKGDIR}/{SUBPATH}"`,
  `:user "{HOME}/.{PKGDIR}/{TOPLEVEL}/{SUBPATH}"`, `:global`, `:usr`, `:local`, `:fast`,
  `:cache`, `:bulk`, `:lib "{LIBDIR}/{TOPLEVEL}/{SUBPATH}"`,
  `:scout_essentials_lib "<libdir>/{TOPLEVEL}/{SUBPATH}"` (computed from `caller_lib_dir(__FILE__)`),
  `:tmp "/tmp/{PKGDIR}/{TOPLEVEL}/{SUBPATH}"`, and `:default => :user` — a *symbol alias*.
- `Path.basic_map_order` (find.rb:103-105): `%w(current workflow user home local global usr lib fast cache bulk)`.
  Note `workflow` is listed but has no default map, so it is silently dropped.
- `Path.map_order` (find.rb:107-119): derived order = basic order with the literal `lib`
  slot replaced by every `*_lib` map followed by `lib`, then `(basic & all) + (all - basic)`.
  Observed default (P34/P39):
  `[:current, :user, :home, :local, :global, :usr, :scout_essentials_lib, :lib, :fast, :cache, :bulk, :default, :tmp]`
  — `:default` and `:tmp` come last because they are not in the basic list.
- Instance-level `#map_order` (find.rb:136-144) re-derives from the instance `path_maps`,
  keeping the global order as a template. There is **no `Path.map_order=` setter** —
  the only supported mutation entry points are `Path.add_path` / `prepend_path` / `append_path`
  (find.rb:121-134, module-function) and the instance counterparts (find.rb:146-159).
  `Path.map_order=` raises `NoMethodError` (verified P39).
  `Path.add_path` resets `@@map_order = nil` (find.rb:123) so the order is recomputed and
  the new map lands at the end; `prepend_path`/`append_path` unshift/push onto the
  *already computed* order (find.rb:128, 133), so they do not reset it.
- `Path.load_path_maps(filename)` (find.rb:161-176): if the file exists, `YAML.load`s a
  `{where: location}` mapping and `add_path`es each entry; failures are only logged
  (`Log.error`, find.rb:171). Used at boot by `resource/scout.rb:9`.

Substitution engine — `Path.follow(path, map, map_name = nil)` (find.rb:51-83):
- a map without `{` gets `/{PATH}` appended (find.rb:52);
- `{PKGDIR}` uses the path's (or module-level default) pkgdir, unwrapping nested
  pkgdir-reponding objects (find.rb:53-57);
- substitution order: `{PKGDIR}`, `{HOME}`, `{RESOURCE}` (also `path.pkgdir.to_s`),
  `{PWD}` (via `FileUtils.pwd`), `{TOPLEVEL}` (`_toplevel`), `{SUBPATH}` (`_subpath`),
  `{BASENAME}`, `{PATH}`, `{LIBDIR}`, `{MAPNAME}`, `{REMOVE}/`, `{REMOVE}` (find.rb:58-69);
- trailing `/` is dropped when the path has no subpath (find.rb:71);
- then a loop rewrites nested `{KEY/ORIG/REPLACE}` forms by recursive `follow`
  (find.rb:73-80).

Decomposition helpers (find.rb:178-188): `#_parts` (`split("/")` memoised),
`#_subpath` (all but first part, or `nil`), `#_toplevel` (first part). For a single
segment path `_toplevel == self` and `_subpath == nil` (see test `test_find.rb`).

`Path.located?(path)` (find.rb:193-198): true iff the string starts with `/`, `~/`, or `./`
(byte comparisons `SLASH = "/"[0]`, `HOME = "~"[0]`, `DOT = "."[0]`, find.rb:190-192).
Instance `#located?` delegates (find.rb:200-202).

`Path.exists_file_or_alternatives(file)` (find.rb:237-245): returns the file itself if
`Open.exist?` or `Open.directory?`; otherwise tries `file + ".gz" / ".bgz" / ".zip"`
in that fixed order; otherwise `nil`.

**`Path#find(where = nil)`** (find.rb:247-274) — the core resolution:
1. If `located?`: absolute path exists → return `self.annotate(File.expand_path(self))`;
   else check alternatives (`Path.exists_file_or_alternatives`) and annotate+return the
   alternative if present; **else return `self` unchanged** (find.rb:248-259). It never
   returns `nil` for located paths (verified P34: missing located path returns itself).
2. `where == 'all' || :all` → `find_all` (find.rb:261).
3. `where` given (Symbol/String) → `follow(where)` (find.rb:263). If the name is a String
   not in `path_maps`, `follow` synthesises `File.join(map_name, '{TOPLEVEL}/{SUBPATH}')`
   (find.rb:222-224); an unknown Symbol still raises `"Map not found"` (find.rb:225).
4. Otherwise iterate `map_order`, skipping names not present in `path_maps`
   (find.rb:265-271): `follow(map_name, false)` (no annotation), then
   `Path.exists_file_or_alternatives`; first hit is returned via
   `annotate_found_where(found, map_name)` which sets `@where` and `@original`
   (find.rb:269-270). The alternative check considers gz/bgz/zip suffixes and, when only
   a compressed variant is on disk, find returns the suffixed path annotated with the
   winning map name (verified P44).
5. Nothing found → **fall through to `follow(:default)`** (find.rb:273), i.e. by default
   the `:user` map location (`{HOME}/.{PKGDIR}/{TOPLEVEL}/{SUBPATH}`), *not* nil
   (verified P34: `/tmp/nonexistent…` returned self; unlocated `share/data/some_file`
   returned `~/.scout/share/…`).

Related predicates:
- `#exist?` / `#exists?` (find.rb:276-283): `File.exist?(self.find) || File.directory?(…)`.
- `#find_all(caller_lib = nil, search_paths = nil)` (find.rb:284-288): maps `map_order`
  through `find`, selects existing, `uniq`. (The `caller_lib`/`search_paths` params are
  accepted but unused.)
- `#find_with_extension(extension, *args, produce: true)` (find.rb:290-303): plain find
  first; if that exists and is not a directory it wins; otherwise try
  `set_extension(ext).find` for each extension (Array or single) and return the first
  that exists; **fall back to the un-extended `found`** (find.rb:302).

### 1.3 `lib/scout/path/util.rb` — filesystem helpers on Path

- `Path.is_filename?(string, need_to_exists = true)` (util.rb:8-16): `Path` passes; a
  String passes if it has no newline, is < 265 chars (or no component > 265), and — with
  `need_to_exists` — `File.exist?`.
- `Path.can_read?` / `can_write?` (util.rb:18-33): remote URLs are always "readable" but
  never "writable"; otherwise `is_filename?` + not-a-directory checks, `find` applied for
  Path instances, and for `can_write?` writability of the file or of its parent dir.
- `Path.sanitize_filename(filename, length = 254)` (util.rb:35-50): overlong names are
  truncated and suffixed `--<len>--<digest5>` plus a preserved 2–9 char extension.
- `#directory?` → `nil` unless `exist?`, else `File.directory?(self.find)` (util.rb:52-55).
- `#realpath`, `#relative_to(dir)` (util.rb:57-63) — both operate on `find`.
- `#sub`, `#dirname`, `#basename` (util.rb:65-75) re-annotate the result.
- `#glob(pattern = "*")` (util.rb:77-97): a receiver containing `*` is globbed directly
  when located, else via `glob_all`; otherwise the receiver must `exist?`, results are
  annotated and, if the found location has an `original`, each result's `original` is
  rewritten relative to it (util.rb:91-93).
- `#glob_names(...)` (util.rb:99-101) = `glob(...).collect(&:basename)`.
- `#glob_all(pattern = nil, caller_lib = nil, search_paths = nil)` (util.rb:103-122):
  iterates every entry of `self.path_maps` (or `Path.path_maps`), calls `find(where)` per
  entry, keeps only located results, globs each, annotates, and sets `original`/`where`
  when a pattern was given.
- Extension helpers: `#get_extension(multiple = false)` (util.rb:124-133; when `multiple`
  collects up to 4 extra dotted segments), `#set_extension(ext)` (util.rb:135-137, appends
  `.ext`), `#unset_extension` (util.rb:139-146), `#remove_extension(ext = nil)`
  (util.rb:148-154), `#replace_extension(new_ext, multiple = false)` (util.rb:156-166).
- Freshness: `#newer_files(*files)` (util.rb:168-172) and `#outdated?(...)` (util.rb:174-176)
  select files newer than self; `Path.newer?(path, file, by_link = false)`
  (util.rb:179-194) returns a *numeric age difference* (negative) when the file is newer
  than the path, `false` otherwise, `true` when `file` does not exist — it is truthy/falsy
  tri-state, not a boolean. Uses `Open.mtime` (so `<file>.info` Step blobs participate,
  see chunk-2 findings) unless `by_link` (then `File.lstat.mtime`).
- `#final_pkgdir` (util.rb:196-200): unwraps pkgdir chains (`pkgdir.pkgdir while …`).

### 1.4 `lib/scout/path/digest.rb` — `#digest_str`

`Path#digest_str` (digest.rb:3-22):
- directory → `glob("*")`, reject directories, `Annotation.purge` the annotated results,
  and emit `"Directory MD5: <n> <digest>"` when > 10 files else `"Directory MD5: <digest>"`;
- existing located file → `"File MD5: <Misc.digest_file(self)>"`;
- otherwise `'\'' + self << '\''` (note: literal quote wrapping, digest.rb:20 — this is a
  quoting quirk, not an error).

### 1.5 `lib/scout/path/tmpfile.rb`

`TmpFile.with_path(*args, &block)` (tmpfile.rb:2-7) wraps `TmpFile.with_file` and
`Path.setup`s the generated temp name before yielding. This is the only content; the
tmp-root/digest conventions live in `lib/scout/tmpfile.rb` (chunk-1 inventory).

---

## 2. Persist subsystem

### 2.1 `lib/scout/persist.rb` — cache/lock roots, `persistence_path`, `persist`

Class-level configuration:
- `Persist.cache_dir` defaults to `Path.setup("var/cache/persistence")` (persist.rb:12-14)
  — a **relative** Path; `cache_dir=` accepts a String or Path (persist.rb:8-10).
- `Persist.lock_dir` defaults to `Path.setup("tmp/persist_locks").find` (persist.rb:16-19),
  which resolves through the default path maps to `$HOME/.scout/tmp/persist_locks`
  (observed P41: `/home/mvazque2/.scout/tmp/persist_locks`).

**`Persist.persistence_path(name, options = {})`** (persist.rb:22-28):
- `options` is an options hash; the defaults add `:dir => Persist.cache_dir`;
  "other" options are pulled out and appended by `TmpFile.tmp_for_file` as
  `:<digest>` (observed P41: `…/foo:41a66144f5d092dbc008b979700699d4`).
- `Persist.persistence_path(name, :marshal)` is **not valid** — the symbol is treated as
  the options hash and fails with `TypeError: can't define singleton` (P41). The type is
  *never* passed to `persistence_path`; `Persist.persist` takes it as a separate
  positional parameter.
- A `:key` option yields `name + "[key]"` via TmpFile's clean-options naming
  (observed P41: `…/foo[K]`), following the same `MAX_FILE_LENGTH`/digest truncation rules
  as all TmpFile names (`tmpfile.rb`, chunk-1).

`Persist.persist(name, type = :serializer, options = {}, &block)` (persist.rb:32-144):
1. pulls `:persist`-prefixed sub-options; `:persist => false` short-circuits to `yield`
   (persist.rb:33-34).
2. `file = persist_options[:path] || options[:path] || persistence_path(name, options)`
   (persist.rb:36); `:data`, `:check`, `:no_load`, `:update` read from either level
   (persist.rb:37-41). `update` may be a Time, a Numeric (seconds of staleness) or truthy
   (persist.rb:45-49); `Path`-valued `update` is converted with `Open.mtime` (persist.rb:42).
   If `file` is a Path and `check` is set, `update` is forced when the file is outdated
   (persist.rb:44).
3. `type == :memory` bypasses all locking and files: repo is `options[:memory] ||
   options[:repo] || MEMORY_CACHE`, keyed by `file`; `update` recomputes, otherwise the
   cached value is reused (persist.rb:51-59). `Persist.memory(name, options, &block)`
   (persist.rb:146-149) is a thin wrapper that derives a `:path`/`:persist_path` from
   `[name, options[:key]] * ":"` when a `:key` is given.
4. Otherwise a lockfile is built as `persistence_path(file + '.persist',
   :dir => Persist.lock_dir)` (persist.rb:61) and the whole read-or-compute critical
   section runs inside `Open.lock` (persist.rb:63), i.e. the chunk-2 `Lockfile` payload
   mechanism with `LockInterrupted` semantics.
5. Cache hit (`Open.exist?(file) && ! update`): with `:no_load => true` return the file
   path, else `Persist.load(file, type)` (persist.rb:64-69).
6. Miss: `Open.rm(file.find)` if updating (persist.rb:72); `file = file.find` when it is a
   Path (persist.rb:74). A block with `arity == 1` is called with either the caller's
   `:data` or the file name (persist.rb:75-81); arity 0 blocks are plain `yield`
   (persist.rb:83).
7. `res.nil?` handling (persist.rb:86-99): with `no_load` return the file; else with a nil
   `type` return nil; else `Persist.load(file, type)`.
8. Stream results (`IO`/`StringIO`): tee into `tee_copies + 1` streams (default 1 copy,
   persist.rb:102), mark `main.lock = lock`, spawn a saver thread running
   `Open.sensible_write(file, main)` (persist.rb:103-110), wrap every copy as a
   `ConcurrentStream` with `:threads => t, :filename => file, :autojoin => true, :next => …`
   (persist.rb:111-114) and return the first copy, raising `KeepLocked.new(res)` so the
   outer `Open.lock` keeps the lockfile until the stream joins (persist.rb:116; the
   `KeepLocked < DontPersist` taxonomy is established in chunk 1/2).
9. Non-stream results are written via `Persist.save(res, file, type)` and `res` is
   replaced by the save result unless it is nil (persist.rb:118-119) — for file-backed
   types `Persist.save` returns nil, so the *block's* value is returned, not the file path.
10. Error path (persist.rb:121-135): on any `Exception`, the partially written file is
    removed under `Thread.handle_interrupt(Exception => :never)` unless the exception is a
    `DontPersist` (persist.rb:130), and the exception is re-raised unless
    `options[:canfail]` (persist.rb:133) — with `:canfail` execution falls through to
    persist.rb:137-141 returning `file` when `no_load` is exactly `true`, else `res`
    (which may be nil).
11. Final return for a successful write: `file` if `no_load == true` else `res`
    (persist.rb:137-141).

### 2.2 `lib/scout/persist/serialize.rb` — types, drivers, save/load

Constants: `TRUE_STRINGS` (Set of 13 truthy spellings, serialize.rb:6) and
`SERIALIZER = :json` (serialize.rb:7) — **the default serializer type is JSON, not marshal**.

Pluggable drivers: `save_drivers` / `load_drivers` hashes with accessors
(serialize.rb:9-17); `save` consults `save_drivers[type]` first, calling it with
`(content)` when its arity is 1 (result written with `Open.sensible_write`) or
`(file, content)` otherwise (serialize.rb:103-109); `load` consults `load_drivers[type]`
(serialize.rb:133-135).

`Persist.serialize(content, type)` (serialize.rb:19-47):
- `nil, :string, :text, :integer, :float, :boolean, :file, :path, :select, :folder,
  :binary` → `content.read` for IO/StringIO else `content.to_s` (serialize.rb:23-28);
- `:array` → `content * "\n"` (serialize.rb:29-30);
- `:yaml` / `:json` / `:marshal` → `to_yaml` / `to_json` / `Marshal.dump` (serialize.rb:31-36);
- `:annotation, :annotations` → `Annotation.tsv(content, :all).to_s` (serialize.rb:37-38) —
  **requires an external `Annotation.tsv` that this gem does not define** (there is no
  `Annotation#tsv` anywhere under `lib/`; `grep` for `def tsv` in `annotation*.rb` is
  empty) and therefore raises `NoMethodError: undefined method 'tsv' for module Annotation`
  at runtime (verified P42/P38);
- `:serializer` is rewritten to `SERIALIZER` (:json) first (serialize.rb:21);
- any `*_array` suffix is expanded recursively and joined with newlines (serialize.rb:40-43);
- anything else raises `"Persist does not know …"` (serialize.rb:44).

`Persist.deserialize(serialized, type)` (serialize.rb:49-85):
- `nil, :text, :stream` → as-is (serialize.rb:54-55); `:string, :file, :select, :folder` →
  `strip` (serialize.rb:56-57); `:path` → `Path.setup(serialized.strip)` (serialize.rb:58-59);
- `:integer`/`:float` → `to_i`/`to_f`; `:boolean` → membership in `TRUE_STRINGS`
  (serialize.rb:60-65);
- `:array` → `split("\n")` (serialize.rb:66-67);
- `:yaml` → **`YAML.parse`** (serialize.rb:68-69), i.e. a Psych AST node, *not* a loaded
  Ruby object — a documented-in-code asymmetry with `Persist.load(file, :yaml)` which uses
  `Open.yaml` (serialize.rb:141). Verified P35: deserializing a YAML string returns a
  `Psych::Nodes::Document`.
- `:json` → `JSON.parse`; `:marshal` → `Marshal.load` (serialize.rb:70-73);
- `:annotation, :annotations` → `Annotation.load_tsv(TSV.open(serialized))`
  (serialize.rb:74-75) — depends on **both** an external `TSV` class and an external
  `Annotation.load_tsv`; neither is defined in this gem (`grep TSV lib/` only matches the
  two call sites plus Log/progress references). So the `:annotation` persistence type is
  *declared but not functional* standalone (verified P38: `Persist.persist(…, :annotation, …)`
  raises `NoMethodError`).
- `*_array` recursion as in serialize (serialize.rb:77-80); unknown raises
  (serialize.rb:82).

`Persist.save(content, file, type = :serializer)` (serialize.rb:88-122):
- normalises `nil` type to `:serializer`; `:memory` swaps in the shared `MEMORY` hash;
  returns immediately on `nil` content (serialize.rb:89-95) — note `type == :memory` is
  checked twice (serialize.rb:92 and :94, dead line);
- `Hash === type` writes `type[file] = content` (in-memory repo) and returns (serialize.rb:97-100);
- driver hook (serialize.rb:103-109);
- `:binary` forces `ASCII-8BIT` and writes with `f.puts` in `wb` mode, returning
  `content` (serialize.rb:111-116);
- everything else: `serialize(content, type)` + `Open.sensible_write(file, serialized,
  :force => true)` and **returns nil** (serialize.rb:117-121) — which is why
  `Persist.persist` keeps the block value for file-backed types (persist.rb:118-119).

`Persist.load(file, type = :serializer)` (serialize.rb:124-169):
- `file = file.find if Path === file` (serialize.rb:125); returns `nil` unless the type is
  a Hash (memory repo) or the file exists (serialize.rb:130);
- special-cased loaders: `:binary` (`Open.read … :mode => 'rb'`), `:yaml` (`Open.yaml`, i.e.
  `YAML.unsafe_load`), `:json` (`Open.json`), `:marshal`/`:serializer` (`Open.marshal`),
  `:stream` (`Open.open(file)`), `:path` (return the Path itself), `:file` (read the file,
  rewrite a leading `./` to the file's dirname, and return that value only if it
  `Path.is_filename?`, else return `file`), `:file_array` (same per line)
  (serialize.rb:137-162);
- `Hash` type → repo lookup (serialize.rb:163-164);
- otherwise generic `Open.read` + `deserialize` (serialize.rb:165-168). Note `:file_array`
  exists as a *load-only* special case; its serialization goes through the generic
  `*_array` machinery (`:file` + "\n").

### 2.3 `lib/scout/persist/open.rb` — typed readers

`Open.json(file)` (open.rb:6-9) and `Open.yaml(file)` (open.rb:11-14) both call
`file.find_with_extension(:json|:yaml)` when given a Path — so they transparently fall
back to `.json.gz`-style alternatives per `Path#find_with_extension`.
`Open.yaml` uses **`YAML.unsafe_load`** (open.rb:13). `Open.marshal(file)` (open.rb:16-18)
has no extension fallback.

### 2.4 `lib/scout/persist/path.rb` — instance sugar

Reopens `Path` to add `#yaml`, `#json`, `#marshal` delegating to the corresponding
`Open.*` readers (path.rb:2-14). Loaded by `persist.rb:3` only, so these methods exist
once `scout/persist` has been required.

---

## 3. Resource subsystem

### 3.1 `lib/scout/resource.rb` — the Resource module itself

`module Resource; extend Annotation; annotation :pkgdir, :libdir, :subdir, :resources,
:rake_dirs, :path_maps, :map_order, :lock_dir` (resource.rb:19-21). Like `Path`, `Resource`
is an *annotated module*: a resource is any module that `extend`s `Resource` and thereby
gains `claim`, `produce`, `identify`, … plus per-instance annotation ivars.

The file `require_relative`s its parts **twice** (resource.rb:3-8 and :10-17) — harmless
(`require_relative` is idempotent) but noteworthy.

Class-level: `Resource.default_resource` accessor (resource.rb:23-29). `Resource.default_lock_dir`
= `Path.setup('tmp/produce_locks').find` (resource.rb:31-33) → resolves to
`$HOME/.scout/tmp/produce_locks` (observed P43).

Instance (i.e. per-resource) helpers:
- `#path_maps` / `#map_order` duplicate the Path globals (resource.rb:35-41) so a resource
  can be scoped independently;
- `#prepend_path(name, map)` / `#append_path(name, map)` (resource.rb:43-51) mutate that copy;
- `#subdir` defaults to `""` (resource.rb:53-55); `#lock_dir` defaults to
  `Resource.default_lock_dir` (resource.rb:57-59); `#pkgdir` defaults to
  `Path.default_pkgdir` (resource.rb:61-63);
- `#root` → `Path.setup(subdir.dup, self, self.libdir, @path_maps, @map_order)`
  (resource.rb:65-67) — the resource acts as the *pkgdir annotation* of its root Path,
  which is how `Path#produce` finds its way back to the claiming resource
  (`resource/path.rb:6`);
- `#method_missing(name, prev = nil, *args)` (resource.rb:69-75) forwards to `root`,
  reproducing the Path segment-building ergonomics at resource level (`Scout.etc`,
  `Scout.share`, `Scout.lib`, …).

### 3.2 `lib/scout/resource/scout.rb` — bootstrapping `Scout` as the default resource

- `module Scout; extend Resource; self.pkgdir = 'scout'` (scout.rb:1-5) — the top-level
  `Scout` namespace *is* a Resource with pkgdir `'scout'` (and `Path.default_pkgdir`
  is also `'scout'`, path.rb:11).
- `Resource.default_resource = Scout` (scout.rb:7).
- `Path.load_path_maps(Scout.etc["path_maps"])` (scout.rb:9) — at require time the
  `etc/path_maps` YAML (if it exists) augments the built-in map table; failures are logged
  and swallowed (find.rb:170-172).

### 3.3 `lib/scout/resource/path.rb` — Path#produce and friends

`Path#produce(force = false)` (path.rb:2-21):
- re-raises a previously stored `@produced` if it is an Exception (path.rb:3) — failures
  are memoised and re-raised on every subsequent call;
- returns `self` when not forcing and either the located file exists or a previous
  produce succeeded (path.rb:4);
- dispatches to `self.pkgdir.produce(self, force)` when the pkgdir annotation is a
  Resource (path.rb:6-7), otherwise returns `false` (path.rb:8-10) — a Path with no
  Resource pkgdir **silently returns false**;
- `ResourceNotFound` is caught and turned into `@produced = false` (path.rb:11-12), so a
  missing claim makes `produce` return `false` rather than raise;
- any other exception is logged with `Log.warn` and re-raised (path.rb:13-17);
- `ensure` sets `@produced = true` if still nil (path.rb:18-20) — so a *successful*
  no-op (nothing to do) is memoised as `true`, a `ResourceNotFound` leaves `false`.
  Consequence (verified P37c): requesting `.gz` when only the un-compressed name is
  claimed makes `produce` return `false` the first time (extension fall-through found
  the `.gz` claim to be absent) yet `find` still returns the `.gz` name that was created
  by the claim registered for it; conversely requesting `h` when `h.gz` is claimed
  produces the `.gz` file and `find` returns the `.gz` path.

`Path#produce_with_extension(extension, *args)` (path.rb:23-34): try `produce`, on
exception try `set_extension(extension).produce`, re-raise the *first* exception if the
second also fails.

`Path#produce_and_find(extension = nil, *args)` (path.rb:36-47): `find_with_extension` /
`find`; if the result exists return it, otherwise produce (with extension) and raise
`"Not found: #{self}"` unless something truthy came back.

`Path#relocate` (path.rb:49-52): `self` if it already exists, else `Resource.relocate(self)`.
`Path#identify` (path.rb:54-56) delegates to `Resource.identify`.

Convenience IO: `#open(*args, &block)` and `#read` call `produce` first then `Open.open`/
`Open.read` (path.rb:58-66); `#write(*args, &block)` writes to `self.find` **without**
producing (path.rb:68-70); `#list` = `produce_and_find('list')` + `Open.list` (path.rb:72-75).

`Path#exists?(produce: true)` (path.rb:77-85) — redefined here on top of the base
`Path#exist?` (find.rb:276) to optionally *produce* the path before concluding.

`Path#find_with_extension(extension, *args, produce: true)` (path.rb:87-100) — redefined
here so each candidate is checked with `exists?(produce: produce)`; the base version in
`path/find.rb:290` is shadowed once `resource/path` is loaded.

### 3.4 `lib/scout/resource/produce.rb` — claims and the produce engine

`Resource#claim(path, type, content = nil, &block)` (produce.rb:6-14):
- `type == :rake` registers in `@rake_dirs[path] = content || block`;
- everything else registers `@resources[path] = [type, content || block]`.
  There is **no validation of `type`** at claim time; the registry is keyed by the raw
  path string.

Lookup helpers: `#rake_for(path)` (produce.rb:16-23) selects rake dirs that are prefixes
of `path` (`Misc.path_relative_to`) sorted by length, taking the longest;
`#has_rake?(path)` (produce.rb:25-27).

`#run_rake(path, rakefile, rake_dir)` (produce.rb:29-51): computes the task as the path
relative to the rake dir; `produce`s/`find`s the rakefile if it responds; resolves
`rake_dir.find(:user)`; sets `Thread.current["resource"] = self`; calls `ScoutRake.run`
(with the block when the rakefile is a Proc); on `ScoutRake::TaskNotFound` it walks *up*
one directory level (`task = File.join(File.basename(rake_dir), task)`,
`rake_dir = File.dirname(rake_dir)`) and retries, re-raising at the filesystem root.

**`Resource#produce(path, force = false)`** (produce.rb:53-158) — the engine:
1. Claim selection (produce.rb:54-77): exact match in `@resources`; else match on
   `path.original` (the unlocated original when a *found* path was passed in); else a
   rake claim; else — for paths not ending in `.gz`/`.bgz` — **automatic extension
   fall-through**: retry with `path + '.gz'` and then `path + '.bgz'`, and only then raise
   `ResourceNotFound "Resource is missing and does not seem to be claimed: …"`
   (produce.rb:64-76). Paths that already end in `.gz`/`.bgz` raise `ResourceNotFound`
   directly (produce.rb:74-76).
2. Target resolution: `path.find(:default)` when forcing, `path.find` otherwise
   (produce.rb:79-83).
3. Production runs only when a type exists and the target is missing or forcing
   (produce.rb:85). Locking: `lock_filename = TmpFile.tmp_for_file(final_path,
   :dir => lock_dir)` then `Open.lock lock_filename { … }` (produce.rb:87-89) — a
   per-resource lock dir (default `$HOME/.scout/tmp/produce_locks`) and a lock *name
   derived from the final path*, following TmpFile digest naming. `force` removes the
   existing target before the inner check (produce.rb:90).
4. Dispatch on `type` (produce.rb:94-144), each arm wrapped in a rescue that removes the
   partial target and re-raises (produce.rb:145-148):
   - `:string` → `Open.sensible_write(final_path, content)` (produce.rb:96-97);
   - `:csv` → **raises `"TSV/CSV Not implemented yet"` immediately** (produce.rb:98-102,
     with the commented-out `rbbt/tsv/csv` implementation left in place);
   - `:url` → `Open.sensible_write(final_path, Open.open(content, options))` with
     `:noz => true` when the target is compressed (produce.rb:103-106) (remote fetch via
     `Open.wget`/curl, see chunk 2);
   - `:proc` → call with arity 0 or 1 (the target path) (produce.rb:107-113); the result is
     written when it is `String, IO, StringIO` (direct), `Array` (`* "\n"`), `TSV`
     (`data.dumper_stream`) or `TSV::Dumper` (`data.stream`); `nil` is tolerated
     (produce.rb:114-126). Because the `case` evaluates `when TSV` before `when nil`
     (produce.rb:119, 123), a proc returning `nil` in a process where no `TSV` constant
     is defined raises `NameError: uninitialized constant Resource::TSV` — verified P43.
     When a TSV library *is* loaded, the ordering still means a String/IO result is fine
     but any other non-listed object raises `"Unkown object produced: …"` (sic,
     produce.rb:125);
   - `:rake` → `run_rake(path, content, rake_dir)`; failures whose message contains
     `"Don't know how to build task"` are converted to `ResourceNotFound`
     (produce.rb:127-136);
   - `:install` → `software_dir = self.root.software`, `Resource.install(content, name,
     software_dir)`, then `set_software_env(software_dir)` (produce.rb:137-141);
   - anything else raises `"Could not produce #{resource}. (#{type}, #{content})"`
     (produce.rb:142-143).
   The implemented claim types are therefore **`:string`, `:url`, `:proc`, `:rake`,
   `:install`** (plus `:csv` which is a stub). There is no `:annotation` claim type.
5. After production the path's location cache is invalidated —
   `path.instance_variable_set("@path", {})` (produce.rb:155) — so that a subsequent
   `find` re-scans all maps (e.g. picking up a `.gz` that just appeared); `path` is
   returned (produce.rb:157).

### 3.5 `lib/scout/resource/produce/rake.rb` — ScoutRake

- `Rake::FileTask.define_task` is monkey-patched to record every defined file task in a
  class-level `@@files` list with `Rake::FileTask.files` / `.clear_files`
  (rake.rb:5-23).
- `module ScoutRake` defines `TaskNotFound < StandardError` (rake.rb:26) and
  `ScoutRake.run(rakefile, dir, task, &block)` (rake.rb:27-68):
  clears `Rake::Task` and the recorded files (rake.rb:30-31), then **forks**. In the
  child: if a block is given it is `instance_exec`'d on the top-level binding receiver
  (rake.rb:36); else the rakefile is either loaded from disk (`rakefile.produce.find`
  first, rake.rb:38-40) or written to a `TmpFile` and loaded (rake.rb:42-45). A missing
  task raises `TaskNotFound` (rake.rb:48); the task is invoked inside `Misc.in_dir(dir)`
  (rake.rb:52), any exception is logged (`Log.exception`, `Log.error`) and the child
  `Kernel.exit!(-1)` (rake.rb:58-62); success exits 0 (rake.rb:63). The parent
  `Misc.wait_child(pid)` and raises `"Rake failed"` unless `$?.success?` (rake.rb:65-66).
  Net effect: rake production happens in a separate process; rake-side exceptions do not
  propagate as-is — the parent sees a generic `"Rake failed"` (which the
  `:rake` arm in produce.rb:130-135 inspects for the "Don't know how to build task"
  text to convert to `ResourceNotFound`).

### 3.6 `lib/scout/resource/open.rb` — auto-produce on Open

Reopens `class << Open` aliasing the original `open` as `_just_open` and defining
`Open.open(file, *args, **kwargs, &block)` that calls `file.produce` when `file` is a
`Path` before delegating (open.rb:1-9). Combined with `Path#find`'s transparent
alternative lookup this is why `Open.open(some_unlocated_path)` materialises resources.

### 3.7 `lib/scout/resource/util.rb` — identify / relocate

`Resource#identify(path)` (util.rb:2-68) — the inverse of `follow`:
- non-Path inputs are `Path.setup`; located-ness short-circuits to the input itself
  (util.rb:3-4);
- uses the path's (or the resource's, or the global) `path_maps`, minus `:current`
  (util.rb:6-11), and `Path.caller_lib_dir` for `{LIBDIR}` (util.rb:13);
- each map pattern is turned into an anchored regexp: `{TOPLEVEL}` → `(?<TOPLEVEL>[^/]+)`,
  `\.{PKGDIR}` → `\.(?<PKGDIR>[^/]+)` (note the leading dot — matching the `.{PKGDIR}`
  form used by the `:user` map), `{LIBDIR}` substituted literally, any other
  `{GROUP}` → an optional `(?<GROUP>[^/]+)` segment, plus a trailing optional
  `(?<REST>.+)` and optional slash (util.rb:28-34);
- a match is accepted only when the pattern had no PKGDIR group or the captured pkgdir
  equals `self.final_pkgdir` (util.rb:35-36); the unlocated form is assembled from the
  first non-nil of `TOPLEVEL/SUBPATH/PATH/REST` (util.rb:38-40), the resource `subdir`
  is stripped as a prefix (util.rb:42-46), the result is annotated (util.rb:48) and
  collected as a candidate;
- the shortest candidate wins (util.rb:55), falling back to the input (util.rb:57);
- `$HOME` is collapsed to `~` (util.rb:59-63) and the result is re-setup with the
  resource and its path maps (util.rb:65).

`Resource.identify(path)` (util.rb:70-75) resolves the resource from `path.pkgdir`,
falling back to `Resource.default_resource`; `Resource.relocate(path)` (util.rb:77-81)
returns the path when it exists, else `identify(path).find`.

### 3.8 `lib/scout/resource/software.rb` — `:install` claims

- `Resource.install_helpers` → `Scout.share.software.install_helpers.find(:lib)`
  (software.rb:3-5), i.e. the helper shell library shipped in the gem's `share` tree.
- `Resource.install(content, name, software_dir = Path.setup('software'), &block)`
  (software.rb:7-97): the software dir is resolved with `find(:user)` when it is a Path
  (software.rb:9); a block overrides the content; a Hash content may carry `:name`,
  `:git`, `:src`, `:url`, `:jar`, `:extra`, `:commands`; a remote String is classified as
  `{:git => …}` when it matches `git:|\.git$` else `{:src => …}` (software.rb:24-30).
  The generated bash script is a fixed preamble (`SOFTWARE_DIR`, sourcing
  `INSTALL_HELPER_FILE`, software.rb:13-20) followed by `install_git`/`install_src`/
  `install_jar`/raw-commands sections (software.rb:32-91), executed via
  `CMD.cmd_log('bash', :in => script)` (software.rb:95); `Resource.set_software_env` is
  called afterwards (software.rb:96).
- `Resource.set_software_env(software_dir = Path.setup('software'))` (software.rb:99-175):
  iterates `software_dir.opt.find_all` (all map locations) in reverse; for each existing
  location it adds `<dir>/opt/bin` to `PATH`, touches `.ld-paths/.c-paths/.pkgconfig-paths/
  .aclocal-paths/.java-classpaths` under `opt` (software.rb:108-119), then reads each of
  those files to extend `C_INCLUDE_PATH`/`CPLUS_INCLUDE_PATH`, `LIBRARY_PATH`/
  `LD_LIBRARY_PATH`/`LD_RUN_PATH`, `PKG_CONFIG_PATH`, `ACLOCAL_FLAGS`, `CLASSPATH`, plus
  every `opt/jars/*.jar` (software.rb:121-156); finally, any `opt/.post_install/*` files
  are scanned for `export VAR=value` lines whose `$var` references are expanded from
  `ENV` and applied (software.rb:158-173). The module calls `self.set_software_env` at
  require time (software.rb:177).

### 3.9 `lib/scout/resource/sync.rb`

`Resource.sync(path, map = nil, options = {})` (sync.rb:3-23): `map` defaults to
`'user'`; the resource comes from `options[:resource]`, else `path.pkgdir` when it is a
Resource, else `Resource.default_resource` (sync.rb:4-9). The target is
`resource.identify(path).find(map)` (sync.rb:11). Source selection: the literal path when
it exists, else `path.directory? ? path.find_all : path.glob_all` (sync.rb:13-18); each
source is copied with `Open.sync(source, target, options)` (sync.rb:20-22), which is an
alias of `Open.rsync` (open/sync.rb:81-83) — rsync `-avztHP --copy-unsafe-links
--omit-dir-times` with the default excludes `.save .crap .source tmp filecache
open-remote` (open/sync.rb:7, 42-44), `--link-dest` when `:hard_link` (open/sync.rb:43),
`-nv` when `:test`, optional `--files-from` (open/sync.rb:45-51), plus optional post-hoc
deletion when `:delete && :files` (open/sync.rb:66-79).

---

## 4. Annotation subsystem

### 4.1 `lib/scout/annotation.rb` — the module-level API

- `Annotation.setup(obj, annotation_types, annotation_hash)` (annotation.rb:7-20):
  `annotation_types` may be a `"|"`-joined String, a single type or an Array; each name is
  resolved with `Kernel.const_get` and applied via `type.setup(obj, annotation_hash)`
  (annotation.rb:9-14); unknown names are only warned about (`Log.warn "Annotation #{type}
  not defined"`, annotation.rb:15-16) and skipped. `nil` input returns nil (annotation.rb:8).
- `Annotation.extended(base)` (annotation.rb:22-26): when a module/class `extend`s
  `Annotation` it gets `@annotations = []`, `include Annotation::AnnotatedObject` and
  `extend Annotation::AnnotationModule` — this is what turns a plain module into an
  annotation *type* with `annotation`, `setup`, `annotated?`, …
- `Annotation.is_annotated?(obj)` (annotation.rb:28-30): checks
  `obj.instance_variables.include?(:@annotation_types) && obj.respond_to?(:purge)`.
- `Annotation.purge(obj)` (annotation.rb:32-48): recursively strips annotations from
  Arrays (purging the array itself when annotated, then each element), Hashes (keys and
  values) and annotated leaves (`obj.purge`).

### 4.2 `lib/scout/annotation/annotated_object.rb` — instance side

Mixed into every annotation *type*, so into every annotated object:
- `#annotation_types` → memoised `@annotation_types ||= []` (annotated_object.rb:3-5) —
  populated by `AnnotationModule#extended` (annotation_module.rb:29);
- `#base_type` → `annotation_types.last` (annotated_object.rb:7-9);
- `#annotation_hash` → `{name => ivar}` for every name in `@annotations`
  (annotated_object.rb:11-17);
- `#annotation_info` → `annotation_hash.merge(annotation_types:, annotated_array:)`
  (annotated_object.rb:19-21);
- `AnnotatedObject.serialize(obj)` / `#serialize` (annotated_object.rb:23-29):
  `Annotation.purge(obj.annotation_info.merge(literal: obj))` — a *plain Hash*
  `{<attr> => value, annotation_types: [...], annotated_array: bool, literal: obj}`
  (verified P42). There is no TSV involved at this level;
- `#annotation_id` / `#id` → `Misc.digest([self, annotation_info])` (annotated_object.rb:31-35);
- `#annotate(other)` → apply every own annotation type (with the own attribute values) to
  another object (annotated_object.rb:37-42);
- `#purge` (annotated_object.rb:44-73): `dup`, then remove every `@<attr>` listed in
  `@annotations` plus `@annotations`, `@annotation_types`, `@container`,
  `@container_index`, and recursively purge every remaining ivar value (annotated_object.rb:67-70).
  The *class* of the object is unchanged — a purged annotated Array is still an Array
  extended with the annotation modules, just without the metadata (verified: after purge
  `Annotation.is_annotated?` is false because `@annotation_types` is gone, but
  `instance_variables` shows the annotated-array state was removed, P36g);
- `#make_array` → `[self]`, annotated and extended with `AnnotatedArray`
  (annotated_object.rb:75-80).

### 4.3 `lib/scout/annotation/annotation_module.rb` — type definition

- `#annotation(*attrs)` (annotation_module.rb:4-11): appends new names to the type's
  `@annotations` (skipping duplicates) and defines attr accessors.
- `#annotations` → memoised `@annotations ||= []` (annotation_module.rb:13-15).
- `#included(mod)` / `#extended(obj)` (annotation_module.rb:17-34): propagate the
  attribute list; `extended` additionally pushes `self` onto `obj.annotation_types`
  (annotation_module.rb:29) — this is the only place `@annotation_types` is grown, and it
  explains `Annotation.is_annotated?`'s ivar check.
- **`#setup(*args, &block)`** (annotation_module.rb:36-69): the workhorse used as
  `MyType.setup(obj, …)`. A leading block is treated as the object (`obj, rest = block,
  args`, annotation_module.rb:37-41); frozen objects are dup'ed (annotation_module.rb:44);
  `obj.extend self` is attempted and a `TypeError` (extending a non-module-friendly
  singleton, e.g. some immediates) simply returns the object un-annotated
  (annotation_module.rb:45-49). Argument binding (annotation_module.rb:54-61): if the last
  rest arg is a 1-element Hash whose first key is an attribute name — or, loosely, when
  the attribute list is not of length 1 (`! attrs.length != 1`, a condition that is true
  whenever `attrs.length != 1` and false when it is exactly 1) — the Hash is used as
  name/value pairs; otherwise attributes are zipped positionally with the rest args.
  Values are assigned as `@<name>` ivars, skipping `nil` values and the reserved
  `:annotation_types` name (annotation_module.rb:63-66).
  Note the aliasing chain: `Path.setup` is exactly this method
  (`Path.setup('a/b').annotation_types == [Path]`, P36f) because `Path` extends
  `Annotation`; `Path.setup` therefore accepts either a Hash of `:pkgdir/:libdir/…` or
  positional values in annotation declaration order (`pkgdir, libdir, path_maps, map_order,
  where, original`, path.rb:8).

### 4.4 `lib/scout/annotation/array.rb` — AnnotatedArray

- `AnnotatedArrayItem` (array.rb:3-5) adds `container` / `container_index` accessors;
  `AnnotatedArray.is_contained?(obj)` (array.rb:7-9) tests for it.
- `#annotate_item(obj, position = nil)` (array.rb:11-19): dup frozen items, extend nested
  Arrays with `AnnotatedArray`, extend with `AnnotatedArrayItem`, record the container and
  index, then `self.annotate(obj)`.
- Index/iteration overrides that lazily annotate items: `#[]` (with a `clean = false`
  second arg to skip annotation, array.rb:21-25), `#first`, `#last`, `#each_with_index`,
  `#each`, `#inject` (array.rb:27-63).
- `#collect` is implemented on top of `inject` so that both block and no-block forms work
  (array.rb:65-71); `#select` builds a fresh annotated array (array.rb:41-48).
- Set-like helpers: `#subset(list)` = `self.annotate(self & list)`, `#remove(list)` =
  `self.annotate(self - list)` (array.rb:73-79).
- `compact, uniq, flatten, reverse, sort_by` are wrapped so the result is re-annotated and
  re-extended with `AnnotatedArray` (array.rb:81-91).

Container representation (settling the suspicion): an annotated *array* is the Array
object itself extended with `AnnotatedArray` (which in turn was `setup` with the
annotation types), carrying `@annotations`, `@annotation_types` and the per-attribute
ivars directly on the Array — **there is no separate container/name/value triplet
structure**. Items fetched out of an annotated array get `container`/`container_index`
plus a copy of the annotations via `annotate_item`; `Annotation.purge` removes all of it.

### 4.5 What `:annotation` persistence actually needs

`Persist.serialize(…, :annotation)` calls `Annotation.tsv(content, :all).to_s`
(serialize.rb:37-38) and `Persist.deserialize` calls
`Annotation.load_tsv(TSV.open(serialized))` (serialize.rb:74-75). Neither `Annotation.tsv`
nor `Annotation.load_tsv` nor `TSV` itself is defined anywhere in this gem (`grep`
`def tsv|load_tsv` under `lib/scout/annotation*` returns nothing; `Object.const_defined?(:TSV)`
is false, P42). The `:annotation` type is therefore **external-library dependent and
non-functional standalone** — `Persist.persist(…, :annotation, …)` raises
`NoMethodError: undefined method 'tsv' for module Annotation` (verified P38), and
`Resource`'s `:proc` claim dispatcher similarly trips over the `TSV` constant
(produce.rb:119-122, verified P43).

---

## 5. Cross-cutting notes and doc-suspicion hot-spots

1. **`Path#find` never returns nil.** Located paths return `self`; unlocated paths
   fall through to `follow(:default)` (the `:user` map) even when nothing exists
   (find.rb:247-274, P34). Docs claiming "returns nil if not found" are wrong.
2. **Default search order** is *derived*, not the `path_maps` declaration order, and
   `:default`/`:tmp` trail at the end (find.rb:103-119, P34/P39). `basic_map_order`
   contains a `workflow` entry with no default map.
3. **No `Path.map_order=`** — only `add_path`/`prepend_path`/`append_path` mutate it
   (P39). Instance-level `path_maps=`/`map_order=` also do not exist; you assign the
   per-instance copy via `p.path_maps = {...}` only because `path_maps` is a declared
   annotation attr (path.rb:8) — there is no equivalent for `map_order` on instances
   beyond `prepend_path`.
4. **`Persist.persistence_path(name, :marshal)` is invalid** (P41); the type belongs to
   `Persist.persist`'s second positional parameter.
5. **`Persist` default serializer is `:json`** (serialize.rb:7), while `Persist.load`'s
   `:serializer` branch uses `Open.marshal` (serialize.rb:144-145) — a mismatch to
   double-check in docs: `load(file)` with no type marshals, `persist(name)` with no type
   JSON-serialises.
6. **`Persist.deserialize(…, :yaml)` returns a Psych AST node** (serialize.rb:69, P35),
   unlike `Persist.load(file, :yaml)` which returns real objects.
7. **`:annotation` persistence is unimplemented standalone** (serialize.rb:37-38, 74-75;
   P38, P42); **`:csv` claims are a stub** that raises immediately (produce.rb:98-102, P37b).
8. **Implemented claim types**: `:string`, `:url`, `:proc`, `:rake`, `:install`
   (produce.rb:95-141). `:proc` returning `nil` mis-fires on the undefined `TSV`
   constant (produce.rb:119-123, P43).
9. **`Path#produce` memoisation uses `@produced` tri-state**: `true` on success/no-op,
   `false` after `ResourceNotFound`, an Exception object stored and re-raised on later
   calls (resource/path.rb:2-21, P37c).
10. **Extension fall-through is asymmetric**: `Resource#produce` retries `.gz` then `.bgz`
    for unclaimed un-compressed names (produce.rb:64-73), so asking for `x` when `x.gz`
    is claimed produces the gzip file and `find` then returns `x.gz`; asking for `x.gz`
    when only `x` is claimed yields a `false` produce result (P37c).
11. **Produce locks** live in `Resource#lock_dir` (default `$HOME/.scout/tmp/produce_locks`)
    and are named after the *final* path via TmpFile digest naming (produce.rb:87);
    **persist locks** live in `Persist.lock_dir` (`$HOME/.scout/tmp/persist_locks`) with
    a `.persist` suffix (persist.rb:61) — two distinct lock namespaces.
12. **Rake production is forked**; parent-side failures surface as the generic
    `"Rake failed"` string which produce.rb:130-135 string-matches to convert
    "Don't know how to build task" into `ResourceNotFound` (rake.rb:27-68).
13. **`Open.open` auto-produces Paths** (resource/open.rb:4-9), and `Open.yaml`/`Open.json`
    transparently use `find_with_extension` (persist/open.rb:7, 12).
14. **`Resource.identify` collapses `$HOME` to `~`** (util.rb:59-63) and strips the
    resource `subdir` prefix (util.rb:42-46); its regexp treats `.{PKGDIR}` (dot-prefixed)
    specially (util.rb:31).
15. **`Path#digest_str` wraps non-existent paths in literal single quotes**
    (digest.rb:20) — the output is `'<path>'`, quotes included.
16. **`Annotation.setup` swallows unknown type names with a warning** (annotation.rb:15-16),
    and `AnnotationModule#setup` returns un-annotated objects when `extend` raises
    `TypeError` (annotation_module.rb:47-49).
17. **`AnnotatedArray#[]`'s second parameter is `clean`**, not a length: `arr[0, true]`
    returns the raw un-annotated item (array.rb:21-25).

---

## Files covered checklist

- [x] lib/scout/path.rb
- [x] lib/scout/path/digest.rb
- [x] lib/scout/path/find.rb
- [x] lib/scout/path/tmpfile.rb
- [x] lib/scout/path/util.rb
- [x] lib/scout/persist.rb
- [x] lib/scout/persist/open.rb
- [x] lib/scout/persist/path.rb
- [x] lib/scout/persist/serialize.rb
- [x] lib/scout/resource.rb
- [x] lib/scout/resource/open.rb
- [x] lib/scout/resource/path.rb
- [x] lib/scout/resource/produce.rb
- [x] lib/scout/resource/produce/rake.rb
- [x] lib/scout/resource/scout.rb
- [x] lib/scout/resource/software.rb
- [x] lib/scout/resource/sync.rb
- [x] lib/scout/resource/util.rb
- [x] lib/scout/annotation.rb
- [x] lib/scout/annotation/annotated_object.rb
- [x] lib/scout/annotation/annotation_module.rb
- [x] lib/scout/annotation/array.rb

(22/22.)
