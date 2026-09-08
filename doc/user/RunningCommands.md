# Running Commands

`CMD` is scout-essentials' subprocess layer: one entry point, `CMD.cmd`, that
covers shell commands, no-shell command arrays, stdin piping, timeouts, stderr
handling and external-tool bootstrap. This page documents what the code does
(`lib/scout/cmd.rb`); for the object `:pipe => true` hands back, see
[Handling Streams](HandlingStreams.md) and the
[Streaming Model](../developer/StreamingModel.md).

## Command forms

`CMD.cmd(tool, cmd, options)` accepts three shapes:

```ruby
CMD.cmd('echo hello').read            # => "hello\n"  (String: run by a shell)
CMD.cmd(['echo', 'array-form']).read             # => "array-form\n"
CMD.cmd('echo', 'arg2', '-n' => true, '-r' => true).read
```

- **String** — `tool` alone, or `tool + ' ' + cmd` when both are given. The
  string is handed to `Open3.popen3(ENV, cmd)`, so shell features work.
- **Array** — no shell is involved; `Open3.popen3(ENV, *cmd_array)` is called
  with the array plus each option as a separate argument. `process_cmd_options_array`
  turns `'n' => 'val'` into `['n', 'val']` (or `['n=val']` for a key ending in
  `=`), so quoting is not an issue here.
- **Hash-only** (`CMD.cmd({'echo' => 'x'})`) is *not* a command form; the Hash is
  treated as options, `cmd`/`tool` stay nil and the call fails.

array, array+string, symbol tool with nil cmd, ProcessFailed on hash-only).

### The `'{opt}'` placeholder

In String form the processed options are substituted for the literal
placeholder `'{opt}'` **only when it is single-quoted** in the command string:

```ruby
CMD.cmd("cut -d' ' -f2 '{opt}'", '-n' => true, in: 'one two three').read
# => "two\n"        options replaced the quoted placeholder

CMD.cmd("echo {opt} a 1", 'x' => 1).read   # => "{opt} a 1\n"
CMD.cmd("echo '{opt}' a 1", 'x' => 1).read # => "a 1\n"  (note: trailing space)
```

Unquoted `{opt}` is left untouched — the substitution matches `'\{opt\}'`
exactly. Without a placeholder the option string is appended to the command.

## Option quoting: `process_cmd_options`

Every option that is not one of the reserved keys below becomes part of the
command line. `CMD.process_cmd_options(options)` builds that string:

| option/value | result |
|---|---|
| `'opt' => true` | `opt` (bare flag, no value) |
| `'-v' => 'V'` | `-v 'V'` |
| `'-v=' => 'V'` | `-v='V'` (key ends in `=`: value glued, still quoted) |
| `'opt' => nil`, `'opt' => false` | dropped |
| value containing `'` | `\'`-escaped, then wrapped in `'...'` |
| `:add_option_dashes => true` | prepends `--` to keys not already starting with `-` |

The quoting rule is uniform: the value is always wrapped in single quotes, and
a value containing an apostrophe has it backslash-escaped first. There is no
"spaces only" special case.

**Key validation**: an option key that does not match `/^[a-z_0-9\-=.]+$/i`
raises `Invalid option key` before anything runs.

**Arrays are not expanded.** An Array value is stringified (`to_s`) and quoted
like any other value — `"#{value}"` produces `n '["a", "b"]'` in String mode
and `['n', '["a", "b"]']` in array mode. Pass separate calls or build the
command yourself if you need repeated flags.
lines 4-5 and the cmd-level Array check.

(dashes, `=`, nil/false, true,
apostrophes, invalid key, arrays).

## stderr: severities, capture and files

`options[:stderr]` selects how the child's stderr is treated. The default
(added by `cmd.rb:181`) is **`Log::DEBUG`** — stderr lines are only logged at
debug severity, i.e. invisible unless you raise `Log.severity` above it.

- :stderr => true is normalised to `Log::HIGH`.
- Any other Integer is a `Log` severity: the ladder is
  `DEBUG=0, LOW=1, MEDIUM=2, HIGH=3, INFO=4, WARN=5, ERROR=6, NONE=7`
  (`lib/scout/log.rb` `SEVERITY_NAMES`), so `:stderr => Log::MEDIUM` shows
  stderr as warnings while staying quieter than `HIGH`.
- Log output itself goes to the Log logfile / STDERR (see the
  [Streaming Model](../developer/StreamingModel.md) for what per-stream capture
  means); the per-command stderr *text* is never attached to the stream.

### `:save_stderr` — capture stderr instead of logging it

`ee24c68` extended `:save_stderr` to three shapes. All of them also fill the
`std_err` attribute (String on non-pipe results, on the returned stream in pipe
mode), so you can inspect it after the fact:

- **`:save_stderr => true`** — the text is captured into `std_err` and nothing
  is logged.
- **`:save_stderr => path`** (String, Scout `Path` or `Pathname`) — CMD opens
  the path for writing (truncating), **creates missing parent directories**,
  writes stderr to it **line-buffered** so `tail -f` can follow a running
  command, and **closes it when the command ends**. `std_err` is populated too.
- **`:save_stderr => io`** (anything responding to `write`/`<<`) — every chunk
  is written and flushed, but CMD **never closes it**; closing is the caller's
  business. `std_err` is populated too.

```ruby
res  = CMD.cmd('sh -c "echo err >&2; echo out"', :save_stderr => true)
res2 = CMD.cmd(..., :save_stderr => 'log/cmd.err')   # nested dirs created
dst  = File.open('err.txt', 'w')
CMD.cmd(..., :save_stderr => dst)                     # dst stays open
```

Implementation: `cmd.rb:194-217` (destination setup), the writer thread /
inline writer, and the `ensure` at `cmd.rb:600-612` that flushes and closes a
CMD-owned file. Verified by `test/scout/test_cmd_save_stderr.rb` (13 tests,
incl. live `tail -f` polling).

## Exit status, `no_fail` and failure

- Non-pipe mode: `CMD.cmd(...)` waits for the child and raises
  `ProcessFailed` when the exit status is non-zero, unless `:no_fail` (alias
  `:nofail`) is given.
- `:no_fail => true` **suppresses** `ProcessFailed`/`ConcurrentStreamProcessFailed`
  — and `exit_status` then stays `nil`, in pipe mode too. If you need the code,
  call `join_pids` yourself.
  (`pipe read+join exit_status: nil`, `explicit join_pids exit_status: 0`,
  `non-pipe exit_status: 0`).
- `exit_status` is only ever set by `ConcurrentStream#join_pids`
  (`concurrent_stream.rb:127`), which also empties `pids`, so it can only be
  used once. A stream that is read and joined normally has `exit_status == nil`
  (`read+join: es=nil` with `joined?` true; only
  an explicit early `join_pids` yields `0`). Do not rely on `stream.exit_status`.
- If the process never starts (bad executable, no such file) `ProcessFailed` is
  raised immediately — also suppressed by `no_fail`, which then returns `nil`.
- A failed *producer thread* in pipe mode surfaces as
  `ConcurrentStreamProcessFailed` when the consumer closes/joins the stream
 

## Timeout

`CMD::Timeout < ProcessFailed` carries `command` and `timeout` and is raised by
a watchdog when `:timeout => seconds` elapses (`cmd.rb:310-408`,
`TIMEOUT_KILL_GRACE = 1.0`). This is the only way to bound a command's runtime.

- **Non-pipe mode**: the watchdog raises in the calling thread.
- **Pipe mode**: the exception is routed through `ConcurrentStream#abort` — it
  lands in `stream_exception`, the stream is aborted (killing the process,
  clearing pids, unblocking a blocked reader) and is re-raised when the consumer
  reads or joins. It is *not* raised directly in the caller at command start.

## Tool management

There is **no `CMD.add_tool`**. Registration is:

```ruby
CMD.tool(:samtools, claim, test, cmd, &block)   # internally stored [claim, test, block, cmd]
CMD.get_tool(:samtools)                          # ensures it is usable; returns the command name
CMD.versions                                     # => {"samtools" => "1.17", ...}
CMD.conda('samtools', 'env', 'bioconda')         # conda install fallback
CMD.bash(cmd)                                    # bash -l login shell, :autojoin => true
CMD.scan_version_text(text, 'samtools')          # heuristically pull a version string
CMD.cmd_log('...')                               # run + echo STDOUT/STDERR, returns nil
CMD.cmd_pid('...')                               # same implementation, also returns nil
                                                 # (both force :pipe/:log; the pid only shows up
                                                 #  inside the 'STDOUT [pid]:' header)
```

`get_tool` runs `test` (or `command -v cmd`), and if that fails produces the
`claim` Resource (or calls `block`; a Hash result is passed to
`Resource.install`). It then records a version from `--version`/`-version`/
`--help` output. Tools are stored in the `TOOLS` IndiferentHash; `versions`
returns only entries matching `/\d+\./`.

## Options reference (consumed by `CMD.cmd`)

| key | effect |
|---|---|
| `:in` | stdin: a String is written by a thread; an IO/StringIO is read; a ConcurrentStream is streamed (and closed unless `:dont_close_in`). Also `:in_pipe` for a pipe-backed writer. (String, IO, stream, `in_pipe` returns an IO)
. |
| `:pipe` | return a ConcurrentStream instead of the text/StringIO |
| `:stderr` | severity for stderr logging (default `Log::DEBUG`); `true` → `Log::HIGH` |
| `:save_stderr` | `true` / path / IO — see above |
| `:no_fail`, `:nofail` | suppress failure raising (both spellings) |
| `:autojoin` | join the stream when it is closed/read; **`CMD.cmd` sets `:autojoin => no_fail`** |
| `:no_wait` | alias used to default `autojoin` (`autojoin = no_wait if autojoin.nil?`) |
| `:timeout` | seconds; watchdog; only runtime bound |
| `:post` | proc run after the command/stream finishes (teardown, forcing upstream closes) |
| `:progress_bar` | a `Log::ProgressBar`; stderr lines tick it (2 ticks for a 2-line stderr, pipe and non-pipe) |
| `:log` | defaults to `true` (`log = true if log.nil?`, cmd.rb:224): pipe-mode stderr lines are `Log.log`ged at the chosen `:stderr` severity. `:log => false` silences that logging. Not the same as `CMD.cmd_log` (a separate helper that forces `:pipe`/`:log`). |
| `:sudo`, `:xvfb` | prefix the command |
| `:dont_close_in` | keep the `:in` stream open |
| `:add_option_dashes` | passed through to `process_cmd_options*` |

`:wait`, `:canfail`, `:empty_inputs` and `:separator` are **not** options of
`CMD.cmd` in this repo — `cmd.rb` deletes none of them, so they would be
forwarded to `process_cmd_options` and end up as command-line text. `:canfail`
exists on `Persist` (`persist.rb:133`) and on `Resource` claims, not here.
Verified by grepping `lib/` for the four names.

## The block is ignored

`CMD.cmd(...) { ... }` accepts a block but **never calls it** — the only block
invocation inside `cmd.rb` is in `CMD.tool`. In both pipe and non-pipe mode the block
body never runs, while `:post` and `stream.add_callback` do. Use
`:post => proc{}` or stream callbacks for post-join work.

## Related

- [Handling Streams](HandlingStreams.md) — the returned object's lifecycle.
- [Streaming Model](../developer/StreamingModel.md) — internals, error paths.
- [Working with Files](WorkingWithFiles.md) — `Open.grep` on top of `CMD`.
