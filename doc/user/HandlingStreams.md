# Handling Streams

This guide explains how to work with streams in scout-essentials — the
IO-like objects returned by command execution, file streaming, and piping
operations. You'll learn about the stream lifecycle: joining, aborting,
callbacks, and error propagation.

## When to use this

- You're working with command output in pipe mode.
- You're building pipelines that chain multiple commands.
- You need to handle stream errors and cleanup safely.
- You want to understand when and why to call `join`.

## Concepts

### What is a stream?

In scout-essentials, a "stream" is a regular IO object (like a pipe from a
subprocess) extended with lifecycle management. It knows about the threads
and processes that produce it, and provides methods to wait for them,
detect failures, and clean up.

```ruby
stream = CMD.cmd("generate_data", pipe: true)
# stream is an IO, but also has:
#   stream.join    — wait for producers
#   stream.abort   — kill producers
#   stream.joined? — check if joined
```

### The stream lifecycle

A stream goes through these phases:

1. **Creation** — CMD or Open creates a pipe and starts the producer.
2. **Reading** — The consumer reads from the stream.
3. **Joining** — The consumer calls `join` to wait for the producer.
4. **Completion** — Producers finish, callbacks run, locks release.

### Why joining matters

When you read a stream to EOF, you've consumed all the data. But the
producer process may still be running, or it may have exited with an error.
Calling `join` ensures the producer has finished and checks its exit status.

```ruby
stream = CMD.cmd("important_command", pipe: true)
stream.read  # data is consumed
stream.join  # raises ProcessFailed if the command failed
```

## Basic usage

### Reading and joining

```ruby
# Create a stream
stream = CMD.cmd("seq 1 10", pipe: true)

# Read all output
output = stream.read

# Join to check exit status
stream.join
```

### Iterating over lines

```ruby
stream = CMD.cmd("cat data.txt", pipe: true)
stream.each_line do |line|
  process(line)
end
stream.join
```

### Autojoin

When `autojoin: true` is set, the stream joins itself when the consumer
reaches EOF or closes the stream:

```ruby
stream = CMD.cmd("seq 1 100", pipe: true, autojoin: true)
stream.read  # EOF triggers join automatically
```

This is convenient but means any failure will raise during reading, not
during an explicit join call.

## Building pipelines

### Chaining commands

```ruby
# Generate → filter → sort, all streaming
generator = CMD.cmd("generate_data", pipe: true)
filter    = CMD.cmd("grep pattern", in: generator, pipe: true)
sorter    = CMD.cmd("sort", in: filter, pipe: true)

result = sorter.read
sorter.join
filter.join
generator.join
```

### Simplified piping with Open

```ruby
# Open.pipe creates a pipe between commands
stream = Open.pipe("generate_data", "grep pattern", "sort")
result = stream.read
stream.join
```

## Error handling

### Default behavior: raise on failure

```ruby
begin
  stream = CMD.cmd("failing_command", pipe: true)
  stream.read
  stream.join  # raises ConcurrentStreamProcessFailed
rescue ProcessFailed => e
  puts "Command failed: #{e.message}"
end
```

### Suppressing failures

```ruby
stream = CMD.cmd("may_fail", pipe: true, no_fail: true)
stream.read
stream.join  # does not raise
stream.exit_status  # => non-zero exit code
```

### Aborting a stream

If something goes wrong on the consumer side, you can abort the stream to
kill producer threads and processes:

```ruby
stream = CMD.cmd("long_running", pipe: true)
begin
  some_processing(stream)
rescue => e
  stream.abort  # kill the producer
  raise
end
```

## Paired streams

When CMD runs a command, it creates two streams: stdout and stderr. These
are "paired" — aborting one will abort the other.

```ruby
stream = CMD.cmd("verbose_command", pipe: true, save_stderr: true)
stream.read
stream.join
stream.std_err  # captured stderr content
```

## Callbacks

You can attach callbacks to a stream — procs that run after the producer
finishes successfully:

```ruby
stream = CMD.cmd("generate", pipe: true) do |stream_obj|
  # This runs after join, if successful
  Log.info "Generation complete"
end

stream.read
stream.join  # callback runs after join
```

## Common mistakes

### Not joining after reading

```ruby
# RISKY: failure goes undetected
stream = CMD.cmd("important", pipe: true)
stream.read
# no join — if the command failed, you won't know

# RIGHT: always join
stream.read
stream.join
```

### Aborting without cleanup

When you abort a stream, any paired streams are also aborted. Make sure you
handle cleanup in rescue blocks.

### Blocking forever with non-closing streams

If a producer never closes the stream (e.g., `tail -f`), reading will block
forever. Use `read_nonblock` or set a timeout on the join.

## See also

- [Running Commands](RunningCommands.md) — CMD creates streams.
- For the internal ConcurrentStream model, see
  [Streaming Model](../developer/StreamingModel.md).
