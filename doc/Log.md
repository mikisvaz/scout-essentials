# Log

The Log module is the framework-wide logging and progress utility. It provides:
- leveled logging (DEBUG, LOW, MEDIUM, HIGH, INFO, WARN, ERROR, NONE)
- colored output and utilities for color manipulation and gradients
- fingerprinting for compact object summaries
- a rich ProgressBar facility with multi-bar, ETA and history support
- helpers to trap and ignore stdout/stderr and to direct logs to a logfile
- convenience debug/inspect helpers

Files / components:
- log.rb — core logging API, level handling, formatting, logfile control
- log/color.rb — integration with Term::ANSIColor and concept color mapping
- log/color_class.rb — Color class for hex color parsing, blending, lightening/darkening
- log/fingerprint.rb — compact fingerprint representations for many object types
- log/progress{.rb, /util, /report} — ProgressBar implementation and helpers
- log/trap.rb — utilities to trap/ignore STDOUT/STDERR

---

## Configuration & Environment

- Log.severity (module attribute): current logging level threshold. Messages below this level are ignored.
- SEVERITY constants: DEBUG, LOW, MEDIUM, HIGH, INFO, WARN, ERROR, NONE (assigned 0..7).
  - Use Log.get_level(value) to convert numeric/string/symbol into numeric level.
- Default severity:
  - Determined by environment variable `SCOUT_LOG` if set to one of the level names.
  - Otherwise read from `~/.scout/etc/log_severity` if present, else INFO.
- Color disabled if `ENV["SCOUT_NOCOLOR"] == 'true'` or SOPT.nocolor set.
- Log.tty_size returns terminal rows (uses IO.console.winsize or `tput li`), falls back to ENV["TTY_SIZE"] or 80.
- Log.logfile(file_or_io) — set logfile target:
  - Passing a String opens the file in append mode, sync=true.
  - Passing an IO or File sets that as the logfile.
  - If not set, logging writes to STDERR.
- Thread-safety: Log.log_write and Log.log_puts synchronize writes via MUTEX.

---

## Coloring & Color utilities

- Log extends Term::ANSIColor and exposes helpers:
  - Log.color(color, str = nil, reset = false)
    - color can be:
      - Symbol naming an ansi color (e.g. :green)
      - Integer index into SEVERITY_COLOR
      - Concept color name (Log.CONCEPT_COLORS map keys like :title, :path, :value)
      - A Color/hex handled by Color class (indirectly via Colorize)
    - If str is nil, returns only the color control string (unless nocolor true).
    - If nocolor is true, returns str unchanged.
  - Log.highlight(str = nil): returns HIGHLIGHT sequence or wraps string.
  - Log.uncolor(str) — strips ANSI color sequences.

- Color utilities:
  - Color class (log/color_class.rb) handles hex parsing, lighten/darken/blend and returns hex strings.
  - Colorize module (log/color.rb) provides:
    - Color selection by name (Colorize.from_name),
    - continuous gradient generation (Colorize.continuous),
    - gradient/rank mapping and distinct color mapping for categorical values,
    - TSV coloring helpers.

- Concept color map:
  - Log.CONCEPT_COLORS (IndiferentHash) maps logical concepts to ANSI colors (e.g. :title => magenta).

---

## Basic Logging API

Main functions:

- Log.log(message = nil, severity = MEDIUM, &block)
  - Adds newline (if missing) and delegates to Log.logn.
  - Skips if severity < Log.severity.

- Log.logn(message = nil, severity = MEDIUM, &block)
  - Emits formatted message without appending newline.
  - Prefix includes timestamp and severity tag inside color.
  - Uses Log.color to color the line. Messages with severity >= INFO are wrapped in Log.highlight.
  - Writes via Log.log_write (synchronized).

- Convenience wrappers:
  - Log.debug(msg), Log.low(msg), Log.medium(msg), Log.high(msg), Log.info(msg), Log.warn(msg), Log.error(msg)
    - Each calls Log.log with the corresponding severity.

- Log.exception(e)
  - Nicely logs an exception: formats message and backtrace using Log.fingerprint for very long messages and Log.color_stack for colored backtrace output. Honors environment `SCOUT_ORIGINAL_STACK` for ordering.

- Log.get_level(level)
  - Accepts Numeric, String (case-insensitive), or Symbol and returns numeric level or 0/nil.

- Log.with_severity(level) { ... }
  - Temporarily sets Log.severity for the block.

- Log.log_obj_inspect(obj, level, file = $stdout)
  - Logs caller location and obj.inspect at given level.

- Log.log_obj_fingerprint(obj, level, file = $stdout)
  - Logs caller location and Log.fingerprint(obj) for compact summary.

- Line/terminal helpers:
  - Log.up_lines(n), Log.down_lines(n), Log.return_line, Log.clear_line(out = STDOUT)

---

## Fingerprinting

- Log.fingerprint(obj) produces a compact human-readable representation useful in logs:
  - Strings are truncated with an MD5 snippet if longer than FP_MAX_STRING (150).
  - Arrays and Hashes are truncated beyond FP_MAX_ARRAY / FP_MAX_HASH.
  - Special handling for IO/File, Float formatting, Thread names, Symbol, nil/true/false etc.
  - Used by other logging helpers to keep outputs concise.

---

## Progress bars

The ProgressBar is a full-featured facility for reporting progress from concurrent tasks.

Key pieces:
- Use Log::ProgressBar.with_bar(max_or_options, options = {}) {|bar| ... } to create a managed bar.
  - new_bar(max, options) creates a bar; with_bar ensures removal on exit unless KeepBar is raised.
- ProgressBar instance attributes:
  - max, ticks, frequency, depth, desc, file, bytes, process, callback, severity
- Behavior:
  - bar.init — initialize and print first state.
  - bar.tick(step = 1) — increment ticks and possibly report (depending on frequency and percent progress).
  - bar.pos(position) — set bar to a specific position (pos - ticks).
  - bar.process(elem) — calls `process` callback and interprets return to tick/pos based on type.
  - bar.percent — computes percent (0..100).
  - Bars are managed centrally in ProgressBar::BARS with concurrency via BAR_MUTEX.
  - Bars can be nested (depth management), silenced, removed, persisted via `file` (save/load YAML state).
  - ProgressBar.report and ProgressBar.report_msg produce formatted output lines including per-second rate, ETA, used time and ticks.

Helpers:
- ProgressBar.get_obj_bar(obj, bar) — helper to create a meaningful bar given an object (TSV, File, Array, Path, etc.) — guesses max records by inspecting file/TSV length if possible.
- ProgressBar.with_obj_bar(obj, bar = true) — convenience wrapper around with_bar using a guessed max.

Notes:
- Progress printing will skip if Log.no_bar is true (set via environment SCOUT_NO_PROGRESS or Log.no_bar=).
- ProgressBar persistence: if `file` option provided, the bar saves state to YAML.

---

## Trapping / ignoring STDOUT and STDERR

- Log.trap_std(msg = "STDOUT", msge = "STDERR", severity = 0, severity_err = nil) { ... }
  - Redirects STDOUT/STDERR into pipes; background threads read and call Log.logn on captured lines with provided severity and prefix.
  - Useful to capture external command output or to consolidate prints into the log.

- Log.trap_stderr(msg = "STDERR", severity = 0) { ... }
  - Captures only STDERR and logs it.

- Log.ignore_stderr { ... } / Log.ignore_stdout { ... }
  - Redirects respective stream to /dev/null for the block (silences output). Safe fallback if /dev/null missing.

These functions restore original streams when the block ends even if exceptions occur.

---

## Convenience debug/inspect helpers

Global helper methods (defined outside Log) for quick debugging:

- ppp(message) — pretty print (with color) and file/line location
- fff(object) — debug printing fingerprint (using Log.debug)
- ddd(obj, file = $stdout) — Log.log_obj_inspect(obj, :debug)
- lll(obj, file = $stdout) — low-level inspect wrapper
- mmm, iii, wwww, eee — wrappers for different severities (medium, info, warn, error)
- ddf/mmf/llf/iif/wwwf/eef — wrappers calling log_obj_fingerprint at different severities
- sss(level) { } — temporarily set severity or set it if no block
- ccc(obj=nil) — conditional debug printing based on $scout_debug_log (used as ad-hoc toggle)

These are small helpers used in tests (e.g., iif :foo writes INFO lines).

---

## Examples

Basic logging:
```ruby
Log.severity = Log::DEBUG
Log.info "Starting task"
Log.debug { "Expensive debug only evaluated when level allows" }
Log.error "Something failed"
```

Exception handling:
```ruby
begin
  raise "boom"
rescue => e
  Log.exception(e)
end
```

Progress bar:
```ruby
Log::ProgressBar.with_bar(100, desc: "Processing") do |bar|
  100.times do
    bar.tick
    # work...
  end
end
```

Trap STDOUT/STDERR block:
```ruby
Log.trap_std("OUT", "ERR", Log::INFO, Log::WARN) do
  system("some_command")
end
```

Set logfile:
```ruby
Log.logfile("/tmp/mylog.txt")
Log.info "Wrote to logfile"
```

Fingerprint:
```ruby
s = "a very long string..."
Log.debug Log.fingerprint(s)   # compact representation for logs
```

---

## Implementation notes & caveats

- Colors: if nocolor is enabled (env or Log.nocolor), color helpers return raw strings.
- Log.log_write and Log.log_puts are synchronized to avoid interleaved writes from threads.
- Log.logn uses caller and Log.last_caller to attempt to find meaningful source location for messages in stack traces.
- Fingerprint logic truncates long strings and large arrays/hashes to keep logs readable.
- ProgressBar uses a central registry (BARS) and a mutex for concurrency; nested bars are supported.
- The Log module depends on utility modules (Misc, IndiferentHash, TSV, Path, etc.) for some features — when used in isolation, those parts may not be available.

This document summarizes the Log module capabilities and usage. Use Log for all script-level diagnostic output, and use ProgressBar for long running operations where periodic status and ETA are useful.