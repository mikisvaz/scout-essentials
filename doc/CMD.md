# CMD

CMD provides a convenience layer for running external commands, capturing/streaming their IO, integrating with the framework's ConcurrentStream and Open helpers, and for tool discovery/installation helpers. It wraps Open3.popen3 and adds standard patterns for piping, feeding stdin, logging stderr, auto-joining producer threads/processes, and error handling.

Key features:
- Run commands (synchronously or as streams) with flexible options.
- Pipe command output as ConcurrentStream-enabled IO so consumers can read and then join/wait for producers.
- Feed data into command stdin from String/IO.
- Collect and log stderr, optionally saving it.
- Auto-join producer threads/PIDs and surface process failures as exceptions.
- Tool discovery/installation helpers (TOOLS registry, get_tool, conda, scan version).
- Convenience helpers: bash, cmd_pid, cmd_log.

---

## Basic usage

- CMD.cmd(command_or_tool, cmd_fragment_or_options = nil, options = {}) -> returns:
  - When run with `:pipe => true` returns an IO-like stream (ConcurrentStream-enabled) that you can read from; caller should join or let autojoin close/join.
  - When `:pipe => false` (default) returns a StringIO containing stdout (collected), after waiting for process completion.

Examples:
```ruby
# simple capture
out = CMD.cmd("echo '{opt}' test").read   # => "test\n"
# with options processed into the command
out = CMD.cmd("cut", "-f" => 2, "-d" => ' ', :in => "a b").read   # => "b\n"

# pipe mode (stream returned)
stream = CMD.cmd("tail -f /var/log/syslog", :pipe => true)
puts stream.read   # streaming consumption
stream.join        # wait for producers and check exit status
```

---

## Important options

All options are passed as an options Hash (converted with IndiferentHash), and many are special keys:

- :pipe (boolean) — if true, return a stream you can read from; otherwise CMD returns a StringIO after the process completes.
- :in — input to feed to the command:
  - String will be wrapped by StringIO and streamed to process stdin.
  - IO/StringIO passed will be consumed using `readpartial` in a background thread.
- :stderr — controls stderr logging/handling:
  - Integer severity → Log.log writes at that severity.
  - true → maps to Log::HIGH.
  - If stderr is enabled, stderr lines are logged as they arrive.
- :post — callable (proc) run after command finishes (attached as stream callback in pipe mode).
- :log — boolean to enable logging of stderr to Log (default true in many paths). Passing true/false toggles logging.
- :no_fail (or :nofail) — if true do not raise on non-zero exit in pipe-mode setup; if omitted errors raise ProcessFailed or ConcurrentStreamProcessFailed.
- :autojoin — when true, the returned stream will auto-join producers on EOF/close (defaults in many calls to match :no_wait).
- :no_wait — don't wait for process to finish (used to set autojoin).
- :xvfb — if true or string, wrap command in xvfb-run with server args (helper for GUI/CMD).
- :progress_bar / :bar — pass a ProgressBar object to process stderr lines via bar.process.
- :save_stderr — if true, collect stderr lines into stream.std_err.
- :dont_close_in — when feeding :in IO, do not close the source IO after streaming to stdin.
- :log, :autojoin, :no_fail, :pipe, :in etc. are all processed and removed from the command string.

Command option helpers:
- CMD.process_cmd_options(options_hash) → returns CLI options string:
  - If `:add_option_dashes` key set, keys without leading dashes are prefixed with `--`.
  - Values are quoted and single quotes escaped.
  - Handles boolean flags (true/false/nil).

Examples:
```ruby
CMD.process_cmd_options("--user-agent" => "firefox")
# => "--user-agent 'firefox'"

CMD.process_cmd_options("--user-agent=" => "firefox")
# => "--user-agent='firefox'"

CMD.process_cmd_options("-q" => true)
# => "-q"
```

---

## Streaming mode internals

When `:pipe => true`:
- CMD uses Open3.popen3 to spawn the process and receives sin (stdin), sout (stdout), serr (stderr), wait_thr.
- If `:in` is provided and is an IO/StringIO, a background thread writes it into process stdin (unless `dont_close_in`).
- Stderr is consumed in a background thread (either logged via Log at the provided severity, or passed to ProgressBar if provided, or collected if `save_stderr`).
- `ConcurrentStream.setup` is called on the returned `sout` with threads and pids plus options like `autojoin` and `no_fail`.
  - That allows consumers to call `sout.read`, `sout.join`, or rely on `autojoin` to close/join automatically.
- `sout.callback` can be set to `post` callable to run after successful join.

Error handling:
- For pipe mode the library will detect non-zero process exit and raise `ConcurrentStreamProcessFailed` on join unless `no_fail` is true.
- If `:no_fail` is passed true, failures are logged but not raised.

---

## Non-pipe mode internals

When `:pipe` is false (default):
- CMD still uses Open3.popen3, but it reads all stdout into a StringIO and waits for process completion before returning.
- Stderr is read in a background thread and optionally logged/collected; after process completion, if process exit is non-zero, a `ProcessFailed` exception is raised (unless `no_fail`).
- This mode is convenient for quick synchronous captures.

---

## Tool discovery & installation helpers

- CMD.tool(name, claim = nil, test = nil, cmd = nil, &block)
  - Register tools with metadata: claim (Resource or Path), a test command, install block/command and optional fallback cmd string.

- CMD.get_tool(tool)
  - Check if tool is available (runs `test` or `cmd --help`); if not, attempts to produce claim or run registered block to install.
  - Caches result in @@init_cmd_tool to avoid repeated checks.
  - Attempts to read version by trying `--version`, `-version`, `--help`, etc., and parsing text via `CMD.scan_version_text`.

- CMD.scan_version_text(text, cmd = nil) → returns matched version string or nil.
  - Heuristics to find version substrings related to the command name.

- CMD.conda(tool, env = nil, channel = 'bioconda')
  - Convenience to install with conda in either a given env or the login shell.

---

## Convenience wrappers

- CMD.bash(command_string)
  - Runs the given commands inside `bash -l` (login shell) and returns the resulting stream (pipe) — helpful when you need shell initialization (e.g., conda).

- CMD.cmd_pid(...) / CMD.cmd_log(...)
  - `cmd_pid` runs a pipe command while streaming stdout to STDERR (or logs) and returns nil; it handles progress bars and returns after join.
  - `cmd_log` is a thin wrapper around `cmd_pid` that simply returns nil.

---

## Error types

- ProcessFailed — raised for non-zero exit in synchronous mode or when explicitly checked.
- ConcurrentStreamProcessFailed — raised when pipe-mode join detects failing producer subprocess (non-zero exit) and `no_fail` is not set.

---

## Examples (from tests)

- Basic command capture:
```ruby
CMD.cmd("echo '{opt}' test").read        # -> "test\n"
CMD.cmd("cut", "-f" => 2, "-d" => ' ', :in => "one two").read  # -> "two\n"
```

- Pipe usage:
```ruby
stream = CMD.cmd("echo test", :pipe => true)
puts stream.read  # "test\n"
stream.join
```

- Piped pipeline:
```ruby
f = Open.open(file)
io = CMD.cmd('tail -n 10', :in => f, :pipe => true)
io2 = CMD.cmd('head -n 10', :in => io, :pipe => true)
io3 = CMD.cmd('head -n 10', :in => io2, :pipe => true)
puts io3.read.split("\n").length  # => 10
```

- Handling errors:
```ruby
# Raises ProcessFailed for missing command
CMD.cmd('fake-command')

# In pipe mode you may get ConcurrentStreamProcessFailed on join or read/join
CMD.cmd('grep . NONEXISTINGFILE', :pipe => true).join
```

- Use `:no_fail => true` to suppress exceptions on failure and just log.

---

## Recommendations & patterns

- Prefer `:pipe => true` + ConcurrentStream when you want streaming processing without waiting for full output in memory.
- Provide `:in` as an IO to stream large inputs into a subprocess.
- Use `:autojoin => true` to automatically join producers on EOF/close (useful for simple consumers).
- Register tools via `CMD.tool` and use `CMD.get_tool` to locate or auto-install/produce required tools.
- Always check or propagate exceptions from `join` for pipe-mode streams to detect failing subprocesses.

---

## Quick API reference

- CMD.cmd(tool_or_cmd, cmd_fragment_or_options = nil, options = {}) => StringIO or ConcurrentStream (when pipe)
- CMD.process_cmd_options(options_hash) => option string appended to command
- CMD.setup tool registry:
  - CMD.tool(name, claim=nil, test=nil, cmd=nil, &block)
  - CMD.get_tool(name)
  - CMD.scan_version_text(text, cmd = nil)
  - CMD.versions -> hash of detected versions
- CMD.bash(cmd_string) — run in bash -l
- CMD.cmd_pid / CMD.cmd_log — helpers for logging and running commands that stream stdout to logs
- CMD.conda(tool, env=nil, channel='bioconda') — convenience installer wrapper

---

CMD centralizes robust process execution patterns needed throughout the framework: streaming, joining, logging, error detection and tool bootstrap. Use its options to control behavior for production-grade command invocation.