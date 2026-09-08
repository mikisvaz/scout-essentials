# Handling Streams

When `CMD.cmd(..., :pipe => true)` or `Open.open_pipe` hands you an IO, that
object has been extended with `ConcurrentStream`: it carries the producer
thread(s) and pid(s) that feed it, plus callbacks and an abort protocol. This
page is the user-facing contract; the internals are in
[Streaming Model](../developer/StreamingModel.md).

## Anatomy

```ruby
io = CMD.cmd('grep x', :pipe => true)
io.threads        # => [input thread, stderr thread, ...]  (producer side)
io.pids           # => [pid]
io.callback       # => nil or a Proc run on successful join (see :post)
io.abort_callback # => nil or a Proc run on abort(exception)
io.std_err        # => "" (filled by :save_stderr)
io.log            # => last stderr line (pipe mode, when :log => true)
io.lock, io.lockfile, io.pair, io.next, io.filename, io.autojoin, io.no_fail
```

Attributes come from `ConcurrentStream.setup` (concurrent_stream.rb:12-70) and
`CMD.cmd` sets `:pids`, `:threads`, `:autojoin` (default `no_fail`) and
`:no_fail` on the returned stream. `exit_status` exists but is *not* reliable
after a normal read+join — it stays `nil` because only `join_pids` sets it, and
that method empties `pids` when it runs; see
[Running Commands](RunningCommands.md).

## `close` vs `join` vs abort

- **`join`** is the finishing move: `join_threads`, `join_pids`, raise
  `stream_exception` if one is set, run `join_callback` (the composed callback),
  close, release the lock, and mark `joined?`. It never joins `@pair` — the
  other end of an internal pipe is the producer's business.
- **`close`** on an `autojoin` stream performs `super` (the plain IO close) and
  then joins if the stream is at EOF; with `autojoin` off it just closes.
  Closing early while a producer still writes raises `IOError`/`Errno::EPIPE`
  in the producer, which the stream converts to an abort — so for an early,
  deliberate stop use `abort`, not `close`.
- **`abort(exception)`** is the safe early close: it marks the stream aborted,
  extends it with the `AbortedStream` marker, runs `abort_callback`, interrupts
  and joins every producer thread, sends `SIGINT` to every pid, clears the
  callbacks, **propagates to `@pair`** (aborting the other pipe end), closes and
  unlocks. It is idempotent (a second call only logs). Threads get
  `Aborted.new` raised in them, so producer bodies should rescue `Aborted`.
- **`force_close` does not exist** in this repo. The only reference is a dead
  `respond_to?` guard inside `Open.grep` (open/util.rb:26); a plain IO has no
  such method (`IO#respond_to?
  (:force_close) => false`). The early-close tool is `abort`.

Consumers should follow this rescue contract:

```ruby
begin
  data = Open.consume_stream(stream, false, dst)   # or .each / .read
rescue Aborted, AbortedStream
  # deliberate stop: log and move on; the stream is already aborted+closed
rescue ConcurrentStreamProcessFailed => e
  # a producer failed; e.pid / e.msg available
end
```

`AbortedStream` is a *marker module* (`concurrent_stream.rb:4-9`) —
`AbortedStream.setup(obj, exception)` extends an object so later code can read
`obj.exception` and recover the real cause; `sensible_write` uses exactly that.

## Callbacks

- `stream.add_callback(&block)` **composes**: it wraps the existing callback so
  the *new* block runs *after* the old one (observed order
  `[:first, :second]`). `ConcurrentStream.setup(stream, &block)` also composes in
  that order, which is why calling setup twice on the same stream is safe.
- `callback` / `abort_callback` are plain accessors over single chained procs
  (built by setup when you pass `:callback` / `:abort_callback` options or a
  block). There is **no `add_abort_callback`** — assign `abort_callback = proc
  { |exception| ... }` (only the last one wins unless you compose by hand).
- `join` runs the composed `callback`; `abort` runs `abort_callback` with the
  exception and then discards both callbacks.

```ruby
s = Open.open_pipe { |sin| sin.puts 'x' }
s.add_callback { puts 'a' }
s.add_callback { puts 'b' }     # runs after 'a'
s.join                          # prints "a\nb"
```

## Helpers in `Open`

### `Open.consume_stream(io, in_thread = false, into = nil, into_close = true, &block)`

Pumps the stream to completion and returns the last chunk read. `Path` inputs
are ignored, closed streams are joined and skipped. With `into` (an IO, or a
String/Path file path whose parent dirs are created) it writes every chunk
there; `into_close` (default true) closes `into` when it responds to `close`.
On `Aborted` or any exception it aborts the source, closes `into`, **removes the
partial output file** and re-raises. With `in_thread: true` the whole drain runs
in a new thread that is pushed onto `io.threads`. The block runs after a
successful drain. (`consume_stream
return: "data"`, `consume_stream into path: "into-file\n"`)
.

### `Open.sensible_write(path, content, options = {}, &block)`

Atomic write into a lock-protected tmp file followed by a rename. Key
behaviours for streams:

- When the content is a stream, an `Aborted` raised while copying is
  **swallowed** (`Log.low "Aborted sensible_write"`), the stream is aborted and
  the target is deleted; the partial tmp file is always removed in `ensure`.
- A non-Aborted exception recovers the *original* upstream cause from an
  `AbortedStream`-marked content (`content.exception`) and re-raises that,
  deleting the target. See
  [Streaming Model](../developer/StreamingModel.md) for the marker.
- After a successful copy the content stream is joined (but not if it is a
  `Path` or already joined).

### `Open.open_pipe(do_fork = false, close = true, &block)`

Creates a pipe and returns the **read end** (`sout`), with the block executed in
a producer thread that writes the other end (`sin`).

- **Block arity**: the block always receives `sin` whether it declares a
  parameter or not (arity-0 blocks simply ignore it; `arity-0 block: "arity0\n"`, `arity-1: "w\n"`).
- **No block** raises `RuntimeError "No block given"`.
- **Fork mode** (`do_fork: true`) runs the block in a child process instead of
  a thread: the child purges registered input pipes, closes `sout`, yields,
  `exit! 0`; the parent closes `sin` and sets the pid on `sout` via
  `ConcurrentStream.setup(sout, :pids => [pid])` — no threads, no callbacks.
  `close: false` in the child leaves `sin` open after the block returns
  (same results in fork mode with and without `close`).
- **Thread mode** pairs the two ends (`pair`), runs the block through
  `ConcurrentStream.process_stream` (close+join on exit, abort on error), and
  registers the thread on both ends. An exception in the block aborts the
  stream and re-raises at the consumer.

### `Open.pipe`

Takes **no arguments** and returns the raw `[sout, sin]` pair from `IO.pipe`
(plus registering `sin` in `OPEN_PIPE_IN`). Calling it with a positional
argument raises `ArgumentError`. There is no multi-command helper here —
chain commands by feeding one stream into `:in` of the next `CMD.cmd`.

### `Open.tee_stream(stream)` / `tee_stream_thread_multiple(stream, num)`

Returns an **Array** of streams (`num` copies, default 2): the first is the
"main" copy with `autojoin: true`, the rest have no autojoin. A splitter thread
reads the source once and writes every chunk to all copies; the main copy's
callback joins the source and closes the extra write ends, and its
`abort_callback` propagates an abort to the source and the other copies.
(`tee_stream count: 2`,
`tee[0].autojoin => true`, `tee[1].autojoin => nil`)
.

```ruby
main, copy = Open.tee_stream(CMD.cmd('gzip -c', :pipe => true, :in => input))
# write copy to disk while main feeds the next command, then join copy
```

### `Open.line_monitor_stream(stream, &block)`

Builds a tee, then a monitor thread reads the monitor copy line by line calling
`block.call(line)` — the block therefore runs **concurrently** with whoever
consumes the returned stream, not after. Failures in the block abort the monitor
and are re-raised into the returned stream (`out.raise $!` when supported). The
returned stream is the second copy, annotated from the source and set up with
the monitor thread. 

### `Open.read_stream(stream, size)`

Blocking read of exactly `size` bytes (plain `stream.read(missing)` loop,
`lib/scout/open/stream.rb:401`), raising `ClosedStream` if EOF is reached
first; useful for binary framing: `read_stream(4) => "0123"`.

### `Open.sort_stream(stream, header_hash: '#', cmd_args: nil, memory: false)`

Streams `header_hash`-prefixed lines straight through, then sorts the rest.
`memory: false` (default) pipes the remainder into `env LC_ALL=C sort
<cmd_args>` (`-u` by default when `cmd_args` is nil) and consumes that stream
into the output; `memory: true` reads the whole remainder, sorts it in Ruby and
writes it out. Everything runs inside `ConcurrentStream.process_stream`, so the
source is closed+joined and aborted on error. feeding `"# header\nc\na\nb\n"` returns
`"# header\na\nb\nc\n"` — the header passes through untouched, the rest is
sorted.

### `Open.collapse_stream(s, line: nil, sep: "\t", header: nil, compact: false, &block)`

Merges consecutive lines sharing the same first field, joining the other
columns with `|` (or dropping empty parts when `compact: true`). An optional
block receives the accumulated column array and its return value becomes the
row payload. 

## `Open.open` block form and `DontClose`

```ruby
res = Open.open(file) do |io|
  next io.read if io.is_a?(String)          # IO/StringIO pass straight through
  raise DontClose.new(io.read)              # payload escapes, io still closes
end
```

`Open.open` yields and **always closes and joins** the IO afterwards (the
`ensure` at open.rb:70-77). Raising `DontClose` with a payload makes the block
form *return* the payload instead of the IO, while still closing — it is an
early-return mechanism, not a way to keep the handle (`DontClose returns
payload: "payload"`, `closed after DontClose: true`). Any other exception
aborts, joins and re-raises the stream.

## Progress bars

Pass `:progress_bar` (a `Log::ProgressBar`, `lib/scout/log/progress.rb`; the option key is `:progress_bar` — there is no `:bar` key)
to `CMD.cmd` and each stderr line ticks it (`bar.process(line)` at cmd.rb:643): 2 ticks for a 2-line stderr, in both
pipe and non-pipe mode. With `:log => true` (`CMD.cmd_log`) the stderr text is also
recorded in `stream.log`. `Log::ProgressBar` itself supports `:process =>
proc{|elem| elem.length}` so a tick can be weighted per element.

## Where the diagnostics go

Log output (including severity-logged stderr lines) goes to the Log logfile /
STDERR. **`std_err` is the per-stream capture**, filled by `:save_stderr` — see
[Running Commands](RunningCommands.md#save-stderr--capture-stderr-instead-of-logging-it).
There is no "paired stderr stream" object; in pipe mode stderr is drained by a
thread inside `CMD.cmd`.

## Related

- [Running Commands](RunningCommands.md) — how these streams are produced.
- [Streaming Model](../developer/StreamingModel.md) — setup, join/abort
  internals, exception propagation.
- [Working with Files](WorkingWithFiles.md) — `Open.read/write` on top.
