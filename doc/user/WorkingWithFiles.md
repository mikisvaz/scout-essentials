# Working with Files

This guide explains how to read, write, and manage files in scout-essentials:
the `Open` module for I/O, compression, grepping, atomic writes, locking, and
remote file handling, plus `TmpFile` for scratch space.

## Reading: `Open.read` and `Open.open`

```ruby
require 'scout-essentials'

Open.read('VERSION')             # => "1.8.8"     (UTF-8 fixed by default)
Open.read('VERSION', nofix: true) # => raw bytes as read

Open.open('data.txt') do |f|
  f.each_line { |line| ... }
end

Every stream returned by `Open.open` is extended with `Open::NamedStream`,
whose `filename` attribute records the file it was opened from (useful when
the stream flows through pipelines):

```ruby
io = Open.open('data.txt')
io.filename # => "data.txt"
```

- `Open.read`/`Open.open` accept a `Path` (or a `String`); a `Path` is
  resolved with `find` before opening.
- Both accept options. Notable ones:
  - `:mode` — open mode (`'r'` default, `'rb'` for binary reads).
  - `:grep` / `:invert_grep` — filter lines while reading (below).
  - `:zip` / `:gzip` / `:bgzip` — force a decompressor regardless of
    extension.
  - `:noz` — disable automatic decompression and read the raw file.

## Compression

Detection is **extension-only and case-sensitive**. A file is decompressed
only when its name ends (lower-case) with `.gz`, `.bgz`, `.zip`:

```ruby
Open.read('file.gz')    # decompressed
Open.read('file.GZ')    # raw gzip bytes — NOT detected
Open.read('file.tgz')   # raw gzip bytes — NOT detected
Open.read('file.tar.gz')# decompressed (ends in .gz)
Open.read('file.gz.bak')# raw gzip bytes — NOT detected
Open.gzip?('file.tgz')  # => false
```

To decompress content that does not carry a recognised name, run
`Open.gunzip` yourself — it is `zcat` behind a `CMD.cmd` pipe:

```ruby
Open.read('file.tgz', :gzip => false, :noz => true)  # raw bytes, if that is what you want
stream = Open.open('file.tgz', :noz => true)         # raw gzip bytes as a stream
Open.read(Open.gunzip(stream))                       # decompressed
```

Note that the historical `:gzip => true` option is **broken as a
decompression force**: it is forwarded to `CMD.cmd('zcat', …)` as a
command-line flag, the command fails, and — because `:no_fail` is set —
you get an empty string instead of an error.

## Grepping lines

`:grep` and `:invert_grep` select lines using the system `grep`. **With a
block**, `Open.read` collects the transformed lines into an Array; **without
a block** it returns the matched lines as a String (and `Open.open` returns
a grep pipe):

```ruby
# file f contains: apple / banana / cherry
Open.read(f, grep: 'an')                 # => "banana\n"   (String)
Open.read(f, grep: 'an') { |l| l.strip.upcase } # => ["BANANA"]
Open.read(f, grep: 'an', invert_grep: true)     # => "apple\ncherry\n"
Open.read(f, grep: %w(apple banana)) { |l| l.strip } # => ["apple", "banana"]
```

**`invert_grep` has no effect on its own.** `Open.read`/`Open.open` only
grep when `grep` is truthy (`Open#file_open(file, grep = false, ...)`
extracts `:grep`/`:invert_grep` but only greps for `grep`); passing
`invert_grep:` without `grep:` returns the whole file unchanged:

```ruby
Open.read(f, invert_grep: 'an')          # => "apple\nbanana\ncherry\n" (no-op)
```

To invert without going through `:grep`, use the low-level helper with its
third argument:

```ruby
Open.grep(Open.open(f), 'an', true).read # => "apple\ncherry\n"
```

`:grep` accepts a String (passed to the system `grep` as a pattern) or an
Array of Strings (written to a pattern file used with `grep -f`). Arrays are
matched with `grep -w -F` (whole-word, fixed strings) unless you pass
`fixed_grep: false`, which switches to plain `grep -f` semantics.

## Writing: `Open.write` and appends

```ruby
Open.write('out.txt', "content\n")       # creates parent dirs
Open.write('out.txt') { |f| f.puts "x" } # block form
```

`Open.write` always overwrites by default (`mode: 'w'`). **To append, pass
`mode: 'a'`** — there is no public `Open.append` class method:

```ruby
Open.write('log.txt', "one\n")
Open.write('log.txt', "two\n", mode: 'a')
Open.read('log.txt') # => "one\ntwo\n"
```

On error, `Open.write` removes the partially written file and re-raises.

### Atomic writes: `sensible_write`

`Open.sensible_write(file, content = nil, options = {})` refuses to overwrite
an existing file unless `:force => true`; it takes a String or a block and
removes the target when the block raises (`Aborted` is swallowed silently):

```ruby
Open.sensible_write(path, "v1")
Open.sensible_write(path, "v2")            # keeps "v1"
Open.sensible_write(path, "v2", force: true) # overwrites
```

## File primitives

All of these accept `Path` or `String` and resolve `Path`s via `find`; most
create parent directories as needed:

| Call | Effect |
|---|---|
| `Open.cp(src, dst)` | `cp_r`, creates parent dirs, replaces `dst` |
| `Open.mv(src, dst)` | two-step move (`.tmp_mv.` intermediate), creates parent dirs |
| `Open.rm(file)` | removes a file or broken link |
| `Open.rm_rf(file)` | recursive remove |
| `Open.mkdir(dir)` | `mkdir -p` if missing |
| `Open.mkfiledir(file)` | `mkdir -p` the parent of `file` |
| `Open.touch(file)` | `touch`, creating parent dirs |
| `Open.ln(src, dst)` | hard link (falls back to `ln_s` via `Open.link`) |
| `Open.ln_s(src, dst)` | symbolic link |
| `Open.ln_h(src, dst)` | `ln -L` with `cp -L` fallback |
| `Open.link(src, dst)` | `Open.ln`, falling back to `Open.ln_s` |
| `Open.link_dir(src, dst)` | `cp -lr` — copy a directory tree of hard links |
| `Open.same_file(a, b)` | `File.identical?` |
| `Open.exists?(f)`, `Open.directory?(f)`, `Open.size(f)`, `Open.ctime(f)`, `Open.mtime(f)` | stats |

```ruby
src = 'data/src.txt'
Open.write(src, 'S')
Open.cp(src, 'data/sub/dst.txt')           # parents created
Open.mv('data/sub/dst.txt', 'data/m.txt')
Open.touch('data/t/t.txt')
Open.ln(src, 'data/hard.txt')              # nlink > 1
Open.link_dir('data/a', 'data/a2')
Open.same_file(src, 'data/hard.txt')       # => true
```

`Open.mtime` has one special case: for a symlink or a file with multiple
hard links it consults a sibling `.info` file when `Step` is defined (a
scout-gear concept) and falls back to `Pathname#realpath`; otherwise it is a
plain `File.mtime`.

## Locking: `Open.lock`

```ruby
Open.lock('var/cache/persistence/file') do
  # exclusive access while the block runs
end
```

`Open.lock(file, unlock = true, options = {})` uses the vendored `Lockfile`
implementation. The lock file lives next to the target by default; pass a
`Lockfile` instance via `options[:lock]` to reuse an existing one. See
[Caching Results](CachingResults.md) for how `Persist` uses it.

## Streams and `consume_stream`

`Open.open_pipe` returns a `ConcurrentStream` that you can consume lazily;
`Open.consume_stream(stream)` reads it to the end (and joins it), and
`Open.sensible_write` accepts a stream, writing it asynchronously. When a
stream carries a `filename`, `NamedStream` records it so tools can recover
the original name. See
[Streaming Model](../developer/StreamingModel.md).

## Remote files

`Open.read`/`Open.open` transparently handle `http(s)://` and `ssh:` URLs by
shelling out (`Open.wget`, `Open.ssh`), and `Open.sync` / `Open.rsync` copy
remote trees into the local cache (`Open.remote_cache_dir`, default
`$HOME/.scout/var/cache/open-remote`). Remote fetching is covered in
[RemoteData.md](RemoteData.md).

## Scratch files: `TmpFile`

```ruby
TmpFile.tmp_file('prefix')     # => ".../tmpfiles/tmp-<n>" (a fresh path)
TmpFile.user_tmp               # => $HOME/tmp/scout
TmpFile.tmp_for_file('a/b/c')  # => "·a·b·c" (flat, separators replaced with ·)
TmpFile.with_file(content) do |file| ... end   # writes, yields the path, removes it
TmpFile.with_dir do |dir| ... end
```

`TmpFile.tmp_for_file` flattens the whole path into a single file name
inside the tmpfiles directory (`/` → `·`), it does **not** create a nested
directory structure; `TmpFile.tmp_for_dir` does not exist. Options may
append a `[key]` and an `&F[...]` fingerprint, and names are truncated to
`MAX_FILE_LENGTH` (150).

## Related

- [Caching Results](CachingResults.md) — `Persist` uses `Open.lock` and
  `sensible_write`.
- [Path Resolution](../developer/PathResolution.md) — `find`/`follow`, path
  maps.
- [Producing Resources](ProducingResources.md) — Resource uses Path for
  resolution.
- For streaming internals, see
  [Streaming Model](../developer/StreamingModel.md).
- For remote data, see [RemoteData.md](RemoteData.md).
