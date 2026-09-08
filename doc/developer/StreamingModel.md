# Streaming Model

This page documents the streaming model implemented in
`lib/scout/concurrent_stream.rb` and `lib/scout/open/stream.rb` from the inside:
how a stream is constructed, how the two lifecycle callbacks compose, how abort
and join interact, and how errors travel. The user-facing surface is
[Handling Streams](../user/HandlingStreams.md); the producer side is
[Running Commands](../user/RunningCommands.md).

## The core idea

A "stream" here is an ordinary IO object (a pipe read end from a subprocess, a
`StringIO`, a `File`) extended with the `ConcurrentStream` **module**. The
module does not replace the IO; it adds bookkeeping about who is producing the
data and what must happen when the data is finished:

- `threads` / `pids` — the producers feeding this end,
- `callback` / `abort_callback` — what to run on success / on abort,
- `std_err`, `log`, `exit_status`, `filename`, `lock`, `next`, `pair`.

Everything hangs off `ConcurrentStream.setup`, and most of the model is about
what setup, join and abort do with that state.

## `ConcurrentStream.setup` is idempotent and accumulative

```ruby
def self.setup(stream, options = {}, &block)   # concurrent_stream.rb:12
```

`setup` extends the object unless it already is a `ConcurrentStream`, then:

- `threads ||= []`, `pids ||= []`, and new values are **concatenated** onto the
  existing arrays — a second `setup` adds producers, it does not replace them
  (`idempotent setup: cs? true
  threads=1 pids=[4]`, `after 2nd threads arg: 2`).
- `std_err` is **reset to `""`** on every setup.
- `autojoin`, `no_fail`, `next`, `pair`, `filename`, `lock` are only assigned
  when the corresponding option is non-nil, so an existing value survives.
- **The block becomes a callback**: a block passed to `setup` is treated as
  `callback` and *composed* with any existing callback, so the new block runs
  after the old one (observed `[:block, :block2]`).

This is why `Open.open_pipe` (thread mode) can call `setup` on both ends and
still compose a user callback, and why `add_callback` composes the same way.

## Callbacks: `callback`, `add_callback`, `abort_callback`

There are two callback slots, each holding a single (possibly chained) Proc:

- `callback` (a.k.a. the join callback) — run by `join_callback`, which is
  called from `join` and is skipped if the stream is already joined; it is
  cleared (`@callback = nil`) after running so it fires once.
- `abort_callback` — run by `abort(exception)` with the abort exception, then
  discarded together with `callback`.

`ConcurrentStream#add_callback(&block)` wraps the current callback so the new
block runs **after** the old one — the same composition `setup` uses:

```ruby
stream.add_callback { cleanup_a }
stream.add_callback { cleanup_b }   # join runs a, then b
```

(`add_callback order: [:first,
:second]`). There is no `add_abort_callback`;
`abort_callback = proc { |exception| ... }` replaces the slot (only `setup`
with an `:abort_callback` option composes it).

## `join`: threads, pids, callbacks, close — never the pair

```ruby
def join        # concurrent_stream.rb:146
  join_threads; join_pids
  raise stream_exception if stream_exception
  join_callback
  close unless closed?
ensure
  @joined = true
  lock.unlock if lock && lock.locked?
  raise stream_exception if stream_exception
end
```

- `join_threads` waits for each producer thread (skipping the current thread).
  If a thread returned a failed `Process::Status` it raises
  `ConcurrentStreamProcessFailed`; a thread that died with an exception is
  routed through `stream_raise_exception` unless `no_fail`.
- `join_pids` `Process.waitpid`s each pid, records `self.exit_status`, raises
  `ConcurrentStreamProcessFailed` for a bad status unless `no_fail`, and
  **empties `@pids`** — so `exit_status` is only ever accurate right here.
- `join` never touches `@pair`. The pair is the *other end of the same pipe*
  (see below) and is joined/aborted through `abort` propagation, not through
  `join`.

`close` (concurrent_stream.rb:230) is a thin wrapper: with `autojoin` it closes
and then joins when the stream is at EOF or already closed, converting a close
failure into `abort` + `join` + `stream_raise_exception`; without `autojoin` it
just closes, swallowing `IOError`.

## `no_fail`

`no_fail` silences every join-time failure path:

- a producer thread's failed status does not raise
  `ConcurrentStreamProcessFailed`,
- a dead producer thread is logged at `Log.low` ("Not failing on exception
  joining thread") instead of being escalated,
- `join_pids` does not raise for a non-zero exit status.

`CMD.cmd` propagates `:no_fail` to the stream and **defaults `autojoin` to
`no_fail`** (`cmd.rb:219`, `:autojoin => no_fail`), which is why a `no_fail`
pipe that is simply read does not blow up at close time.

## `abort`: idempotent, and it propagates to `pair`

```ruby
def abort(exception = nil)   # concurrent_stream.rb:204
```

`abort` is the deliberate early-stop path. It:

1. records `stream_exception ||= exception`,
2. marks the object with `AbortedStream.setup(self, exception)` and sets
  `@aborted = true`; a second call only logs (`Already aborted stream`) and
  returns — **idempotent**:
  `abort idempotent: aborted? true`, `second abort: no raise, aborted? true`),
3. runs `abort_callback` with the exception,
4. `abort_threads`: raises `Aborted` (or the given exception) in each producer
  thread and joins them — this is what unblocks a producer stuck writing to a
  pipe nobody reads,
5. `abort_pids`: sends `SIGINT` to each pid,
6. clears both callbacks,
7. **propagates to `@pair`** if it responds to `abort` and is not already
  aborted — killing one end of an `Open.open_pipe` pair takes down the other,
8. closes and unlocks in `ensure`.

Producers are expected to `rescue Aborted` and finish quietly; `Open.grep`,
`consume_stream` and `sensible_write` all do.

## `stream_raise_exception`: the failure amplifier

```ruby
def stream_raise_exception(exception)   # concurrent_stream.rb:281
  self.stream_exception = exception
  threads.each { |thread| thread.raise exception }
  self.abort
end
```

This is how one failing producer takes the whole stream down: the exception is
stored in `stream_exception` (so a later `join`/`read` re-raises it even if the
current frame recovers), it is raised in every producer thread, and the stream
is aborted. `join_threads` and `join_pids` call it, and `ConcurrentStreamProcessFailed`
carries the offending `pid` plus the stream.
(`stream_raise_exception raised: demo`, `stream_exception set: #<Aborted: demo>`,
`no_fail join of failed: no raise`).

## `ConcurrentStream.process_stream`

```ruby
def self.process_stream(stream, close: true, join: true, message: "process_stream",
                        **kwargs, &block)
```

The standard producer wrapper (concurrent_stream.rb:286): it sets the stream up
with `kwargs`, runs the block, and in an `ensure` closes and joins the stream as
requested. `Aborted` and any other exception are logged, the stream is aborted
with the exception, and the exception is re-raised. `Open.open_pipe` (thread
mode) and `Open.sort_stream` are built on it.
(`process_stream: "z\ny\nx\n" src joined=true src closed=true`).

## `AbortedStream` and recovering the original cause

`AbortedStream` is not an exception class: it is a **marker module** with an
`exception` accessor (`concurrent_stream.rb:4-9`). `abort` marks the stream with
it so downstream code can tell "this stream was aborted" apart from "this IO is
just closed", and can ask what the real cause was:

```ruby
content.abort(my_error)          # stream.exception == my_error
...
exception = (AbortedStream === content and content.exception) ? content.exception : $!
```

That exact snippet is what `Open.sensible_write` uses: when copying a stream
into its tmp file raises, it recovers the original upstream exception from the
marker and re-raises *that* (deleting the target and tmp file), while a plain
`Aborted` is swallowed and cleaned up.

## `pair` means pipe ends, not stdout/stderr

`ConcurrentStream#pair` is set by `Open.open_pipe` (thread mode) on both ends of
the pipe it just created: `setup(sin, :pair => sout)` and
`setup(sout, :pair => sin)` (open/stream.rb:230-231). It exists so `abort` on
one end can propagate to the other. **It has nothing to do with "a paired
stdout/stderr stream"** — there is no such object in this repo.

Likewise, in `CMD.cmd` pipe mode the child's **stderr is drained by a thread**
(an `err_thread` registered on the returned stream when a severity or
`save_stderr` asks for it), not by a second stream. Per-stream diagnostics live
in `std_err` (filled by `:save_stderr`) and `log` (last stderr line); log
messages themselves go to the Log logfile / STDERR.

## `next`

`next` is a forward link to the stream that logically follows this one
(`setup` assigns it from `:next`). It lets a helper hand you a derived stream
while keeping a pointer at the original, so bookkeeping (`filename`, locks,
`annotate`) can be traced back along the chain. `ConcurrentStream#annotate`
copies `threads`, `pids`, `callback`, `abort_callback`, `filename`, `autojoin`
and `lock` onto another stream — used by `Open.line_monitor_stream` and
annotation-style code.

## Reading between the lines

`read` (concurrent_stream.rb:246) wraps `IO#read` so that an exception is
recorded in `stream_exception`, the stream aborted and the recorded exception
re-raised; when `autojoin` is set it polls `eof?` and closes/joins once the
producer is done. This is what makes a `:pipe => true` result behave like a
plain IO for `.read`/`.each` while still cleaning up its producers.

## Where this is used

- `CMD.cmd` — `:pipe => true` produces these streams
  ([Running Commands](../user/RunningCommands.md)).
- `Open.open_pipe`, `Open.tee_stream`, `Open.sort_stream`,
  `Open.line_monitor_stream`, `Open.collapse_stream`, `Open.consume_stream`,
  `Open.sensible_write` — the helpers documented in
  [Handling Streams](../user/HandlingStreams.md).
- `Open.grep` composes `CMD.cmd` + `:post`; its `force_close` call is a dead
  `respond_to?` guard (no such method exists in this repo).
- For the module dependency graph, see
  [Architecture](Architecture.md#modules-and-dependencies); for cross-repo
  concepts (TSV, Step, Workflow, HPC) see the
  [attribution table](Architecture.md#ecosystem-boundaries-and-attribution).
