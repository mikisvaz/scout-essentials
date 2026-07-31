# Investigation: Command Execution and Logging

**Status:** Non-normative investigation artifact. May be outdated.

## Scope
CMD and Log.

---

## CMD

### What it is
A unified wrapper for running external commands with:
- Tool discovery and auto-installation.
- Streaming (pipe) and blocking (read-all) modes.
- stdin piping.
- stderr logging, progress tracking, and capture.
- sudo, xvfb, pipe-chaining support.
- SSH through Open (for remote commands).
- Option-hash-to-flags conversion.

### Core API
```ruby
# Blocking: returns a StringIO-like result
result = CMD.cmd("ls -la")
puts result.read

# Streaming (pipe: true): returns a ConcurrentStream
stream = CMD.cmd("cat huge_file", :pipe => true)
stream.each { |line| ... }

# With tool discovery
CMD.cmd(:samtools, "view -bS aln.sam")
```

### `CMD.cmd(tool, cmd = nil, options = {})`
- `tool` — may be a Symbol registered via `CMD.tool` (auto-install + discovery)
  or a plain String command.
- `cmd` — optional subcommand appended after the tool.
- `options` — IndiferentHash with special keys:
  - `:in` — String/IO/StringIO piped to stdin.
  - `:pipe` — if true, return a ConcurrentStream immediately.
  - `:stderr` — severity level (Integer) or boolean.
  - `:progress_bar` — Log::ProgressBar or options hash.
  - `:sudo` — prepend `sudo`.
  - `:xvfb` — run under xvfb-run.
  - `:autojoin` — autojoin the stream on close.
  - `:no_fail` / `:nofail` — don't raise on failure.
  - `:log` — toggle logging (default true).
  - `:save_stderr` — capture stderr text.
  - `:pipe` — output piped to another command.
  - `:post` — callback executed after command completion.
  - Other keys are converted to command-line flags.

### Tool system (`CMD.tool` / `CMD.get_tool`)
```ruby
CMD.tool(:samtools, nil, nil, "samtools") { install_samtools }
```
- `TOOLS` is a global registry: `{ tool => [claim, test, block, cmd] }`.
- `get_tool(tool)` checks if the tool exists (via `test` or `command -v`).
- If not found, it tries:
  1. `claim.produce` (if a Resource claim is given).
  2. `block.call` (if a block is given).
- After installation, version is detected via `scan_version_text`.
- Tools are cached in `@@init_cmd_tool` to avoid repeated checks.

### Option-to-flags conversion (`process_cmd_options`)
```ruby
CMD.cmd("grep", :pattern => "foo", :ignore_case => true)
# → grep --pattern 'foo' --ignore_case
```
- Boolean `true` → flag without value.
- Boolean `false`/`nil` → flag omitted.
- String → flag with quoted value.
- `--key=value` → `--key 'value'`.
- `--key=` → `--key='value'` (equals form).
- `:add_option_dashes => true` → adds `--` prefix to keys.

### SSH / remote
CMD itself does not handle SSH directly. Use `Open.ssh` or `Open.open`/`Open.read`
with remote paths (detected via `Open.remote?`). However, CMD commands may
include ssh as a string.

### `CMD.bash`
```ruby
CMD.bash(<<~SH)
  set -e
  source ~/.bashrc
  conda activate myenv
  do_stuff
SH
```
Wraps the string in a login shell.

### `CMD.cmd_log` / `CMD.cmd_pid`
Variants that tee stdout/stderr to `Log` in real time, useful for long-running
commands.

---

## Log

### What it is
A thread-safe, severity-based logging system with colored output, progress
bars, exception formatting, and support for redirecting output to a file or
IO.

### Severity levels
```ruby
Log::DEBUG = 0
Log::LOW    = 1
Log::MEDIUM = 2
Log::HIGH   = 3
Log::INFO   = 4
Log::WARN   = 5
Log::ERROR  = 6
Log::NONE   = 7
```
Messages are only emitted if `severity >= Log.severity`.

### Configuration
- `Log.severity = Log::DEBUG` — set threshold (Integer).
- `SCOUT_LOG` environment variable — DEBUG, LOW, MEDIUM, HIGH, WARN, ERROR, NONE.
- `~/.scout/etc/log_severity` file — numeric severity.
- `Log.logfile(path)` — redirect all log output to a file.
- `Log.nocolor = true` — disable ANSI colors.

### Log methods
```ruby
Log.debug("Detailed info")      # DEBUG
Log.low("Slightly important")    # LOW
Log.medium("Medium importance")  # MEDIUM
Log.high("Important")            # HIGH
Log.info("User-facing info")     # INFO
Log.warn("Warning")              # WARN
Log.error("Error")               # ERROR
Log.exception(e)                 # ERROR + backtrace
```

### Block form (lazy evaluation)
```ruby
Log.debug { "Computed value: #{expensive_computation()}" }
```
The block is only evaluated if the severity threshold is met. Use this for
expensive-to-compute log messages.

### Thread-safety
- `MUTEX = Mutex.new` guards `log_write` and `log_puts`.
- Multiple threads logging simultaneously are safe.
- The ProgressBar system uses `BAR_MUTEX` for its own state.

### Log::ProgressBar
A sophisticated multi-bar progress tracking system:

```ruby
Log::ProgressBar.with_bar(1000, :desc => "Processing") do |bar|
  1000.times do |i|
    # ... work ...
    bar.tick
  end
end
```

Features:
- **Stacked bars** — multiple concurrent bars rendered with vertical stacking
  using ANSI cursor movement (`up_lines`/`down_lines`).
- **Throughput estimation** — short-term and long-term rate, ETA calculation.
- **Auto max-guessing** — `with_obj_bar` infers the max from file size
  (`wc -l`), TSV/Array/Hash length, etc.
- **Persistence** — bar state can be saved to/reloaded from a file.
- **Depth tracking** — nested bars track their position in the stack.
- **Silencing** — `SILENCED` array hides specific bars from rendering.
- **Callback chains** — `callback` procs executed on completion.

#### Key methods
- `Log::ProgressBar.with_bar(max, options) { |bar| ... }` — main entry point.
- `bar.tick(n = 1)` — increment by n.
- `bar.pos(n)` — set absolute position.
- `bar.process(elem)` — call `@process` callback, then tick based on return.
- `bar.done` — print completion summary.
- `bar.error` — print error summary.
- `bar.remove` / `remove_bar` — clean up bar from display.
- `with_obj_bar(obj, desc_or_max) { |bar| ... }` — auto-infer max from object.

#### Bar removal
- On normal completion: `bar.done` then `remove_bar`.
- On exception: `bar.error` then `remove_bar`.
- `KeepBar` exception — prevents removal for debugging.

### Log::Color
ANSI color codes for severity levels and general use:
```ruby
Log.color(:yellow, "warning text")
Log.color(Log::INFO, "informational")
```
- `nocolor?` — checks if colors are disabled.
- Colors are defined in `log/color_class.rb` with a mapping from severity → ANSI code.
- `Log.uncolor(text)` — strips ANSI codes.

### Log::Trap
```ruby
Log::Trap.trap('SIGINT') { ... }
```
Safely intercepts signals. Stores handlers for restore. Ensures progress bars
are cleaned up on signal.

### Log::fingerprint
```ruby
Log.fingerprint(obj)
```
Produces a compact, human-readable representation of an object for logging:
- String → the string (truncated if long).
- Array → `[a, b, ...]` (truncated).
- Hash → `{k => v, ...}` (truncated).
- Path → the path string.
- Other → `inspect`.

---

## Cross-module interactions

- **CMD depends on Log** — for stderr logging, debug logging, and progress bars.
- **CMD depends on ConcurrentStream** — for stream lifecycle.
- **CMD depends on Open** — for remote operations and `consume_stream`.
- **Log depends on IndiferentHash** — `process_options` in ProgressBar.
- **Log::ProgressBar depends on CMD** — `guess_obj_max` uses `CMD.cmd("wc -l")`.
- **Log depends on Misc** — `format_seconds`, `fixutf8`.
- **All modules use Log** — it is the foundational logging layer.

---

## Gotchas and warnings

1. **CMD.cmd with `:pipe => true` returns immediately** — the command may
   still be running when you receive the stream. You must `join` the stream
   to wait for completion.
2. **CMD.cmd default stderr level is Log::DEBUG** — by default, stderr is
   logged at DEBUG severity. Use `:stderr => Log::HIGH` to make it visible at
   default severity.
3. **CMD option keys are validated** — `process_cmd_options` raises if an
   option key contains characters outside `[a-z_0-9\-=.]+`. This prevents
   shell injection.
4. **Log.severity is global** — `Log.severity = Log::DEBUG` affects all
   threads. Use `Log.with_severity(level) { ... }` for scoped severity changes.
   This is thread-safe via a thread-local pattern.
5. **Log::ProgressBar bars are global** — the `BARS` array is class-level.
   Nested calls add bars. Bars from different threads may interleave in
   display.
6. **Log.debug block form is not always lazy** — `Log.debug { "..." }`
   evaluates the block only if severity >= DEBUG, but `Log.debug("..." )`
   always evaluates the string. For expensive messages, use the block form.
7. **CMD.cmd missing tool** — if a tool is not found and no install block is
   given, the command will fail with a `ProcessFailed` exception. Check
   `CMD.versions` for known tools.
8. **Log.nocolor detection** — checks `ENV['SCOUT_NO_COLOR']`, output not a
   tty, and `Log.nocolor` flag. Colors may be unexpectedly disabled in
   pipelines.
9. **CMD.cmd option escaping** — single quotes are escaped (`'` → `\'`), but
   other shell metacharacters are not escaped by default. This is by design
   (commands may need them), but means user-supplied option values must be
   sanitized.
10. **Log.exception NOLOG/NOSTACK** — exception messages containing "NOLOG"
    or "NOSTACK" will skip logging or backtrace printing. This is an internal
    convention, not documented.
11. **CMD.cmd with no_fail:true and pipe:true** — the stream will have
    `no_fail` set, meaning `join` won't raise on process failure. Check
    `stream.exit_status` to verify success.
12. `CMD.cmd("grep", :pattern => "foo")` generates `grep --pattern 'foo'`.
    The dashes are auto-added via `:add_option_dashes`. To suppress, pass
    `:add_option_dashes => false`. Check current default: it appears to be
    falsy by default, so `CMD.cmd("grep", "--pattern" => "foo")` may be
    needed.
