# Streaming Model

This document explains how ConcurrentStream works internally: the callback
lifecycle, error propagation, and coordination between producers and
consumers. It is intended for framework contributors.

## Why this abstraction exists

When you pipe one command into another (`generate | grep | sort`), each
stage runs as a separate process with a pipe connecting them. Ruby's
standard IO objects don't track which process produced them, don't detect
if the producer crashed, and don't coordinate cleanup. ConcurrentStream
solves this by wrapping IO objects with lifecycle management.

## How it works

### ConcurrentStream as an IO extension

ConcurrentStream extends IO-like objects (pipes, StringIOs) with lifecycle
metadata:

- `threads` — producer threads that should be joined on completion.
- `pids` — producer process IDs that should be waited on.
- `join_callback` — callbacks to run after successful join.
- `abort_callback` — callbacks to run on abort.
- `autojoin` — whether to join automatically on EOF/close.
- `stream_exception` — exception captured from the producer, re-raised on
  join.

```ruby
ConcurrentStream.setup(io, threads: [producer_thread], pids: [pid])
```

### The join lifecycle

When the consumer calls `stream.join`:

1. **Wait for threads** — Each thread in `threads` is joined. If a thread
   raised an exception, it's captured in `stream_exception`.
2. **Wait for pids** — Each PID in `pids` is waited on. If the process
   exited non-zero, a `ProcessFailed` exception is stored in
   `stream_exception`.
3. **Check exception** — If `stream_exception` is set, it's re-raised.
4. **Run join callbacks** — Procs in `join_callback` are called.
5. **Cleanup** — Locks are released, paired streams are joined.

### Autojoin

With `autojoin: true`, the join happens automatically when:
- The consumer reaches EOF while reading.
- The consumer calls `close` on the stream.

This is convenient for single-consumer scenarios. For multi-stage
pipelines, explicit join is recommended.

### Error propagation

When a producer process fails (non-zero exit), the error propagates to the
consumer through `stream_exception`:

```ruby
# Producer fails
generator = CMD.cmd("false", pipe: true)  # exits 1
filter = CMD.cmd("grep x", in: generator, pipe: true)

filter.read   # may succeed (EOF from pipe)
filter.join   # raises ProcessFailed (from generator's non-zero exit)
generator.join  # also raises
```

### Aborting

`stream.abort` terminates producer threads and processes:

1. Run abort callbacks.
2. Kill threads in `threads`.
3. Kill processes in `pids`.
4. Close the stream.

Aborting propagates to paired streams (e.g., stdout/stderr pairs from CMD).

### Paired streams

CMD creates paired streams (stdout + stderr). They share lifecycle:
- Aborting one aborts both.
- Joining one does not automatically join the other (unless autojoin).
- Both must be joined (or aborted) for full cleanup.

## Key invariants

1. **ConcurrentStream is an IO extension, not a wrapper.** It extends the
   actual IO object, so it remains readable, writable, and passable to
   methods expecting IO.
2. **Join checks for failures.** Calling `join` re-raises any exception
   stored from the producer.
3. **Autojoin is opt-in.** By default, streams are not auto-joined. The
   consumer must call `join` explicitly.
4. **Abort is destructive.** It kills producers. Use abort only for error
   recovery, not normal cleanup.
5. **Paired streams share abort.** Aborting stdout kills stderr producers
   too.

## Extension points

### Custom join callbacks

```ruby
stream = CMD.cmd("generate", pipe: true)
stream.join_callback << lambda { |s| Log.info "Done" }
stream.join
```

### Custom abort callbacks

```RUBY
```ruby
stream.abort_callback << lambda { |s| cleanup_temp_files }
```

### Wrapping custom streams

Any IO-like object can be extended with ConcurrentStream:

```ruby
io = StringIO.new("data")
ConcurrentStream.setup(io, threads: [], pids: [])
```

## Interactions with other subsystems

- **CMD** — CMD wraps every pipe output with ConcurrentStream. The producer
  thread and PID are registered on the stream.
- **Open** — Open's streaming functions (e.g., for remote files) may use
  ConcurrentStream for async fetching.
- **Persist** — Persist's atomic writes don't use ConcurrentStream, but
  concurrent production may involve CMD streams.
- **Log** — CMD logs stderr through Log, which writes to the stream's
  paired stderr.

## Common pitfalls

### Forgetting to join

```ruby
stream = CMD.cmd("important", pipe: true)
stream.read
# forgot join — process failure goes undetected
```

Always join streams in pipe mode to detect producer failures.

### Joining in wrong order for pipelines

For pipelines, join consumer first, then producer. This ensures all data
has been consumed before checking producer status:

```ruby
# Correct order: consumer → producer
sorter.join
filter.join
generator.join
```

Joining producer first may hang if the consumer hasn't drained the pipe.

### Memory with non-pipe mode

Non-pipe mode (`pipe: false`) collects all output in memory (StringIO).
For large outputs, always use `pipe: true`.

### Aborting without handling paired streams

When you abort a stream, paired streams are also aborted. If you're
consuming a paired stream (e.g., stderr), make sure your error handling
accounts for this.

## Related

- [Architecture](Architecture.md) — How ConcurrentStream fits in the
  dependency graph.
- [Design Principles](DesignPrinciples.md) — The IO extension idiom.
- For detailed code investigation, see
  [`../../research/commands-streaming-analysis.md`](../../research/commands-streaming-analysis.md).
