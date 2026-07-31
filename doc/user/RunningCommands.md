# Running Commands

This guide explains how to execute external commands in scout-essentials
using the CMD module. You'll learn about basic execution, streaming,
piping, tool management, and error handling.

## When to use this

- You need to run shell commands and capture their output.
- You want to stream command output to another command (pipelines).
- You need to discover and manage external tools (e.g., via conda).
- You want robust error handling for subprocess failures.

## Concepts

### CMD: command execution with lifecycle management

The CMD module wraps `Open3.popen3` to run external commands. It handles
pipe creation, stdin feeding, stderr logging, process lifecycle, and error
propagation.

```ruby
# Simple command — returns StringIO with collected output
out = CMD.cmd("echo hello")
out.read  # => "hello\n"
```

### Pipe mode vs blocking mode

By default (`pipe: false`), CMD waits for the command to finish and returns
a StringIO with all output collected. With `pipe: true`, CMD returns a
stream immediately that you read from while the command runs.

```ruby
# Blocking mode (default): wait for completion
out = CMD.cmd("wc -l file.txt")
out.read  # => "1234 file.txt\n"

# Pipe mode: stream while running
stream = CMD.cmd("generate_data", pipe: true)
stream.each_line { |line| process(line) }
stream.join  # wait for completion and check exit status
```

## Basic usage

### Running a command and capturing output

```ruby
result = CMD.cmd("date +%Y-%m-%d").read
# => "2024-01-15\n"
```

### Passing options as a hash

CMD can interpolate options into the command string using the `{opt}`
placeholder, or append them at the end:

```ruby
# With {opt} placeholder in command
CMD.cmd("sort {opt} file.txt", "-n" => true, "-r" => true)
# runs: sort -n -r file.txt

# Without {opt}: options appended
CMD.cmd("cut -f 2 -d ' '", in: "a b c")
```

### Feeding stdin

```ruby
# Feed a string as stdin
out = CMD.cmd("tr a-z A-Z", in: "hello").read
# => "HELLO\n"
```

## Streaming and pipes

### Creating a stream

```ruby
stream = CMD.cmd("seq 1 100", pipe: true)
stream.read  # read some output
stream.join  # wait for process to finish, raise on failure
```

### Piping one command into another

```ruby
# Generate data, pipe through filter, capture result
producer = CMD.cmd("seq 1 10", pipe: true)
filter = CMD.cmd("grep 5", in: producer, pipe: true)
result = filter.read  # => "5\n"
filter.join
producer.join
```

### Using autojoin

When `autojoin: true` is set, the stream automatically joins producers when
the consumer finishes reading (on EOF or close):

```ruby
stream = CMD.cmd("seq 1 100", pipe: true, autojoin: true)
stream.read  # reading triggers join on EOF
```

## Tool management

CMD can discover and install tools through a registry:

```ruby
# Pass a symbol to trigger tool discovery
CMD.cmd(:samtools, "view -bS input.sam")

# Register a tool with installation instructions
CMD.add_tool(:samtools, "conda install -c bioconda samtools")
```

When you pass a Symbol as the first argument, CMD checks if the tool is
available. If not, it runs the registered installation command.

## Error handling

### Default: raise on failure

```ruby
begin
  CMD.cmd("false")  # exits with status 1
rescue ProcessFailed => e
  puts "Command failed: #{e.message}"
end
```

### Suppressing errors

```ruby
io = CMD.cmd("may_fail", no_fail: true)
io.join
io.exit_status  # => non-zero (check manually)
```

### Capturing stderr

```ruby
io = CMD.cmd("verbose_tool", pipe: true, save_stderr: true)
io.read
io.join
io.std_err  # => captured stderr output
```

## Common mistakes

### Forgetting to join in pipe mode

```ruby
# RISKY: exit status is not checked
stream = CMD.cmd("may_fail", pipe: true)
stream.read
# forgot to join — failure goes undetected

# RIGHT: always join
stream = CMD.cmd("may_fail", pipe: true)
stream.read
stream.join  # raises ProcessFailed if exit != 0
```

### Using String vs Symbol for tools

```ruby
# String: runs exactly this command
CMD.cmd("samtools view input.bam")

# Symbol: goes through tool registry (may install the tool)
CMD.cmd(:samtools, "view input.bam")
```

If you don't need tool installation, pass the command as a String.

### Memory-heavy non-pipe mode

Non-pipe mode (`pipe: false`, the default) collects all stdout in memory. For
commands producing large output, use `pipe: true` and process line by line.

## See also

- [Handling Streams](HandlingStreams.md) — Details on stream lifecycle and
  joining.
- [Logging and Progress](LoggingAndProgress.md) — CMD logs stderr through
  the Log module.
