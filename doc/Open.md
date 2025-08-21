# Open

The Open module provides unified, high-level file/stream/remote I/O and filesystem utilities. It wraps plain File I/O, streaming helpers, remote fetching (wget/ssh), atomic/sensible writes, pipe/fifo helpers, gzip/bgzip/zip helpers, file-system operations (mkdir, mv, ln, cp, rm, etc.), and a lock wrapper (Lockfile). Use Open when you need robust file access, streaming, temporary/atomic writes, remote access and process-safe locking.

Sections:
- Opening / reading / writing files
- Streams, pipes and tees
- Sensible / atomic writes
- Remote fetching, caching and downloads
- File / filesystem helpers
- Locking
- Sync (rsync)
- Utilities (gzip/bgzip/grep/sort/collapse)
- Examples
- Notes and edge cases

---

## Opening / reading / writing files

Open unifies access and transparently handles compressed and remote files.

- Open.open(file, options = {}) { |io| ... } or returns an IO-like stream
  - Accepts File paths, Path objects, IO, StringIO.
  - Options (via IndiferentHash):
    - :mode (default 'r') — file open mode (e.g., 'r', 'w', 'rb', etc.)
    - :grep, :invert_grep, :fixed_grep — pipe the stream through grep
    - :noz — if true, do not auto-decompress zip/gzip/bgz
    - :gzip / :bgzip / :zip — force decompression
  - For compressed files: Open detects .gz, .bgz, .zip and pipes through gzip/bgzip/unzip unless mode includes "w" (noz true).
  - The returned stream is extended with NamedStream (has .filename and digest_str helper).

- Open.file_open(file, grep = false, mode = 'r', invert_grep = false, fixed_grep = true, options = {})
  - Returns the basic stream (no auto-decompress). Uses get_stream to handle remote/ssh/wget or open file.

- Open.get_stream(file, mode = 'r', options = {})
  - Low-level stream getter:
    - If file is already a stream, returns it.
    - If file responds to .stream, returns file.stream.
    - If Path, resolves .find.
    - If remote URL, delegates to Open.ssh or Open.wget.
    - Finally falls back to File.open(File.expand_path(file), mode).

- Open.read(file, options = {}) { |line| ... } or returns String
  - If block given: yields lines from file (fixes UTF-8 by default; suppressed via :nofix).
  - If no block: returns full file contents (UTF-8 fixed by default).
  - Supports :grep and :invert_grep (see tests).

- Open.write(file, content = nil, options = {})
  - Atomic/robust writing wrapper:
    - options default includes :mode => 'w'
    - If mode includes 'w' ensures parent directory exists.
    - If a block is given, yields a File object opened in mode and ensures close; on exception removes target file.
    - If content is nil => writes empty file.
    - If content is String => writes content.
    - If content is an IO/StringIO => streams content into file with locking.
    - On success calls Open.notify_write(file) and returns nil.
  - Use for simple writes; for safer concurrency-sensitive writes prefer Open.sensible_write (below).

---

## Streams, pipes and tees

Open contains multiple helpers to produce and manage streams:

- Open.consume_stream(io, in_thread = false, into = nil, into_close = true)
  - Consumes `io` reading blocks of size BLOCK_SIZE and writes into `into` (file or IO) or discards.
  - If in_thread true, spawns a consumer thread and returns it (thread named and stored).
  - Handles exceptions: closes and deletes partial files on failure; forwards abort to stream if supported.

- Open.pipe
  - Creates an IO.pipe pair [reader, writer] and records writer for management. Returns [sout, sin] (sout reader, sin writer).
  - Caller typically uses sout as stream to read and sin to write.

- Open.open_pipe { |sin| ... } -> returns sout
  - Creates a pipe and runs the block with `sin` (writer) in a new thread (or fork if requested). The returned `sout` is a ConcurrentStream configured to join/handle threads/pids.
  - Example: use for producing a stream on-the-fly for other consumers.

- Open.open_pipe(do_fork = false, close = true) yields sin in child/forked thread and returns sout for parent.

- Open.tee_stream_thread(stream) / Open.tee_stream_thread_multiple(stream, num)
  - Duplicate input stream into multiple output pipes; returns out pipes.
  - Uses a splitter thread that reads from the source and writes to each pipe; sets up abort callbacks and cleanup.
  - Useful to fan-out a single stream to multiple consumers without re-reading source.

- Open.tee_stream(stream) — convenience returns two outputs.

- Open.read_stream / Open.read_stream(stream, size)
  - Blocking reads helper to ensure reading exactly `size` bytes; raises ClosedStream if stream EOF.

- Open.with_fifo(path = nil, clean = true) { |path| ... }
  - Create FIFO in temp path and yield it; removes it after block.

---

## Sensible / atomic writes

Use `Open.sensible_write(path, content, options = {})` for safe writes that avoid overwriting existing targets and use temporary files + atomic rename.

- Behavior:
  - If path exists and :force not true, will consume source and skip update.
  - Writes to a temporary file in `Open.sensible_write_dir` then moves (Open.mv) into place.
  - Supports lock options via `:lock` key (uses Open.lock). Accepts hash of lock settings or Lockfile instance.
  - Ensures cleanup of temp files on exception; preserves existing target if write fails.
  - On successful move, calls Open.notify_write(path).

- Open.sensible_write_lock_dir / Open.sensible_write_dir are configurable directories (Paths) used for temporary files and lock state.

- Open.sensible_write uses Open.lock to protect move operations.

- For basic atomic writes, Open.write does attempt file lock during write (f.flock File::LOCK_EX) but sensible_write also uses safer tmp->mv semantics and optionally locking for concurrent processes.

---

## Remote fetching, caching and downloads

Open supports remote URLs and SSH-style access:

- Open.remote?(file) -> Boolean if URL-like (http|https|ftp|ssh)
- Open.ssh?(file) -> ssh:// scheme detection
- Open.ssh(file, options = {})
  - Parses ssh://server:path and streams via `ssh server cat 'path'` (if server != 'localhost').
  - For localhost returns Open.open(file) (local path handling).

- Open.wget(url, options = {})
  - Download via `wget` (through CMD.cmd), returns an IO-like stream (ConcurrentStream).
  - Options:
    - :pipe => true (default), :autojoin => true
    - supports `--post-data=`, cookies, quiet mode, :force, :nocache
    - caching: unless :nocache true, saves to remote_cache_dir under a digest filename (Open.add_cache) and returns Open.open on cache file.
    - :nice / :nice_key for throttling repeated requests with a wait
    - Errors raise OpenURLError on failure
  - Example: Open.wget('http://example.com', quiet: true, nocache: true).read

- Open.cache_file(url, options), Open.in_cache(url, options), Open.add_cache(url, data, options), Open.open_cache(url)
  - Support caching remote requests to `Open.remote_cache_dir`.

- Open.download(url, file) — wrapper to run wget into local file with logging.

- Open.digest_url(url, options) — compute cache key based on url and post data/file.

- Open.scp(source_file, target_file, target:, source:) — convenience wrapper for scp and remote mkdir.

---

## File / filesystem helpers

Common filesystem operations with Path support:

- Open.mkdir(path) — ensure directory exists (mkdir_p). Accepts Path.
- Open.mkfiledir(target) — ensure parent dir exists for file target.
- Open.mv(source, target) — move with tmp intermediate to reduce risk (move to .tmp_mv.* then rename).
- Open.rm(file) — remove file if exists or broken symlink.
- Open.rm_rf(file) — recursive remove
- Open.touch(file) — create or update mtime (ensures parent dir).
- Open.cp(source, target) — copy (uses cp_r, removes existing target).
- Open.directory?(file)
- Open.exists?(file) / Open.exist? alias — existence check (Path supported).
- Open.ctime(file), Open.mtime(file) — time helpers; mtime has logic to follow symlinks and handle special Step info file cases.
- Open.size(file)
- Open.ln_s(source, target) — create symbolic link (ensures parent dir and remove existing).
- Open.ln(source, target) — create hard link (removing target if present).
- Open.ln_h(source, target) — attempt hard link via `ln -L`, fallback to copy on failure.
- Open.link(source, target) — tries ln then ln_s as fallback.
- Open.link_dir(source, target) — cp with hard-links (cp_lr).
- Open.same_file(file1, file2) — File.identical?
- Open.writable?(path) — checks writability handling symlinks and non-existing files.
- Open.realpath(file) — returns canonical realpath (resolves symlinks).
- Open.list(file) — returns file contents split on newline (convenience).

---

## Locking

Open wraps Lockfile to provide safe locking primitives and a simpler interface.

- Open.lock(file, unlock = true, options = {}) { |lockfile| ... }
  - Acquire a lock (Lockfile) for a given path.
  - `file` may be:
    - a Lockfile instance (used directly),
    - Path/String (lockfile path defaulting to `file + '.lock'`),
    - nil with options[:lock] being a Lockfile instance or false.
  - `unlock` default true; set false to keep lock after block (or raise KeepLocked inside block to keep lock and return payload).
  - Options passed to Lockfile constructor (min_sleep, max_sleep, sleep_inc, max_age, refresh, timeout, etc.).
  - Handles exceptions and unlocks safely in ensure.
  - Example (from tests):
    ```ruby
    Open.lock lockfile_path, min_sleep: 0.01, max_sleep: 0.05 do
      # critical section
    end
    ```

- Lockfile class is included in `open/lock/lockfile.rb` — classic NFS-safe lockfile implementation (supports refreshing, stealing detection, sweeps, retries, timeouts, etc.). Use its options via Open.lock(..., options).

---

## Sync (rsync)

- Open.rsync(source, target, options = {})
  - Wrapper to build and execute an `rsync` command with common options.
  - Options processed via IndiferentHash:
    - :excludes, :files (list of files to transfer), :hard_link (use --link-dest), :test (dry-run), :print (return command), :delete, :source, :target (server strings), :other (extra args)
  - Handles directory trailing slashes, remote server prefixes, ensures target dirs exist (remote mkdir via ssh when needed).
  - Uses TMP files for --files-from when passing a list.
  - Example:
    ```ruby
    Open.rsync(source_dir, target_dir, excludes: 'tmp_dir', delete: true)
    ```

- Open.sync is alias for rsync.

---

## Utilities

- Compression helpers:
  - Open.gzip?(file) / Open.bgzip?(file) / Open.zip?(file) — simple extension checks.
  - Open.gunzip(stream), Open.gzip(stream), Open.bgzip(stream) — spawn subprocesses (zcat/gzip/bgzip) returning a piped IO.
  - Open.gzip_pipe(file) — returns shell-friendly expression for gzip handling.

- Open.grep(stream, grep, invert = false, fixed = nil, options = {})
  - Uses system grep (GREP_CMD) to filter stream. Accepts Array of patterns (written to temporary file and used with -f) or single pattern.

- Open.sort_stream(stream, header_hash: "#", cmd_args: nil, memory: false)
  - Sort stream while preserving header lines (lines starting with header_hash).
  - For memory=false runs external sort (env LC_ALL=C sort).
  - Splits into substreams to avoid loading entire stream into memory for large inputs.

- Open.collapse_stream(s, line: nil, sep: "\t", header: nil, compact: false, &block)
  - Collapses consecutive lines with same key (first field) merging rest columns with `|` separators or processed by provided block.
  - Useful for aggregating grouped data in streaming fashion.

- Open.consume_stream described above.

- Open.notify_write(file)
  - If `<file>.notify` exists, reads its contents and sends notification (email or system notify) and removes .notify file.

- Open.broken_link?(path) — true if symlink target missing
- Open.exist_or_link?(file) — exists or symlink
- Open.list(file) — read as lines

- Lockfile utility: Lockfile.create(path) creates lock and opens file (used internally).

---

## Examples (from tests)

Reading and line-wise processing:
```ruby
sum = 0
Open.read(file) { |line| sum += line.to_i }
```

Open compressed file:
```ruby
Open.read("file.txt.gz")  # decompresses and returns content
```

Sensible write:
```ruby
Open.sensible_write(target_path, File.open(source))  # safe atomic write from stream
```

Pipe and open_pipe:
```ruby
sout = Open.open_pipe do |sin|
  10.times { |i| sin.puts "line #{i}" }
end
# sout is a readable stream; consume:
Open.consume_stream(sout, false, target_file)
```

Tee stream to two consumers:
```ruby
sout = Open.open_pipe do |sin|
  2000.times { |i| sin.puts "line #{i}" }
end
s1, s2 = Open.tee_stream_thread(sout)
t1 = Open.consume_stream(s1, true, tmp.file1)
t2 = Open.consume_stream(s2, true, tmp.file2)
t1.join; t2.join
```

Locking (concurrency safe):
```ruby
Open.lock(lockfile_path, min_sleep: 0.01, max_sleep: 0.05) do
  # critical section
end
```

Rsync:
```ruby
Open.rsync(source, target)
Open.sync(source, target) # alias
```

Sorting a stream while preserving headers:
```ruby
sorted = Open.sort_stream(string_io)
puts sorted.read
```

Collapse grouped rows:
```ruby
stream = Open.collapse_stream(s, sep: " ") do |parts|
  parts.map(&:upcase) # or aggregate
end
```

Remote fetch:
```ruby
io = Open.wget('http://example.com', quiet: true)
puts io.read
```

---

## Notes & edge cases

- Many functions accept Path objects and will call `.find` or `.produce_and_find` where appropriate.
- Remote functions rely on external commands (wget, ssh). Errors from those commands are wrapped/propagated (OpenURLError, ConcurrentStreamProcessFailed, etc.).
- Open.sensible_write and Open.write try to avoid inconsistent partial files; sensible_write uses tmp-file + mv and optional Lockfile to avoid races.
- Stream utilities use a ConcurrentStream abstraction (not documented here) to manage thread/pid/join semantics.
- Tee/splitter threads forward aborts and exceptions to downstream consumers; callers must handle cleanup and join threads.
- Open.lock relies on the included Lockfile implementation which supports NFS-safe locking, lock refreshing, stealing detection and sweeping stale locks.
- gzip/bgzip/unzip operations spawn external processes and return piped IOs — ensure you consume/join and close these streams to avoid zombies.
- Open.grep handles Array of patterns by writing them to a tmp file and using `-f` grep; fixed matching uses -F and -w by default.

---

This document covers the main public behaviors of the Open module: unified file/stream opening, robust writing, streaming utilities, remote fetching and caching, filesystem helpers, locking and synchronization, and convenience utilities for sorting, collapsing and grepping streams. Use Open for safe, composable I/O operations in scripts and concurrent code.