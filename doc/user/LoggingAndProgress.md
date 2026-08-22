# Logging and Progress

`Log` is the single reporting surface: a severity-gated logger that writes to
STDERR, plus a stack of progress bars that render in the same place.
`lib/scout/log.rb`, `log/color.rb`, `log/fingerprint.rb`, `log/progress.rb`,
`log/progress/util.rb` and `log/progress/report.rb` are the whole
implementation.

## Severity ladder

`Log::SEVERITY_NAMES` is `%w(DEBUG LOW MEDIUM HIGH INFO WARN ERROR NONE)` with
integer constants `DEBUG=0 .. NONE=7`. `INFO` sits in the middle (4), not at
the top: `LOW`/`MEDIUM`/`HIGH` are *more verbose than info*.

The severity is set at require time from `ENV['SCOUT_LOG']` first
(`lib/scout/log.rb:36-54`): the known names (`DEBUG`, `LOW`, `MEDIUM`, `HIGH`,
`WARN`, `ERROR`, `NONE`) are honoured, and anything else — including an
unrecognised value — falls back to `Log.default_severity`, which reads
`~/.scout/etc/log_severity` if that file exists and is `INFO` otherwise
(log.rb:23-34).

Verified by `tmp/rewrite_C/probe_04_log_severity.rb` (out04.txt): ladder
order, `Log.severity == 4` with no env/file, `Log.with_severity(level){}`
restoring the original value after the block.

Change it at runtime with `Log.severity = Log::DEBUG`, or scope a block with
`Log.with_severity(level){ ... }`, or use the top-level `sss(level)` /
`sss(level){ ... }` helper (log.rb:430).

## Where output goes, and how it is protected

- `Log.log_write` / `Log.log_puts` wrap every write in `Log::MUTEX`
  (log.rb:141-163). If a logfile was installed, output goes there; otherwise
  STDERR (IOError swallowed).
- **`Log.logfile(path)` sets the logfile; `Log.logfile` with no argument does
  NOT read it back — it resets it to `nil`** (log.rb:110-113). There is no
  reader; the accessor is only `Log.logfile=` (`attr_writer`).
- `Log::LAST` is one shared mutable `String` (starts as `"log"`, never frozen)
  used as a protocol between `logn` and progress-bar printing so bars know how
  many lines to move up and which kind of output came last
  (`progress/report.rb` `print`/`report`). Probe out04.txt confirms
  `class == String`, `frozen? == false`.

## Message forms

- `Log.debug "msg"` .. `Log.error "msg"` print when severity allows; the top
  of the ladder is the `Log::NONE` constant, not a method.
- `Log.debug { "expensive " + build }` — **the block is lazy message
  evaluation, not a timer**: it is only called if the level passes. Probe
  (out05.txt): a counter incremented inside a block passed to `Log.debug`
  stays at 0 under ERROR severity and reaches 1 under DEBUG severity.
- `Log.exception(e)` (log.rb:254) prints `BACKTRACE` lines derived from
  `e.backtrace` after fingerprinting messages longer than 1000 chars; it
  returns early when the message contains `NOLOG` and drops the backtrace when
  it contains `NOSTACK`.
- `Log.stack(stack)` (log.rb:318) prints a magenta header then the stack
  **reversed** (innermost frame first) unless `SCOUT_ORIGINAL_STACK=true`.
  Probe (out05.txt): a caller list `a.rb:1, b.rb:2, c.rb:3` prints as
  `c.rb:3`, `b.rb:2`, `a.rb:1`.

## Top-level debug helpers (defined on Object)

`ppp(msg)` (log.rb:358) prints a cyan `PRINT:` banner plus the caller line and
pretty-prints the message. `fff(obj)` (log.rb:374) logs the fingerprint at
DEBUG. `ddd/lll/mmm/iii/wwww/eee` inspect an object at the matching severity,
and the `f`-suffixed variants (`ddf`, `llf`, `mmf`, `iif`, `wwwf`, `eef`)
fingerprint it first. `sss(level[, &blk])` sets or scopes severity. `ccc`
(log.rb:439) enables `$scout_debug_log` around a block so nested `ccc` calls
print. Probe out05.txt confirms all five are top-level methods defined inside
`lib/scout/log.rb`.

## Colors

- `Log.color(:red, "text")` — symbol color name. Produces `"\e[31mtext\e[0m"`.
- Passing a *String* name does not resolve the color table; the string is used
  as the literal prefix and an escape is appended (`"redred\e[0m"`). Use
  symbols.
- `Log.uncolor(str)` strips ANSI codes. `Log.nocolor` is true when
  `ENV['SCOUT_NOCOLOR'] == 'true'` (exact string), which also blanks the cursor helpers
  `up_lines`/`down_lines`/`return_line`/`clear_line`.

## Fingerprints

`Log.fingerprint(obj)` (log/fingerprint.rb:18) builds a stable, truncated text
representation for logging big values. It dispatches: objects responding to
`fingerprint` are delegated to; `nil/true/false/Symbol` are rendered
literally; strings longer than `FP_MAX_STRING` (150) are truncated to a
digest-marked middle (`"xxx<...400 - 0d723...>xxx"`); arrays longer than 20
show first/middle/last elements; hashes longer than 10 fall back to
keys+values fingerprints; floats get 1/3/6 decimals depending on magnitude.

The signature is `fingerprint(obj)` — **one positional argument**; there are no
`max_length`/`sep` options (probe_05). Hash rendering separates pairs with a
space, not a comma: `Log.fingerprint({a: 1, b: 2, c: 3})` gives
`"{:a=>1 :b=>2 :c=>3}"`.

## Progress bars

`Log::ProgressBar` instances are created with the class helpers in
`progress/util.rb`:

- `Log::ProgressBar.new_bar(max, options = {})` — also accepts a plain Hash
  alone (`new_bar(:max => 50)`); `cleanup_bars` runs first and `:depth`
  defaults to the current bar-stack depth plus offset. `new_bar(true)` treats
  `true` as "no max" (`max = nil if TrueClass === max`, progress.rb:38).
- `Log::ProgressBar.with_bar(max = nil, options = {})` (util.rb:85) — wraps a
  block; `KeepBar` keeps the bar alive, any other exception marks it errored
  and re-raises.
- `Log::ProgressBar.with_obj_bar(obj, bar = true, &block)` (util.rb:167) —
  the *second* argument (not `obj`) picks the bar: a String is the
  description, `true` calls `guess_obj_max(obj)` (which — see the caveat
  below — returns `nil` in a bare scout-essentials process), a Numeric is the
  explicit max, a Hash carries `:max` and other options, and an existing
  `Log::ProgressBar` is reused
  (util.rb:139-162). **The block receives only the bar**:
  `with_obj_bar(list, 'Processing'){ |bar| ... }`.
- `Log.no_bar` / `Log.no_bar=` / `SCOUT_NO_PROGRESS=true` disable ticking
  entirely (progress.rb:5-11). There is no `Log.bar` module method.

Instance API (`progress.rb`): `init`, `tick(step = 1)`, `pos(pos)`,
`process(elem)`, `percent`, and the `max/ticks/frequency/depth/desc/file/
bytes/process/callback/severity` accessors.

- `percent` returns 0 with no ticks, **100 when `max == 0`**, and integer
  division otherwise.
- `tick` is a no-op when `Log.no_bar`; it reports when `diff >= frequency`
  (default 2 s) or when the percent advanced and `diff > 0.3` — that ~0.3 s
  throttle plus the frequency gate is the render throttling.
- `report(io = STDERR)` redraws the whole active-bar stack with cursor
  movement. `report_msg` shows **elapsed time and rate** and, when `max` is
  set, an ETA: `· <rate> per sec. -- <dots> <pct>% <eta> => <elapsed> -
  <ticks> of <max> items · <desc>`; with no `max` the ETA part is replaced
  by `<ticks> items` (probe_12 shows both forms).
- `add_offset` / `remove_offset` / `offset` (util.rb:9-28) indent bars created
  in nested threads.
- `file:` option: `save` writes the bar state to YAML (`:desc, :last_count,
  :last_percent, :last_time, :max, :start, :ticks`) and `done`/`error` remove
  the file, so a bar given a `file:` **resumes across runs** — the persisted
  YAML is reloaded into `ticks` (probe_06 round-trips 3 ticks).

All bar bookkeeping is guarded by `BAR_MUTEX`; per-bar `tick` state is not
synchronized and races by design.

### A scout-essentials-only caveat

`guess_obj_max` (util.rb:101-136) matches `TSV` and `Step` *before* `Array` and
`Hash`. In a plain `require 'scout-essentials'` process neither `TSV` nor
`Step` exists, so the `when TSV` arm raises `NameError`, the rescue turns it
into `nil`, and **`guess_obj_max` always returns `nil`** — i.e.
`get_obj_bar(list, true).max == nil` (probe_06). Pass an explicit Numeric or a
`:max` hash, or define those constants in the embedding repo, to get a real
max.

## Related

- [Cookbook](Cookbook.md) — progress bars inside real recipes.
- [Architecture](../developer/Architecture.md) — where `Log` sits and
  cross-repo attribution.
