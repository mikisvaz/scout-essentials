# ConcurrentStream

ConcurrentStream is a mixin that augments IO-like stream objects (pipes returned by subprocess wrappers, in-memory streams, etc.) with concurrency-aware lifecycle management: tracking threads and child PIDs that produce/consume the stream, coordinated joining, aborting, callbacks, and safe cleanup. It is used throughout the framework for streams returned by commands (CMD.cmd) and by tee/pipe helpers in Open.

There is also a tiny AbortedStream helper to mark a stream as aborted and attach an exception.

---

## What it does

When a stream is set up with ConcurrentStream.setup, the stream is extended with methods and attributes to:
- record producer threads and child PIDs (threads/pids),
- automatically join and check producer exit status,
- attach callbacks to run once production is complete,
- abort producers/consumers cleanly (raise exceptions in threads, kill PIDs),
- support autjoining/auto-closing when the consumer finishes reading,
- attach a lock object that will be unlocked after join,
- carry metadata: filename, log, paired stream (pair), next stream in pipeline, and more.

This lets a consumer read from a stream and then reliably wait for producers to finish and detect failures (non-zero exit), or abort the whole pipeline on errors.

---

## Setup

ConcurrentStream.setup(stream, options = {}, &block)

- Extends `stream` with ConcurrentStream methods (unless already extended).
- Options (recognized):
  - :threads — thread or array of threads that produce or manage this stream.
  - :pids — pid or array of child process ids to wait for.
  - :callback — proc to call after successful join (can also be provided as block).
  - :abort_callback — proc to call on abort.
  - :filename — textual name for logging/error messages.
  - :autojoin — boolean, if true join on close/read EOF and auto-unlock lock.
  - :lock — Lockfile instance to unlock after join.
  - :no_fail — boolean; if true treat non-zero child exit as non-fatal.
  - :pair — paired stream (e.g., the other side of a pipe) so aborts propagate.
  - :next — next stream in pipeline when teeing/forwarding
  - :log, :std_err — metadata captured for error messages
- If a block is given it is appended to the stream callback.

Example:
```ruby
ConcurrentStream.setup(io, threads: [t], pids: [pid], autojoin: true, filename: "ls-out")
```

---

## Important attributes & predicates

The stream object gets attributes:
- threads, pids — lists of threads and subprocess PIDs to manage.
- callback, abort_callback — procs to call on success/abort.
- filename — friendly name used in logs and error messages.
- joined? — true after join completed.
- aborted? — true after abort called.
- autjoin — whether to auto-join on EOF/close.
- lock — optional Lockfile to unlock after join.
- stream_exception — exception captured that should be re-raised by readers/joins.
- no_fail — allow ignoring nonzero child exit.

AbortedStream.setup(obj, exception = nil) can be used to mark a stream aborted and attach exception (helper used internally).

---

## Joining / waiting

- join_threads
  - Joins registered threads, and if a thread's return value is a Process::Status checks success (unless no_fail). If a thread represented a subprocess and exit status indicates failure, raises ConcurrentStreamProcessFailed.

- join_pids
  - Waits for PIDs via Process.waitpid and raises on non-zero exit unless no_fail.

- join_callback
  - Runs `callback` once and clears it.

- join
  - Calls join_threads, join_pids, raises stored stream_exception if set, runs callback, closes stream (if not closed) and marks joined. Also unlocks `lock` if present. Any exceptions are propagated after unlocking.

---

## Aborting

- abort(exception=nil)
  - Mark stream aborted, store exception in stream_exception, call abort_callback, abort threads (raise into threads) and kill PIDs with SIGINT (best-effort), clear callbacks, close stream, and unlock lock if held. Also propagate abort to `pair` stream if present.

- abort_threads(exception=nil)
  - Raises exception (or Aborted) into producer threads and joins them.

- abort_pids
  - Kills pids with INT.

Use abort to ensure fast cleanup on error and to signal paired streams.

---

## Reading & closing

- read(*args)
  - Wraps normal `read` with exception capture: on error stores `stream_exception` and re-raises. If `autojoin` is enabled and EOF reached, `close` is called automatically.

- close(*args)
  - If `autojoin` is true, `close` will try to `join` (ensuring producers have finished) and then close; on exceptions it aborts, joins, and re-raises.

`joined?` and `aborted?` reflect the stream's lifecycle.

---

## Callbacks

- add_callback(&block)
  - Attaches an additional callback executed after producers finish. Multiple callbacks stack and are executed in order at join time.

- callback and abort_callback may be set in setup — used by caller to run cleanup or post-processing.

---

## Error propagation

- stream_raise_exception(exception)
  - Stores `stream_exception`, raises it into all producer threads (so they can abort), and calls `abort`.

- When join discovers a failing child process, it raises a ConcurrentStreamProcessFailed. Tests exercise this by running `grep` on a nonexisting file and asserting the exception is raised.

When `no_fail` is set true, non-zero exits or join errors are logged but not raised.

---

## Utilities

- annotate(stream) — copy the current stream's threads/pids/callback/etc. onto another stream (useful when creating derived streams).
- filename — returns stored filename or a fallback derived from stream.inspect.
- process_stream(stream, close: true, join: true, message: "...") { ... }
  - Class method wrapper that sets up the stream and ensures the block runs, then closes and joins the stream as requested. On exceptions it aborts the stream and re-raises.

Example usage (from framework):
- `CMD.cmd(..., pipe: true, autojoin: true)` returns a ConcurrentStream-enabled IO. Consumer reads from the stream; when EOF reached or read finishes, the stream auto-joins producers and raises errors on non-zero exit.

Test examples:
```ruby
# success case
io = CMD.cmd("ls", pipe: true, autojoin: true)
io.read
io.close

# failure case raises ConcurrentStreamProcessFailed
io = CMD.cmd("grep . NONEXISTINGFILE", pipe: true, autojoin: true)
io.read   # raises ConcurrentStreamProcessFailed
```

---

## Typical patterns and recommendations

- When producing streams from background threads or subprocesses, call `ConcurrentStream.setup(stream, threads: t, pids: [pid], autojoin: true, filename: name)` so readers can join/observe failures.
- When teeing a stream to multiple outputs, register the splitter thread as a producer on each out-stream so each consumer can join independently.
- Use `abort(exception)` to stop whole pipeline on error and ensure all producers/consumers are signaled and cleaned up.
- Use `process_stream` helper to wrap a block that processes a stream and ensure it is closed and joined safely.

---

ConcurrentStream centralizes safe management of concurrent IO pipelines: shared producers (threads/PIDs), stream cleanup, callback semantics, and error propagation. It is a core primitive used by Open, CMD, and persistence/teeing helpers to make streaming robust in multi-threaded / multi-process contexts.