# Running Commands

This guide explains how to execute external commands in scout-essentials
using the CMD module. You'll learn about basic execution, streaming,
piping, tool management, and error handling.

CMD supports two ways to specify a command: as a **String** (interpreted by
a shell, for flexibility) or as an **Array** of arguments (executed
directly, for safety). Both forms share the same lifecycle, streaming, and
error-handling tooling. Choosing between them is a recurring theme in this
guide.

## When to use this

- You need to run shell commands and capture their output.
- You want to stream command output to another command (pipelines).
- You need to discover and manage external tools (e.g., via conda).
- You want robust error handling for subprocess failures.
- You are building commands from variable or untrusted input and want to
  avoid shell injection (use the Array form).

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

### String form vs Array form

CMD accepts the command in two forms. All other options (stdin, pipe mode,
error handling, etc.) work identically in both.

| Form | First argument | Shell | Typical use |
|------|---------------|-------|-------------|
| **String** | `"echo hello"` | Yes — interpreted by `/bin/sh` | Pipes, redirects, globbing, variable expansion |
| **Array** | `["echo", "hello"]` | No — passed directly to `execve` | Commands built from variable or untrusted input |

The **String form** passes the command through a shell. This means shell
features like pipes (`|`), redirects (`>`), globbing (`*.txt`), variable
expansion (`$HOME`), and command substitution are available. It is the
right choice when you need these features or when the command is a fixed
literal.

The **Array form** passes each element as a separate argument directly to
the operating system's `exec` call — no shell is involved. This means
special characters such as `;`, `|`, `>`, `$`, spaces, and backticks are
treated as literal data, not as shell metacharacters. It is the right
choice when any part of the command comes from user input, external data,
or variables, because it eliminates the risk of shell injection.

```ruby
# String form — shell interprets special characters
CMD.cmd("echo $HOME").read    # => "/home/user\n"  (variable expanded)

# Array form — everything is literal
CMD.cmd(["echo", "$HOME"]).read   # => "$HOME\n"    (literal, not expanded)
```

## Basic usage

### Running a command and capturing output

```ruby
# String form
result = CMD.cmd("date +%Y-%m-%d").read
# => "2024-01-15\n"

# Array form — same result, no shell
result = CMD.cmd(["date", "+%Y-%m-%d"]).read
# => "2024-01-15\n"
```

### Array form (no shell)

When the first argument is an Array, CMD executes the command without a
shell. Each element becomes a single argument:

```ruby
# Simple echo
CMD.cmd(["echo", "hello"]).read        # => "hello\n"

# Multi-word argument stays as one argument (no quoting needed)
CMD.cmd(["echo", "hello world"]).read  # => "hello world\n"

# Special characters are literal — no injection risk
CMD.cmd(["echo", "hello; rm -rf /"]).read   # => "hello; rm -rf /\n"
CMD.cmd(["echo", "$HOME"]).read             # => "$HOME\n"
```

This is the recommended approach when command arguments come from
untrusted or variable sources:

```ruby
# User-provided filename — safe with Array form
filename = params[:filename]   # could contain spaces, ;, $, etc.
CMD.cmd(["grep", pattern, filename]).read

# Contrast: String form would be vulnerable to injection
# CMD.cmd("grep #{pattern} #{filename}").read  # RISKY!
```

A String passed as the second argument is appended to the command array:

```ruby
CMD.cmd(["echo", "-n"], "hello").read  # => "hello" (no trailing newline)
```

### Passing options as a hash

CMD can interpolate options into the command string using the `{opt}`
placeholder, or append them at the end:

```ruby
# With {opt} placeholder in command
CMD.cmd("sort '{opt}' file.txt", "-n" => true, "-r" => true)
# runs: sort -n -r file.txt

# Without {opt}: options appended
CMD.cmd("cut -f 2 -d ' '", in: "a b c")
```

In Array form, options from the hash are converted to separate CLI
arguments and appended to the command array (there is no `{opt}`
placeholder — the options simply become additional elements):

```ruby
# Array form with options hash
CMD.cmd(["cut"], "-f" => 2, "-d" => " ", in: "one two three").read
# => "two\n"
# runs: cut -f 2 -d ' '
```

### Feeding stdin

```ruby
# Feed a string as stdin (works in both forms)
CMD.cmd("tr a-z A-Z", in: "hello\n").read         # => "HELLO\n"
CMD.cmd(["tr", "a-z", "A-Z"], in: "hello\n").read  # => "HELLO\n"
```

## Streaming and pipes

### Creating a stream

```ruby
# String form
stream = CMD.cmd("seq 1 100", pipe: true)
stream.read  # read some output
stream.join  # wait for process to finish, raise on failure

# Array form — identical behavior
stream = CMD.cmd(["seq", "1", "100"], pipe: true)
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

Both forms can be mixed in a pipeline:

```ruby
producer = CMD.cmd(["seq", "1", "100"], pipe: true)  # Array form
filter  = CMD.cmd("grep 50", in: producer, pipe: true) # String form
filter.read  # => "50\n"
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

Tool management is only available in String form (or when using a Symbol).
In Array form, the first element is always treated as a literal command
name — no tool registry lookup occurs.

## Error handling

### Default: raise on failure

```ruby
# String form
begin
  CMD.cmd("false")  # exits with status 1
rescue ProcessFailed => e
  puts "Command failed: #{e.message}"
end

# Array form — identical error behavior
begin
  CMD.cmd(["false"])
rescue ProcessFailed => e
  puts "Command failed: #{e.message}"
end
```

### Suppressing errors

```ruby
io = CMD.cmd("may_fail", no_fail: true)
io.join
io.exit_status  # => non-zero (check manually)

# Array form works the same way
io = CMD.cmd(["may_fail"], no_fail: true)
```

### Capturing stderr

```ruby
io = CMD.cmd("verbose_tool", pipe: true, save_stderr: true)
io.read
io.join
io.std_err  # => captured stderr output

# Array form
io = CMD.cmd(["ls", "/nonexistent"], no_fail: true, save_stderr: true)
io.std_err  # => "ls: cannot access '/nonexistent': No such file or directory\n"
```

## Choosing between String and Array form

| Criteria | Use String | Use Array |
|----------|-----------|-----------|
| Command is a fixed literal | ✓ | ✓ |
| Arguments come from user input | | ✓ |
| You need shell pipes (`\|`) | ✓ | |
| You need shell redirects (`>`, `<`) | ✓ | |
| You need variable expansion (`$VAR`) | ✓ | |
| You need globbing (`*.txt`) | ✓ | |
| You need the `{opt}` placeholder | ✓ | |
| You need tool registry lookup (Symbol) | ✓ | |
| You want to avoid shell injection | | ✓ |

**Rule of thumb:** If any part of the command could contain spaces or
special characters that you want treated as literal data — especially when
the data comes from outside your code — use the Array form. If you need
shell features (pipes, redirects, globbing, variable expansion), use the
String form.

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

# Array: runs the command directly (no tool registry)
CMD.cmd(["samtools", "view", "input.bam"])
```

If you don't need tool installation, pass the command as a String or Array.

### Array form does not support shell features

Because the Array form bypasses the shell entirely, shell operators and
metacharacters are **not interpreted** — they are passed as literal
arguments:

```ruby
# This does NOT pipe — "|" is a literal argument to echo
CMD.cmd(["echo", "hello", "|", "cat"]).read
# => "hello | cat\n"

# This does NOT redirect — ">" is a literal argument to echo
CMD.cmd(["echo", "data", ">", "out.txt"]).read
# => "data > out.txt\n"

# Variable is NOT expanded
CMD.cmd(["echo", "$HOME"]).read
# => "$HOME\n"

# Glob is NOT expanded
CMD.cmd(["ls", "*.txt"]).read
# ls tries to open a file literally named "*.txt"
```

If you need shell pipes, redirects, globbing, or variable expansion, use
the **String form** instead:

```ruby
# Shell pipe — use String form
CMD.cmd("echo hello | cat").read       # => "hello\n"

# Shell redirect — use String form
CMD.cmd("echo data > out.txt").read    # writes to out.txt

# Variable expansion — use String form
CMD.cmd("echo $HOME").read             # => "/home/user\n"
```

### `{opt}` placeholder is String-only

The `{opt}` placeholder is a feature of the String form: it substitutes
processed options into a specific position in the command string. In Array
form there is no string template, so `{opt}` is not available. Instead,
options from the hash are simply appended as separate arguments to the
command array:

```ruby
# String form: '{opt}' placeholder controls where options go
CMD.cmd("sort '{opt}' file.txt", "-n" => true, "-r" => true)
# runs: sort -n -r file.txt

# Array form: options appended after the command elements
CMD.cmd(["sort", "file.txt"], "-n" => true, "-r" => true)
# runs: sort file.txt -n -r
```

If you need precise control over option placement within the command, use
the String form with `{opt}`. If you just need options appended at the end,
either form works.

### Memory-heavy non-pipe mode

Non-pipe mode (`pipe: false`, the default) collects all stdout in memory. For
commands producing large output, use `pipe: true` and process line by line.

## See also

- [Handling Streams](HandlingStreams.md) — Details on stream lifecycle and
  joining.
- [Logging and Progress](LoggingAndProgress.md) — CMD logs stderr through
  the Log module.
- [Developer: Streaming Model](../developer/StreamingModel.md) — How CMD
  uses ConcurrentStream internally.
