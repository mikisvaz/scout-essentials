# Implementation inventory — chunk 2: Open / CMD-adjacent, streaming, concurrency, locking

Phase 1 forensic documentation audit. Source under `lib/scout/` is authoritative; this
document records what the code *actually* does, with file:line anchors, so that the doc
layer can be checked against it.

Chunk 1 findings referenced here (see `research/implementation-inventory-core.md`):
exceptions taxonomy, `Log` severity knobs, `TmpFile.tmp_for_file` naming/digest gating.

Probes referenced as P22–P33 live in `research/behavior-probes.md`.

---

## 1. `lib/scout/concurrent_stream.rb` — ConcurrentStream / AbortedStream

### Module/class structure
- `AbortedStream` — plain module, not an exception; `AbortedStream.setup(obj, exception=nil)` *extends* an arbitrary object (typically a stream) and sets `obj.exception` (concurrent_stream.rb:3-9). It is the marker used by `sensible_write` to recover the original failure when an upstream stream was aborted (open/stream.rb:153).
- `ConcurrentStream` — module, mixed into IO/StringIO objects; all state via `attr_accessor` (concurrent_stream.rb:12): `threads, pids, callback, abort_callback, filename, joined, aborted, autojoin, lock, no_fail, pair, thread, stream_exception, log, std_err, next, exit_status`.

### `ConcurrentStream.setup(stream, options = {}, &block)` — arity 2(+block)
(concurrent_stream.rb:14-63). Options: `:threads, :pids, :callback, :abort_callback, :filename, :autojoin, :lock, :no_fail, :pair, :next`.
- Idempotent: only extends when not already a ConcurrentStream (line 18).
- `threads`/`pids` default to `[]` then are `concat`-ed, so repeated `setup` calls accumulate rather than replace (lines 20-23).
- `std_err` is reset to `""` on every setup call (line 26) — **subtle**: re-setup on an existing stream wipes previously collected stderr.
- A block given to `setup` becomes the `callback` (line 31).
- New callbacks are *chained after* existing ones (old then new, lines 32-42); same for `abort_callback` (lines 44-54). This is why `tee_stream` can layer callbacks (open/stream.rb:352,364).
- `aborted` is reset to `false` (line 60) — setup is a "re-arm".

### State predicates and filename fallback
- `filename` (line 65-67): if `@filename` is nil, derives a name from `self.inspect` by taking everything after the last `:` and dropping the final `>`. This is a *display* fallback only (probe P24 shows e.g. `"0x00007ce596cb6170 @threads=[]..."`), not a real path.
- `annotate(stream)` (line 69-72): copies `threads, pids, callback, abort_callback, filename, autojoin, lock` onto another stream. Note `:pair`, `:next`, `:no_fail` are **not** propagated.
- `clear` (line 74-76): nils `@threads, @pids, @callback, @abort_callback, @joined`. After `clear`, `joined?`/`aborted?` read instance vars that may be nil (probe P24: `threads` → `nil`, `joined?` → `nil`, i.e. no longer truthy).
- `joined?` / `aborted?` (lines 78-84) are plain readers, not computed.

### join family
- `join_threads` (lines 86-122): joins each thread except `Thread.current`. If a thread's value is a `Process::Status` and not successful, builds a message from `log` + `std_err` (looking for an "error"/"exception"/`::` line) and raises `ConcurrentStreamProcessFailed.new(t.pid, msg, self)` unless `no_fail` (lines 92-109). Any `Exception` during join is swallowed if `no_fail`, else `stream_raise_exception $!` (lines 111-118). Threads array is emptied afterwards (line 121).
- `join_pids` (lines 124-136): `Process.waitpid(pid, Process::WUNTRACED)`, records `self.exit_status`, raises `ConcurrentStreamProcessFailed` unless `$?.success? or no_fail`; `Errno::ECHILD` swallowed. No zombie reaper thread exists — reaping happens only at join time (contrast with a "zombie handler" in other frameworks; docs claiming automatic reaping would be wrong).
- `join_callback` (lines 138-146): runs `@callback` once (nils it in `ensure`), skipped if already `joined?`.
- `join` (lines 148-164): `join_threads` → `join_pids` → `raise stream_exception if stream_exception` → `join_callback` → `close unless closed?`; in `ensure`, sets `@joined = true`, unlocks `lock` if locked (logging exceptions), and re-raises `stream_exception` if present. So `join` always marks joined, even on failure.
- `add_callback(&block)` (lines 273-279): wraps existing callback to run *new* one after old — note opposite order from `setup` chaining (which is old→new).

### abort family
- `abort_threads(exception=nil)` (lines 166-188): for each thread except current and not already flagged `t["aborted"]`, sets the flag, defaults exception to `Aborted.new`, `t.raise(exception)`, then joins them. Threads marked aborted are skipped later.
- `abort_pids` (lines 190-199): `Process.kill :INT, pid` per pid; `Errno::ESRCH` swallowed; empties `@pids`.
- `abort(exception=nil)` (lines 201-231): memoizes `stream_exception ||= exception`; if already aborted only logs and returns (idempotent, lines 203-208). Otherwise: `AbortedStream.setup(self, exception)`, sets `@aborted = true`, calls `@abort_callback`, aborts threads and pids, nils `@callback`/`@abort_callback`, recursively aborts `@pair` if it responds and is not aborted (lines 220-223); `ensure` closes and unlocks `lock`.
- `stream_raise_exception(exception)` (lines 281-287): sets `stream_exception`, raises in every thread, then `self.abort`.

### close / read
- `close(*args)` (lines 233-250): with `autojoin`, closes via `super`; on exception aborts, joins, and re-raises; in `ensure` joins when the stream is closed or at EOF and no stream exception. Without `autojoin`, `super` wrapped in `rescue IOError` and skipped if already closed (i.e. double close is tolerated, not an error).
- `read(*args)` (lines 252-271): any exception becomes `@stream_exception ||= $!`, then `abort`, then re-raise. `ensure`: if `autojoin` and not closed and `eof?`, close; `join if autojoin && (closed? || @stream_exception)`.

### `ConcurrentStream.process_stream(stream, close: true, join: true, message: "process_stream", **kwargs, &block)`
(lines 289-307). Class method that setups the stream with kwargs, yields, and in `ensure` closes/joins as requested. `Aborted` and `Exception` both abort the stream and re-raise; only the log wording differs. This is the wrapper used by `open_pipe` (open/stream.rb:246) and `sort_stream` (open/stream.rb:415).

### Subtle points for doc audit
- `Open.stream_raise_exception` naming: it is `stream_raise_exception` on the module, not `raise_stream_exception`.
- `no_fail` semantics: it makes join-time failures silent **and** swallows join exceptions, but does not affect `abort`.
- `pair` propagation only happens in `abort`, never in `join`.
- `threads`/`pids` accumulate across `setup` calls; `clear` is the only way to drop them.

---

## 2. `lib/scout/open.rb` — module body, NamedStream, `Open.open`, `Open.read`

### Loading order
open.rb:1-9 requires `path`, `cmd`, then `open/final`, `open/stream`, `open/util`, `open/remote`, `open/lock`, `open/sync`. `open/final` requires only `scout/log` (open/final.rb:1), so the load graph is: log → final → stream → util → remote → lock → sync.

### `Open::NamedStream`
(open.rb:12-22) module with `filename` accessor and `digest_str`:
- if `filename` is an *unlocated* `Path`, digest on the Path itself;
- else `Misc.file_md5(filename)`.

So `digest_str` hashes file content for located paths/strings (P32-style probe confirms a 32-char md5 for a real file), and uses the path string when the Path is symbolic. `Misc.digest_str` in `misc/digest.rb:4-7` dispatches to this method first.

### `Open.file_open(file, grep=false, mode='r', invert_grep=false, fixed_grep=true, options={})` — arity 6 (module-private-ish, defined as `self.`)
(open.rb:24-34)
- mkdir of dirname only when mode contains "w" (line 25).
- `get_stream(file, mode, options)` → applies grep wrapper when grep given.
- Note: the `grep` path bypasses the gzip logic in `open`.

### `Open.open(file, options = {})` — arity 2 (+block)
(open.rb:36-80)
- IO/StringIO passthrough: given a block it yields, closes, returns result; without block returns the object unchanged (lines 37-45). `DontClose` is NOT honored on this passthrough branch (it is only handled in the later branch, line 66).
- Defaults `:noz => false, :mode => 'r'` (line 47). Extracts `mode, grep, invert_grep, fixed_grep` (line 49).
- Write modes force `options[:noz] = true` (line 51) — writing never transparently gzips.
- `file_open` → then transparent decompression, each guarded by extension test on the *filename* plus `options[:zip]/[:gzip]/[:bgzip]` overrides (lines 55-57). Detection is extension-only (`util.rb:61-74`); content sniffing is not performed (probe: `.tar.gz`→gzip yes, `.GZ`→no, `.tgz`→no, `.gz.bak`→no).
- `io.extend NamedStream; io.filename = file` (lines 59-60) — the returned stream always carries the original name.
- Block form (lines 62-76): `rescue DontClose` → `res = $!.payload` (DontClose carries a payload; see exceptions.rb:50-57 and probe P30); `rescue Exception` → `io.abort`, `io.join`, re-raise; `ensure` → close if not closed, then join. **Probe P30 shows the name is misleading**: after `DontClose` the stream is still closed in the `ensure` (line 73). `DontClose` means "return my payload now", not "leave the descriptor open".
- Without a block, returns the io (lines 77-79).

### `Open.read(file, options = {}, &block)` — arity 2(+block)
(open.rb:82-100). Delegates to `open` with block.
- With a block: iterates lines while `not f.eof?`, applies `Misc.fixutf8(l)` unless `options[:nofix]`, collects results into an Array (lines 84-91). Note the line-wise fixutf8, i.e. invalid bytes per line.
- Without block: `Misc.fixutf8(f.read)` unless `:nofix` (lines 92-97).

---

## 3. `lib/scout/open/util.rb` — grep, compression, predicates, notify, wait_for, find

### `GREP_CMD` resolution (util.rb:3-13)
`ENV["GREP_CMD"]` → `/bin/grep` → `/usr/bin/grep` → `"grep"`.

### `Open.grep(stream, grep, invert=false, fixed=nil, options={})` — arity 5 (util.rb:15-28)
- Array patterns → `TmpFile.with_file(grep * "\n", false)`, then `CMD.cmd("#{GREP_CMD} [opts] -", "-f" => f, :in => stream, :pipe => true, :post => proc{FileUtils.rm f})`. When `fixed` is not false, adds `-w -F` (word-regexp, fixed strings) (lines 17-24).
- String pattern → `CMD.cmd("#{GREP_CMD} #{invert ? '-v ' : ''} '#{grep}' -", :in => stream, :nofail => true, :pipe => true, :post => proc{ stream.force_close rescue nil })` (line 26). `:nofail` (note spelling, `nofail`, distinct from ConcurrentStream's `no_fail`) makes grep exit status 1 non-fatal; `post` forces the input closed.
- Note arity/semantics: `fixed_grep` defaults to `true` in `file_open` (open.rb:24) but `fixed` defaults to `nil` here; `FalseClass === fixed` selects the no `-w -F` variant only for Array patterns.

### Compression helpers (util.rb:30-58)
- `gzip_pipe(file)` — returns `"<(gunzip -c 'file')"` for `.gz` else `'file'` (line 30-32).
- `gunzip/gzip/bgzip(stream, options={})` — all `CMD.cmd('zcat'|'gzip'|'bgzip', ...)` with defaults `:pipe => true, :no_fail => true, :no_wait => true, in: stream` (lines 38-51). These return CMD streams.
- `unzip(stream, options={})` — defaults `"-p" => true, :pipe, :no_fail, :no_wait, in: stream`; buffers the whole input via `TmpFile.with_file(stream.read)` then `StringIO.new(CMD.cmd("unzip '{opt}' #{filename}", options))` (lines 53-58). **Not streaming**: full materialization in memory plus a temp file.
- `bgunzip(stream)` — arity 1 only; body is `Bgzf.setup stream` (lines 34-36). `Bgzf` is **not defined anywhere in this gem** (probe P29: `NameError: uninitialized constant Open::Bgzf` when called, `defined?(Bgzf)` → not defined). Any doc claiming bgzip support works out of the box is wrong; it requires an external gem.

### Extension predicates (util.rb:60-78)
`gzip?` → `/\.gz$/`, `bgzip?` → `/\.bgz$/`, `zip?` → `/\.zip$/`, `compressed?` = any of them. All operate on the *string/path*, case-sensitively; `.tgz`/`.GZ` are not detected (probe in §2).

### Stream predicates (util.rb:80-86)
- `is_stream?(obj)` → `IO === obj || StringIO === obj`.
- `has_stream?(obj)` → `obj.respond_to?(:stream)`.

### `Open.notify_write(file)` — arity 1 (util.rb:89-109)
Notification protocol: if `file + '.notify'` exists, read it as a key; if the key contains `@` it is treated as an email → `Misc.send_email(from,to,subject,message,:files=>[file])` with subject `"Wrote <file>"`; otherwise `Misc.notify("Wrote <file>", nil, key)`; then the `.notify` file is removed. All failures are swallowed and logged (`rescue → Log.exception`, lines 105-108). Probe P28 shows that on this repo state both `Misc.notify` and `Misc.send_email` are **not defined** (NoMethodError logged, no raise), i.e. notify_write is effectively a no-op hook unless another gem defines them.

### Other predicates/paths (util.rb:110-185)
- `broken_link?` (111-113): `File.symlink?(path) && !File.exist?(File.readlink(path))`.
- `exist?` alias of `exists?` (115).
- `exist_or_link?` (117-119).
- `writable?` (121-130): symlink → directory writability; existing → file; else parent dir.
- `realpath` (132-135).
- `list(file)` (137-140): `file.produce_and_find` for Path, then `Open.read(file).split("\n")`.
- `wait_for(path, timeout: 10)` (142-171): **requires the `listen` gem lazily** (line 147); uses `Listen.to(dir)` and pushes `:found` when the *absolute* path string appears in `added`; pops with `Timeout.timeout(timeout)`; returns `true` on pop, `false` on Timeout::Error, listener stopped in ensure. Note the listener pushes only for exact string equality against `path`, which for a relative `path` never matches `added` entries (they are absolute), so a relative path would always time out. Subtle trap.
- `find(path)` (173-184): Step→`.path`, Path→`.find`; remote paths returned unchanged; existing → `realpath`; else `File.expand_path`.

---

## 4. `lib/scout/open/stream.rb` — pipes, consume, sensible_write, tee, sort, collapse, monitor

Constants and dirs (stream.rb:1-17): `Open::BLOCK_SIZE = 1024*8`. `sensible_write_lock_dir` defaults to `Path.setup("tmp/sensible_write_locks").find` and `sensible_write_dir` to `Path.setup("tmp/sensible_write").find` — i.e. relative to the Scout tmp root (`$HOME/.scout/tmp/...`), resolved once and cached (probe P32 shows `/home/mvazque2/.scout/tmp/sensible_write{,_locks}`).

### `Open.consume_stream(io, in_thread=false, into=nil, into_close=true, &block)` — arity 4(+block) (stream.rb:19-89)
- Early returns: `Path === io` (line 20), non-`read`-ers (line 21), already closed → just join (lines 23-26).
- `in_thread: true` spawns `Thread.new` named `"Consumer <fingerprint>"` that recursively calls `consume_stream(io,false,into,into_close)`; the thread is pushed onto `io.threads` and returned (lines 28-38). `Thread.pass until consumer_thread["name"]` ensures naming before returning.
- Inline path: `into` may be a String path (dir created, file opened `'w'`) or an object with `<<`; `into_close` is only applied when `into` responds to `close` (lines 47-55).
- Loop: `while c = io.read(BLOCK_SIZE)` → `into << c`, tracking `last_c`, `break if io.closed?` (lines 57-61). Then join, close io, join/close into if `into_close`, call the block, return `last_c` (lines 63-69).
- `rescue Aborted` (70-75): marks `Thread.current["exception"]=true`, aborts io, closes into, **removes the into file**, does *not* re-raise.
- `rescue Exception` (76-87): picks `io.stream_exception` if present else `$!`, aborts io with it, closes into, removes into file, **re-raises** (probe P31: `consume w/ exception: ProcessFailed into2 removed: true`).
So: Aborted is swallowed; everything else propagates. Both delete the partial target file.

### `Open.sensible_write(path, content=nil, options={}, &block)` — arity 3(+block) (stream.rb:91-168)
Lifecycle: exists-and-not-force → just consume the content stream and return (lines 94-97).
- `force` from options (line 92); `lock_options = IndiferentHash.pull_keys options.dup, :lock` (may be a Hash under `:lock`) (lines 99-100).
- Temp names: `tmp_path = TmpFile.tmp_for_file(path, {:dir => Open.sensible_write_dir})` and `tmp_path_lock = TmpFile.tmp_for_file(path, {:dir => Open.sensible_write_lock_dir})` (lines 101-102). Both use the slash-replaced basename scheme (probe P32/P19: `·a·b·data.txt`).
- `options[:lock] == false` (FalseClass) disables the lock file (line 104).
- Everything runs inside `Open.lock tmp_path_lock, lock_options do ... end` (line 106); second exists-check inside the lock logs a warning and consumes (lines 108-110).
- Content dispatch (lines 116-134): block → `File.open(tmp_path,'wb',&block)`; String → write; IO/StringIO/File → nested `Open.write(tmp_path)` loop copying `BLOCK_SIZE` chunks, breaking when `content.closed? || content.eof?`; else `write_file` if defined, else `to_s`.
- Publish: `Misc.insist { Open.mv tmp_path, path, lock_options }` inside a rescue that swallows the error *if the target now exists* (lines 136-142); then `Open.touch`, then `content.join` (unless Path or already joined), then `Open.notify_write(path)` (lines 144-147).
- `rescue Aborted` (148-151): logs, aborts content, removes the *published* path, **does not re-raise** (probe P33).
- `rescue Exception` (152-157): if content is an `AbortedStream` with an exception, that exception is re-raised instead of `$!`; aborts content, removes path, re-raises (probe P25 shows a plain `ProcessFailed` propagating and the file removed).
- `ensure` (160-165): removes `tmp_path`, unlocks `lock_options[:lock]` if it is a `Lockfile` and locked.
Guarantee: the target file only appears via the two-step temp+rename, and on any failure neither a partial file nor the temp remains.

### Pipes (stream.rb:170-213)
- `PIPE_MUTEX = Mutex.new`, `OPEN_PIPE_IN = []` global registry of write ends (170-172).
- `Open.pipe` (173-183): prunes closed entries, creates `IO.pipe` under the mutex, registers `sin` in `OPEN_PIPE_IN`, logs `Creating pipe ...`, returns `[sout, sin]`.
- `Open.with_fifo(path=nil, clean=true, &block)` (185-195): path defaults to `TmpFile.tmp_file`; `File.rm path if clean && File.exist?(path)` (line 189) — **`File.rm` does not exist in this Ruby version/gem** (probe P32 confirms `File.respond_to?(:rm)` → false), so passing an existing path with `clean=true` raises `NoMethodError` before `File.mkfifo`; with the default nil path it works because the file does not exist yet. Also `erase` cleanup uses `FileUtils.rm`. Docs claiming `with_fifo` cleans an existing fifo are wrong.
- `Open.release_pipes(*pipes)` (197-203): closes (unless closed) the given pipes under `PIPE_MUTEX`.
- `Open.purge_pipes(*save)` (205-213): closes every registered `OPEN_PIPE_IN` except those in `save` — used in the fork branch of `open_pipe` so the child does not keep inherited write-ends open (line 224).

### `Open.open_pipe(do_fork=false, close=true, &block)` — arity 2(+block, required) (stream.rb:215-262)
- Raises `"No block given"` if no block (line 216).
- Thread mode (default): both ends are `ConcurrentStream.setup`-ed as `:pair` of each other (lines 241-242); a thread runs `ConcurrentStream.process_stream(sin, :message => "Open pipe") { ... yield sin ... }` with name `"Pipe input <in> => <out>"` and `report_on_exception = false` (lines 244-253). Both `sin.threads` and `sout.threads` get `[thread]` (lines 255-256). `Thread.pass until thread["name"]` (258). Returns `sout`.
- Fork mode (`do_fork: true`): child purges pipes except `sin`, closes `sout`, yields, closes `sin` if `close`; exceptions log and `Kernel.exit!(-1)`; success `Kernel.exit! 0` (lines 220-235). Parent closes `sin` and returns `ConcurrentStream.setup sout, :pids => [pid]` (lines 236-238) — note `:threads` is empty here, joining reaps the pid via `join_pids`.
Probe P26: default returns a ConcurrentStream; reading to EOF auto-joins (threads joined after read when autojoin default not set — the observed `joined: true` came from `close`+`join` in the `read` ensure path).

### `Open.tee_stream_thread_multiple(stream, num=2)` — arity 2 (stream.rb:264-372)
Data structure: `num` pipe pairs; a single *splitter thread* copies `BLOCK_SIZE` chunks from `stream` into every `sin`, honoring a `skip` array when a downstream end raised `IOError` (lines 282-297). The splitter is named `"Splitter <fingerprint>"`.
- Returns the array of read-ends `out_pipes`; the first is the "main" pipe with `:threads => [splitter_thread], :filename, :autojoin => true` (line 346); the rest get `:filename` and the same thread but **no autojoin** (lines 348-350).
- `main_pipe.callback` joins the source and closes the remaining write ends (352-362); `main_pipe.abort_callback` aborts the source (if ConcurrentStream) and all other outputs (364-369).
- Abort path: `rescue Aborted, Interrupt` aborts stream, deletes the splitter from each `sout.threads`, aborts each `sout`, closes all `sin`, re-raises (301-314). Generic `Exception` does the same but wraps in `begin/rescue/ensure` that always closes the `sin`s before re-raising (315-339).
- `tee_stream_thread(stream)` = `tee_stream_thread_multiple(stream, 2)` (374-376); `tee_stream(stream)` aliases it (378-380). So `tee_stream` returns an **array of two streams** (main + copy) — probe P31 destructured `m, o = Open.tee_stream(base)` and both delivered identical content.

### `Open.read_stream(stream, size)` — arity 2 (stream.rb:382-410)
Two definitions exist; the second (401-410) wins: builds `str` in a loop `while str.length < size`, `more = stream.read(missing)`, `raise ClosedStream if more.nil?`. The earlier IO.select-based definition (382-399) is dead code. Docs describing select/poll behavior are describing dead code.

### `Open.sort_stream(stream, header_hash:"#", cmd_args:nil, memory:false)` (stream.rb:412-440)
- `cmd_args` defaults to `'-u'` (line 413).
- Emits leading lines starting with `header_hash` directly (416-420), then pipes the remainder into an inner `open_pipe` whose consumer writes into `env LC_ALL=C sort <cmd_args>` via `CMD.cmd(..., :in => line_stream, :pipe => true)` unless `memory:` (lines 428-435); memory mode sorts in-Ruby with `read.split("\n").sort` (429-431).
- Note `LC_ALL=C` is forced for the external sort (line 433).
- A commented-out pure-Ruby implementation sits at lines 442-444.

### `Open.collapse_stream(s, line:nil, sep:"\t", header:nil, compact:false, &block)` (stream.rb:446-502)
- Optional `header` line emitted first; `line ||= s.gets` seeds the first row (450-452).
- Splits `line.chomp.split(sep, -1)` into `key, *parts`; groups consecutive rows with the same key; values accumulate as `existing + "|" + part`, i.e. **pipe-joined**, and padding uses `"|"` + `""` when a later row has fewer fields (lines 456-478). `compact: true` replaces pipe-joins with plain overwrite of empty fields (464-467) and skips empty parts.
- With a block, the block transforms the accumulated parts array and `[key, res] * sep` is written (483-488, 495-497); without, `[key, parts].flatten * sep` (487, 499).
- Probe P31: `"k1\tv1\nk1\tv2\nk2\tv3\n"` → `"k1\tv1|v2\nk2\tv3\n"`.

### `Open.line_monitor_stream(stream, &block)` (stream.rb:504-525)
Tees the stream; a monitor thread reads lines from the monitor side and calls the block per line; on error it aborts the monitor, closes/joins, and `out.raise $!`. Returns `out` (the non-monitor side) with `:threads => [monitor_thread]`. The block sees each raw line **including** the trailing newline (probe P31 `seen: []` was because the monitor thread had not run before we read — see "gotcha" below).

Gotcha worth documenting: `line_monitor_stream` returns immediately and the monitor thread runs concurrently; in probe P31 the block had not yet fired when the consumer read, so `seen` was empty even though `out` delivered all lines. Docs claiming synchronous observation are wrong.

---

## 5. `lib/scout/open/lock.rb` — `Open.lock`, `Open.init_lock`

(open/lock.rb:1-68)

- `Open.init_lock` (7-13): sets class knobs on `Lockfile`: `refresh = 2`, `max_age = 30`, `suspend = 4`; called at load time (line 13). Probe P32 confirms effective values: `refresh=2 max_age=30 suspend=4 retries=nil timeout=nil poll_retries=16 dont_clean=false poll_max_sleep=0.08 sleep_inc=2 min_sleep=2 max_sleep=32`. (Note these override the file defaults `3600/1800/8` at lock/lockfile.rb:64-74.)
- `Open.lock(file, unlock=true, options={})` — arity 3 (15-67):
  - `Open.lock(hash)` overload: `unlock, options = true, unlock if Hash === unlock` (line 16) — so `Open.lock(:x => 1){...}` is legal.
  - `return yield if file.nil? and not Lockfile === options[:lock]` (line 17): nil lock path means no locking at all, unless an explicit Lockfile object is passed in options.
  - `Lockfile === file` → use it directly (19-20).
  - Otherwise ensure the target's directory exists (22-23) and select lock location: `options[:lock]` may be a `Lockfile` (use as-is), `FalseClass` (no lockfile, and `unlock=false`), `Path/String` (lock path from option), else `<file>.lock` sibling (25-37).
  - Acquire: `lockfile.lock unless lockfile.nil? || lockfile.locked?`; `rescue Aborted, Interrupt → raise LockInterrupted` (40-44). So Ctrl-C/aborts surface as `LockInterrupted` (a `TryAgain` subclass, exceptions.rb:73).
  - Body: `res = yield lockfile` (line 49) — the block receives the lockfile object.
  - `rescue KeepLocked` → `unlock = false; res = $!.payload` (50-52): raising `KeepLocked` (a `DontPersist` subclass, exceptions.rb:59) returns its payload from `Open.lock` and leaves the lock held.
  - `ensure` unlocks if `unlock` and `lockfile.locked?`, logging (never raising) unlock failures (53-63).
  - Probe P30: `KeepLocked` gives `result="value-kept"` and the lock file is *not* deleted; contended second locker blocks (probe printed "never" only after the first released).
  - Probe P22: with the default path, `Open.lock` yields a `Lockfile` object (`Lockfile:/tmp/.../data.txt.lock`), removes the lock file after the block, and the `.lock` sibling itself never appears as a leftover in the target dir — the actual lock artifact is a dotfile in the *same* directory (see §6 tmpnam), removed on unlock.

---

## 6. `lib/scout/open/lock/lockfile.rb` — vendored `Lockfile` (Ara T. Howard, v2.1.8, modified)

(open/lock/lockfile.rb:1-587). Guarded by `unless(defined?($__lockfile__) or defined?(Lockfile))` (line 5), so it is not re-defined if another gem already provides `Lockfile`.

### Class constants & error taxonomy (lines 11-28)
`LockError < StandardError` with subclasses `StolenLockError, StackingLockError, StatLockError, MaxTriesLockError, TimeoutLockError, NFSLockError, UnLockError` — **these are top-level `Lockfile::…` classes, not nested under Open**.

### Tunables (lines 60-114, values probed in P32 after `Open.init_lock`)
`HOSTNAME`, `DEFAULT_RETRIES=nil`, `DEFAULT_TIMEOUT=nil`, `DEFAULT_MAX_AGE=3600` (overridden to 30 by init_lock), `DEFAULT_SLEEP_INC=2`, `DEFAULT_MIN_SLEEP=2`, `DEFAULT_MAX_SLEEP=32`, `DEFAULT_SUSPEND=1800` (overridden to 4), `DEFAULT_REFRESH=8` (overridden to 2), `DEFAULT_DONT_CLEAN=false`, `DEFAULT_POLL_RETRIES=16`, `DEFAULT_POLL_MAX_SLEEP=0.08`, `DEFAULT_DONT_SWEEP=false`, `DEFAULT_DONT_USE_LOCK_ID=false`, `DEFAULT_DEBUG = ENV['LOCKFILE_DEBUG'] || false`. All exposed as class-level accessors (78-92) initialized by `Lockfile.init` (94-113) and per-instance via `getopt` (546-551).

`Lockfile.create(path, *a, &b)` (147-168): one-shot constructor with a fast, non-blocking option set (`retries 0`, `min_sleep 0`, `max_sleep 1`, `sleep_inc 1`, `max_age nil`, `suspend 0`, `refresh nil`, `timeout nil`, `poll_retries 0`, `dont_clean true`, `dont_use_lock_id true`); `LockError` is translated to `Errno::EEXIST`. Used by `create_tmplock`.

### `SleepCycle` (lines 30-58)
An `Array` of sleep durations built as min, min+inc, … capped at max; `next` cycles; `reset` restarts at index 0. Raises `RangeError` for bad min/max/inc.

### `initialize(path, opts = {}, &block)` (179-212)
Reads every knob via `getopt` (symbol/string/`to_s.intern` keys accepted, 546-551), builds `@semaphore = Mutex.new` and `@sleep_cycle`; `@clean = @dont_clean ? nil : Lockfile.finalizer_proc(@path)` (203); `lock(&block)` if a block is given (211). Note the typo `@refrsher = nil` (209) is harmless dead state.

`finalizer_proc(file)` (170-177): a `lambda` that `File.unlink`s the lock when the object is GC'd **and the pid is unchanged**; registered with `ObjectSpace.define_finalizer` only in the no-block path (line 330). So an unreferenced Lockfile cleans up at exit via GC, and `unlock` undefines it (409).

### `synchronize` (218-226)
`lock; yield; ensure unlock` — requires a block.

### `lock` (228-339) — the core algorithm
- `StackingLockError` if already `@locked` (229).
- `sweep unless @dont_sweep` (231) — reaps stale dot-locks from dead local processes (see below).
- `attempt { ... }` (235; the `attempt`/`try_again!`/`give_up!` machinery at 566-579 uses `catch/throw 'attempt'`).
- Inside `create_tmplock` (470-486) a *temporary* lock file is created via `tmpnam @dirname`; if `dont_use_lock_id` is false, the lock-id payload is written into it (474-480).
- `Timeout.timeout(@timeout)` wraps the whole acquisition (240).
- Acquisition: `File.link tmp_path, @path` — **hard link, atomic on NFS** (250); `Errno::ENOENT` → `try_again!` (251-253). Then `lstat` both and require identical `rdev`+`ino` (`StatLockError` otherwise) (254-256). On success `@locked = true` (258).
- Poll loop: up to `@poll_retries` attempts sleeping `min(rand(poll_max_sleep), poll_max_sleep)` between them (259-268).
- Outer retry loop (270-297): increments `n_retries`, consults `validlock?`:
  - `true` (a live lock exists): raise `MaxTriesLockError` when `@retries` exceeded; else `sleep @sleep_cycle.next` and retry (274-280).
  - `false` (stale lock): `File.unlink @path`, set `@thief = true`, warn `"stolen by <pid> at <time>"`, then `sleep @suspend` (281-291). With `Open.init_lock`'s `max_age=30`, locks older than 30 s are considered stale and stolen.
  - `nil` (no lock file at all): raise `MaxTriesLockError` if retries exhausted, else just retry (292-295).
- `Timeout::Error` → `TimeoutLockError` (299-300). `Errno::ESTALE`/`EIO` → `NFSLockError` (333-34).
- With a block: `@refresher` (see below) is started, block yielded with `@path`; `StolenLockError` during the block sets `stolen` and skips the automatic unlock (304-327).
- Without a block: refresher started, finalizer registered, returns `self` (328-332).

### `sweep` (341-377) — zombie handling
Globs `File.join(@dirname, ".*lck")`, parses `.<host>_<pid>_...` names (regex `%r/^\s*\.([^_]+)_([^_]+)/o`), keeps only entries whose host prefix matches `HOSTNAME` and pid is numeric, and removes them when `alive?(pid)` is false (via `Process.kill 0`, 379-387, `Errno::ESRCH` → dead). So: **dead-process cleanup happens only for the local host**, at the moment a new lock is attempted, for dot-locks matching this hostname. This is the "zombie/reaper" story for this subsystem.

### `unlock` (389-411)
Requires `@locked` (`UnLockError` otherwise); kills and clears the refresher; `File.unlink @path` (`Errno::ENOENT` → `StolenLockError`, meaning someone else removed it); in `ensure` clears `@thief`/`@locked` and undefines the finalizer.

### `new_refresher` (413-436)
A thread that every `@refresh` seconds: `touch`es the lock path (keeping it "fresh" so `validlock?`'s max_age does not steal it) and, unless `dont_use_lock_id`, re-reads the lock-id via the semaphore and compares to the stored one; on mismatch or error it raises `StolenLockError` in the *owner* thread and exits (429-433).

### `validlock?` (438-450)
With `@max_age`: `uncache` then `(Time.now - File.stat(@path).mtime) < @max_age` (ENOENT → nil). Without: `File.exist?` → true else nil. `uncache` (452-468) defeats mtime caching by hard-linking the lock to a scratch name and re-applying mode/utimes.

### Lock file format (470-519)
- Acquired lock artifact: `<target>.lock` — a **hard link** to the temporary lock file, i.e. the same inode. Removing the temp name leaves the `.lock` as the only link.
- Temp/dot-lock name: `tmpnam(dir, seed = File.basename($0))` → `"%s%s.%s_%d_%s_%d_%d_%d.lck" % [dir, File::SEPARATOR, HOSTNAME, pid, seed, sec, usec, rand(sec)]` (521-528). Matches the `.<host>_<pid>_…` pattern `sweep` expects.
- Optional lock-id payload (only when `dont_use_lock_id` is false, which is **not** the case for `Lockfile.create` but *is* the default for `Lockfile.new` since `DEFAULT_DONT_USE_LOCK_ID=false`): 4 lines `host: <hostname>\npid: <pid>\nppid: <ppid>\ntime: <YYYY-mm-dd HH:MM:SS.uuuuuu>\n` (`dump_lock_id` 504-507, `gen_lock_id` 488-495, `load_lock_id` 509-519 which parses any `key: value` lines). Probe P22 captured the exact 4-line contents while held.
- `create(path)` (530-540): `open path, File::WRONY|File::CREAT|File::EXCL, 0644` under `File.umask 022` — exclusive creation.

### Misc API
`to_str`/`to_s` → `@path` (553-556); `trace` (558-560) prints to STDERR when `debug`; `errmsg` (562-564); `attempt`/`try_again!`/`again!`/`give_up!` (566-579). Module-level `Lockfile(path, *a, &b)` convenience constructor (582-584) and `$__lockfile__ = __FILE__` (586).

---

## 7. `lib/scout/open/remote.rb` — wget/ssh/scp + URL cache

(open/remote.rb:1-151)

### Cache location and naming
- `Open.remote_cache_dir` — class accessor defaulting to `Path.setup("var/cache/open-remote/").find` (lines 6-12), i.e. `$HOME/.scout/var/cache/open-remote/` (probe P23/P32; note the trailing slash in the literal is collapsed by `File.join`).
- `Open.digest_url(url, options = {})` (108-111): `Misc.digest([url, [url, options.values_at("--post-data","--post-data="), post_file_sorted_lines]])`; `--post-file` content is read, split on newlines, sorted and re-joined (so two post-files with the same lines in different order share a cache entry). Probe P23/P29: `--post-data` changes the digest; post-file line order does not.
- `cache_file(url, options)` → `File.join(remote_cache_dir, digest_url(url, options))` (113-115). There is **no extension and no TTL/mtime check**: `in_cache` (117-124) is a plain `File.exist?`; invalidation is only via `remove_from_cache(url, options)` (126-133) or passing `:force`/`:nocache` at fetch time.
- `add_cache(url, data, options)` → `Open.sensible_write(filename, data, :force => true)` (135-138) — every cache write is forced, uses the temp+rename machinery.
- `open_cache(url, options)` → `Open.open(filename)` (140-143).

### Predicates
- `remote?(file)` → `/^(?:https?|ftp|ssh):\/\//` (14-16).
- `ssh?(file)` → `/^ssh:\/\//` (18-20).

### `Open.ssh(file, options = {})` (22-31)
Parses `ssh://<server>:<path>`; `localhost` opens the local file directly; otherwise `CMD.cmd("ssh '<server>' cat '<path>'", :pipe => true, :autojoin => true)`.

### `Open.wait(lag, key = nil)` (33-42)
Rate limiter keyed on `key` using the class-level `LAST_TIME` hash: sleeps until `LAST_TIME[key] + lag` if within the window, then records `Time.now` (note: records *after* sleeping, i.e. end time).

### `Open.wget(url, options = {})` (44-97)
- Accepts `options[:wget_options]` as an alternate options hash (45).
- Cache hit: `in_cache` consulted unless `options[:force]` or `options[:nocache]`; a hit returns `file_open(cache_file)` immediately (46-48).
- Defaults `"--user-agent=" => 'rbbt'`, `:pipe => true`, `:autojoin => true` (51).
- `wait(options[:nice], options[:nice_key]) if options[:nice]` (53) then the nice keys are deleted (54-55).
- Extracted (deleted) keys: `pipe, quiet, post, cookies, nocache` (57-61).
- `options["--quiet"] = quiet if options["--quiet"].nil?` (63); `options["--post-data="] ||= post if post` (64).
- Cookies: sets `--save-cookies`, `--load-cookies` to the given file plus `--keep-session-cookies` (66-70).
- stderr routing: `options['stderr']` if given, else `false` when quiet, else `nil` (72-79).
- Executes `CMD.cmd("wget '#{url}'", wget_options)` where `-O -` is added unless `--output-document` was given (81-87). Probe P23 shows the final options hash passed to `CMD.cmd` for a quiet, cookie'd, POST fetch, including `"-O"=>"-"`, `:pipe=>true`, `:stderr=>false`.
- Result handling: `nocache` that is not the string `'update'` returns the live `io`; otherwise `add_cache(url, io, options)` then `open_cache(url, options)` — i.e. **even `nocache: 'update'` refreshes the cache and then reads from it** (88-93).
- Any failure → `OpenURLError "Error reading remote url: <url>.\n<original>"` (94-96) — the original exception becomes message text.

### `Open.download(url, file)` (99-106)
`CMD.cmd_log(:wget, "'#{url}' -O '#{file}'")`; on failure removes the partial file and re-raises. Note the mixed arity/keyword style of `CMD.cmd_log(:wget, "…")`.

### `Open.scp(source_file, target_file, target: nil, source: nil)` (145-150)
Runs `ssh <target> mkdir -p <dir>` first, then composes `host:` prefixes when `target`/`source` are given without them, and finally `CMD.cmd_log("scp -r '<source_file>' <target_file>")`.

---

## 8. `lib/scout/open/sync.rb` — rsync wrapper

(open/sync.rb:1-84)

### `Open.rsync(source, target, options = {})` — arity 3 (lines 3-79)
Options processed (4-5): `:excludes, :files, :hard_link, :test, :print, :delete, :source, :target, :other` (note `:source`/`:target` are the *server* names, everything else goes to `other`).
- Default excludes `%w(.save .crap .source tmp filecache open-remote)` (7); a String excludes value is split on `/,\s*/` unless it already contains `--exclude` (8).
- Directory normalization: trailing `/` forced on both sides when source is a directory or ends with `/` (10-13).
- Self-sync guard: same source and target with no servers logs a warning and returns (15-18).
- URI construction: `target_uri = [target_server, "'target'"] * ":"` when `target_server` else quoted plain (20-30) — note the **single quotes are added around the path but not around the `host:` prefix**.
- Pre-creates the target directory via `ssh <target_server> mkdir -p` or `Open.mkdir` (33-37).
- `rsync_args = %w(-avztHP --copy-unsafe-links --omit-dir-times)` (42); `--link-dest '<source>'` appended when `hard_link` and source is local (43); one `--exclude '<e>'` per exclude (44); `-nv` when `test` (45).
- `:files` is written to a `TmpFile.tmp_file 'rsync_files-'` temp file (newline-separated) and passed as `--files-from=` (46-50).
- Final command string: `rsync <args> <source_uri> <target_uri>` plus `other` (String appended verbatim or Array joined) (52-58); `delete && !files` appends `" && rm -Rf #{source}"` to the *shell* command (59).
- `:print => true` returns the command string without executing (61-63); otherwise `CMD.cmd_log(cmd, :log => Log::HIGH)` (64).
- `delete` with `files`: files are removed individually with `Open.rm` (directories skipped first pass) and then empty directories are `FileUtils.rmdir`-ed only when `Dir.glob(dir).empty?` — note the empty-glob test uses the glob pattern, not existence (66-77).

### `Open.sync(...)`
Ruby-3 forwarding alias for `rsync` (81-83). Any doc listing `Open.sync` as separate behavior is wrong.

---

## 9. `lib/scout/open/final.rb` — file primitives, write/mv/rm/ln

(open/final.rb:1-224)

### `Open.get_stream(file, mode='r', options={})` (3-12)
Streams/objects with `.stream` pass through; `Path#find`; then **`ssh://` before general remote** (`Open.ssh(file, options)` if `ssh?`, then `Open.wget(file, options)` if `remote?`), else `File.open(File.expand_path(file), mode)`. This is the single dispatch point for remote reads; `Open.open` reaches it via `file_open`.

### `Open.file_write(file, content, mode='w')` (14-24)
`File.open` + `flock(LOCK_EX)` + write + `flock(LOCK_UN)` + close-in-ensure. Cross-process safety for plain writes is POSIX flock, *not* Lockfile.

### `Open.write(file, content=nil, options={}, &block)` — arity 3(+block) (26-71)
Defaults `:mode => 'w'`; `Path#find(options[:where])`; mkdir of dirname (29-32).
- Block form: opens, yields, closes; on `Exception` removes the file and re-raises (35-46). Probe P28: raising `ProcessFailed` inside the block propagates and the file is removed.
- `content.nil?` → writes the empty string (47-48) — i.e. `Open.write(file)` creates/truncates the file.
- String → `file_write` (flock path).
- IO/StringIO → reads `Open::BLOCK_SIZE` chunks under flock; on exception removes and re-raises; then closes and joins the source (51-65).
- Anything else → `raise "Content unknown <fingerprint>"` (66-67). Probe P28 confirmed `Open.write(f, 42)` raises `RuntimeError`.
- Ends with `notify_write(file)` (70).

### `Open.append(file, content, options={})` (73-77)
**Instance method, not `self.`** — `Open.append(...)` raises NoMethodError; it is only reachable because `Open` is a module whose instances do not exist (probe P28: `Open.respond_to?(:append)` → false, `Open.instance_methods.include?(:append)` → true). Any doc showing `Open.append` is wrong; the idiom is `Open.write(file, content, :mode => 'a')`.

### `Open.mv(source, target, options={})` (79-87)
Two-step rename through `.tmp_mv.<basename>` in the target directory; directories created. Note: unlike `sensible_write`, this is not lock-protected.

### `Open.rm(file)` / `rm_rf` / `touch` / `mkdir` / `mkfiledir` (89-117)
- `rm` also removes broken symlinks (`Open.broken_link?`) (89-92) — probe P28.
- `mkdir` is mkdir_p-if-missing; `mkfiledir` only creates the *parent* dir.

### `cp`, `directory?`, `exists?`, `ctime`, `mtime`, `size` (119-167)
- `cp` removes the target first, then `cp_r`.
- `mtime` (143-162): for symlinks or files with `nlink > 1`, first consults `file + '.info'` (a `Persist.memory`-cached `Step::SERIALIZER` blob with a `[:done]` flag, only when `defined?(Step)`); returns the flag's truthiness-derived `done` if set, else falls back to the realpath's mtime; `nil` when the file does not exist; any error → `nil`. This is the "done-file" integration point with the Step layer, and a likely spot for docs to overstate.
- `size` is `File.size` (no exception guard).

### Links (169-222)
- `ln_s(source, target, options={})`: into a directory appends basename; removes existing target (file or symlink) then `ln_s`.
- `ln`: resolves symlink source via `File.realpath`, removes target, hard link.
- `ln_h`: `CMD.cmd("ln -L 'src' 'dst'")` (dereference-and-hardlink), falls back to `cp -L` on `ProcessFailed` with a debug log (191-203) — probe P28: creates a real hard link when possible.
- `link`: tries `ln`, falls back to `ln_s` on any error, returns nil (205-213).
- `link_dir(source, target)`: `FileUtils.cp_lr` (hard-linked directory copy).
- `same_file(file1, file2)`: `File.identical?`.

---

## Files covered

- [x] lib/scout/concurrent_stream.rb
- [x] lib/scout/open.rb
- [x] lib/scout/open/util.rb
- [x] lib/scout/open/stream.rb
- [x] lib/scout/open/lock.rb
- [x] lib/scout/open/lock/lockfile.rb
- [x] lib/scout/open/remote.rb
- [x] lib/scout/open/sync.rb
- [x] lib/scout/open/final.rb

## Cross-cutting notes for the doc audit

1. **Dead code**: the first `Open.read_stream` (stream.rb:382-399) and the commented `sort_stream` (442-444).
2. **Misleading names**: `DontClose` still closes; `Open.append` is not a class method; `sync` is `rsync`.
3. **Extension-only compression detection**, case-sensitive; `.tgz`, `.GZ`, `.gz.bak` undetected.
4. **`Bgzf` missing** → `Open.bgunzip`/`:bgzip` path unusable without an external gem.
5. **Lock semantics**: `.lock` sibling is a hard link to a dot-temp; stale stealing after `max_age` 30 s with 4 s suspend; local-only sweep of dead-process dot-locks; refresher touches every 2 s.
6. **`Open.notify_write`** depends on `Misc.notify`/`Misc.send_email` which this gem does not define — silently logged as errors.
7. **`Open.with_fifo`** cannot clean a pre-existing path (`File.rm` NoMethodError).
8. **URL cache** has no TTL, no extension, keyed by a digest that sorts `--post-file` lines; `nocache: 'update'` still refreshes the cache.
9. **`Open.mtime`** consults `<file>.info` Step blobs for hard-linked/symlinked files — not a plain stat.
10. **`consume_stream` swallows `Aborted`** (and deletes the partial target) while re-raising everything else; `sensible_write` likewise swallows `Aborted`.
11. **`line_monitor_stream`** block runs concurrently with consumption (may not have run when the consumer finishes reading).
