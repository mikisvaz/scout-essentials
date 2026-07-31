# Investigation: File I/O, Paths, and Temporary Files

**Status:** Non-normative investigation artifact. May be outdated.

## Scope
Open, Path, TmpFile, and their interactions.

---

## TmpFile

### What it is
A minimal module providing temporary file/directory paths and scoped helpers.

### Key methods
- `TmpFile.tmpdir` — base directory (default `~/tmp/scout/tmpfiles`).
- `TmpFile.user_tmp(subdir)` — user-scoped tmp directory.
- `TmpFile.random_name(prefix, max)` — prefix + random integer.
- `TmpFile.tmp_file(prefix, max, dir)` — path inside dir (defaults to tmpdir).

### Scoped helpers (create-then-cleanup)
- `with_file(content=nil, erase=true, options={})` — create a temporary file,
  optionally pre-populate it with content (String, IO, or StringIO), yield the
  path, then delete it.
  - IO content is read in chunks via `readpartial`.
  - Options: `:prefix`, `:max`, `:tmpdir`, `:extension`.
- `with_dir(erase=true, options={})` — create a temp directory, yield, cleanup.
- `in_dir(*args)` — create temp dir, `chdir` into it, yield, cleanup.

### Persistence path helper
- `tmp_for_file(file, tmp_options={}, other_options={})` — generates a stable
  cache filename from a logical filename + options.
  - Replaces `/` with `·` (SLASH_REPLACE) to make a single filename.
  - Truncates names over 150 chars, appends a digest.
  - Appends a digest of `other_options` for parameter-variant uniqueness.
  - Used pervasively by Persist to generate cache paths.

### Design insight
TmpFile is the **fundamental cache-path primitive** — it turns logical names
into stable filesystem paths. It does not itself manage caching or locking;
it just builds deterministic paths.

---

## Open

### What it is
A unified, high-level file/stream/remote I/O module. It wraps plain File I/O,
streaming helpers, remote fetching (wget/ssh), atomic writes, locking,
compression auto-handling, and filesystem utilities (grep, sort, collapse,
wc, head, tail, mv, cp, rm).

### Sub-modules
- `Open/stream.rb` — streaming, tee streams, `sensible_write`, monitor streams.
- `Open/util.rb` — existence checks, remote detection, compression detection,
  realpath, gzip/bgzip/zip helpers, grep, sort, wc, head, tail, mv, cp, rm,
  is_gzip?/is_bgzip?/is_zip? detection.
- `Open/remote.rb` — remote detection, `wget` download, `ssh` file operations
  (exists, open, read, write, mv, cp, upload, download), scp.
- `Open/lock/lockfile.rb` — cross-process locking via lock files (a port of
  the Lockfile gem). Supports `Open.lock(file) { ... }`.
- `Open/final.rb` — streaming wrappers with guaranteed resource cleanup
  (`stream_without_close`, etc.).

### Key patterns

#### Auto-decompression
`Open.read("data.tsv.gz")` automatically detects `.gz`, `.bgz`, `.zip` and
decompresses transparently. `Open.open` also auto-detects compression on the
fly via magic byte detection.

#### Remote access
- `Open.remote?(path)` — detects `http://`, `https://`, `ssh:` prefixes.
- `Open.open(remote_url)` — downloads via `wget` to a cache, then opens.
- SSH-style: `Open.exists?("server:file")`, `Open.read("server:file")` etc.

#### Atomic writes (sensible_write)
`Open.sensible_write(file, content)` writes to a temporary file then renames
atomically. Uses a lock to prevent concurrent writes to the same target.
This is the safe way to write files that might be read concurrently.

#### Cross-process locking
`Open.lock(lockfile) { ... }` — file-based locks using `flock` + lock files.
Used by Persist and Resource for concurrent-safe resource production.

#### Stream handling
- `Open.open(path) { |io| ... }` — streaming file open with auto-decompression.
- `Open.stream(io)` — wraps an IO into a ConcurrentStream for lifecycle safety.
- `Open.tee_stream(io)` — splits a stream into multiple consumers.
- `Open.consume_stream(io, close=true)` — reads to end and closes.

#### Grep/sort/wc utilities
`Open.grep(stream, pattern)`, `Open.sort(stream)`, `Open.wc(stream)`,
`Open.head(stream, n)`, `Open.collapse_stream(stream)` — stream-processing
utilities that work on file paths or IO objects.

### Compression detection
- `Open.is_gzip?(file)` — magic bytes `\x1f\x8b`.
- `Open.is_bgzip?(file)` — magic bytes `\x1f\x8b` + extra field in header.
- `Open.is_zip?(file)` — magic bytes `PK\x03\x04`.
- `Open.gzip?(file)` — file extension `.gz`.
- `Open.bgzip?(file)` — file extension `.bgz`.
- `Open.zip?(file)` — file extension `.zip`.

---

## Path

### What it is
A path abstraction layered on top of Annotation. Paths are annotated Strings
that know how to **find** themselves across a configurable set of locations
(path maps).

### Annotations
- `pkgdir` — logical package name (default 'scout').
- `libdir` — library directory for resolving `lib` maps.
- `path_maps` — hash of named location templates.
- `map_order` — ordered list of map names to try.
- `where` — which map resolved successfully during `find`.
- `original` — the path before resolution.

### Setup
- `Path.setup(string, pkgdir, libdir, path_maps, map_order)` — extends a plain
  String with Path annotations.
- A Path **is** a String; it responds to all String methods plus path-specific
  ones.

### Path maps system
Path maps are templates with placeholders:
- `{PKGDIR}`, `{HOME}`, `{PWD}`, `{TOPLEVEL}`, `{SUBPATH}`, `{PATH}`,
  `{BASENAME}`, `{LIBDIR}`, `{RESOURCE}`, `{MAPNAME}`.

Default maps:
```ruby
:current => "{PWD}/{TOPLEVEL}/{SUBPATH}"
:home    => "{HOME}/{TOPLEVEL}/{PKGDIR}/{SUBPATH}"
:user    => "{HOME}/.{PKGDIR}/{TOPLEVEL}/{SUBPATH}"
:global  => '/{TOPLEVEL}/{PKGDIR}/{SUBPATH}'
:lib     => '{LIBDIR}/{TOPLEVEL}/{SUBPATH}'
# etc.
```

### Resolution: `find`
```ruby
path = Path.setup("data/file.tsv", "mypkg")
path.find  # tries each map in map_order, returns first existing location
```

- If the path is already located (absolute, ~/, ./), `find` returns immediately.
- Otherwise, it iterates `map_order`, applies each map template, and checks
  existence (including `.gz`/`.bgz` alternatives).
- The first match wins; `where` annotation records which map resolved.

### Method-missing as path builder
```ruby
path = Path.setup("data", "mypkg")
path.file   # → "data/file"  (as annotated Path)
path.data.tsv  # → "data/data/tsv"
```
This works because `method_missing(name, prev)` calls `join(name, prev)`,
which returns an annotated Path. This is the idiomatic Scout way to build
nested paths.

### Operators
- `path / "subpath"` — alias for `join`.
- `path["subpath"]` — alias for `join`.
- `path.join("subpath")` — returns a new annotated Path.

### located? check
`Path.located?(path)` — returns true if path starts with `/`, `~/`, or `./`.
These paths are treated as already resolved and are not subject to map
resolution.

### Path manipulation
- `_parts` — split by `/`.
- `_toplevel` — first path component.
- `_subpath` — everything after the first `/`.
- `set_extension(ext)` — swap file extension.
- `set_extension` — used by `find_with_extension`.

### find_with_extension
```ruby
path.find_with_extension(['tsv', 'csv'], produce: true)
```
Tries the path as-is, then tries each extension. Useful when the exact
extension is not known.

---

## Cross-module interactions

- **Path depends on Annotation** — extends Annotation; paths are annotated strings.
- **Path depends on IndiferentHash** — path_maps is an IndiferentHash.
- **Open depends on Path** — for path resolution in read/write operations.
- **Open depends on ConcurrentStream** — for streaming safety.
- **TmpFile depends on Open** — uses `Open.mkdir` to ensure directories exist.
- **Resource depends on Path and Open** — resources are annotated paths that
  can be produced on demand.
- **Persist depends on TmpFile** — uses `tmp_for_file` to generate cache paths.

---

## Gotchas and warnings

1. **Path.map_order is a class variable (@@map_order)** — modifying it globally
   affects all Path instances. Use instance-level `@map_order` for per-resource
   customization.
2. **Path.method_missing sends `to_*` methods to super** — `path.to_s` works
   normally, but any custom method starting with `to_` is passed through.
3. **Open.remote? requires the full URL prefix** — bare hostnames without
   `http://` or `ssh:` are treated as local paths.
3. **Open.sensible_write lock files are not always cleaned up** — if the
   process crashes during write, lock files may persist in
   `tmp/sensible_write_locks`.
4. **Path.find may return a path that doesn't exist** — if no map resolves to
   an existing file, `find` returns the `:default` map result (which may not
   exist). Always check `exist?` or `File.exist?` after `find`.
5. **TmpFile.tmp_for_file generates Path-annotated strings** — the return value
   is a Path, not a plain String, so it responds to `find`, `produce`, etc.
6. **Open.open auto-decompresses based on file content, not just extension** —
   if a file named `.tsv` actually contains gzipped data, Open.open will
   still decompress it.
7. **ConcurrentStream.setup on streams returned by Open** — when you use
   `Open.open` with a block, the stream is automatically set up with
   ConcurrentStream. When using `Open.read`, the stream is consumed and
   closed.
8. **Open.read on a directory** — returns an empty string or raises, depending
   on the Ruby version.
