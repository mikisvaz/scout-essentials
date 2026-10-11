# Testing availability handoff — scout-rig

Provenance: salvage packet produced during the scout-essentials layering cleanup
(2026-10). The interrupted draft in scout-essentials contained Python/R probes
that belong to scout-rig. This note is self-contained: layer table, corrected
reference implementations, interpreter-selection matrix, motivation, and
constraints. Nothing here needs to be re-derived from scout-essentials.

## Scope for scout-rig

scout-rig owns **runtime-availability probes for interpreters and their
packages**: `python?`, `python_modules?`/`python_modules_reason`,
`rscript?`, `r_packages?`/`r_packages_reason` (R: reference code only — there
are no live R call sites today).

## Layer table

| Probe / method | Layer | Destination |
|---|---|---|
| `executable?(name)` — PATH lookup, no shell | scout-essentials | `lib/scout/testing/availability.rb` (already delivered: `Scout::Testing::Availability.executable?`) |
| `run_command(argv, timeout:)` — bounded, both streams, TERM→KILL | scout-essentials | same file, `Scout::Testing::Availability.run_command` |
| `tcp_reachable?(host, port, timeout:)` | scout-essentials | same file, `Scout::Testing::Availability.tcp_reachable?` |
| `python?` | scout-rig | scout-rig test-support module (suggested `test/support/availability.rb` equivalent, e.g. `ScoutRig::Testing::Availability`) |
| `python_modules?(mods)` + `python_modules_reason(mods)` | scout-rig | same module |
| `rscript?` | scout-rig (reference only) | same module |
| `r_packages?(pkgs)` + `r_packages_reason(pkgs)` | scout-rig (reference only) | same module |
| `cuda?` | scout-ai | scout-ai `test/support/availability.rb` (see testing-availability-scout-ai-handoff.md) |
| `hf_model_cached?` / `hf_model_reason` | scout-ai | same |
| `endpoint_reachable?`, `endpoint_configured?`, `endpoint_reason`, `configured_endpoints`, `real_endpoints`, `endpoint_available?` | scout-ai | same |
| `InfrastructureProbes` | scout-ai | scout-ai `test/support/infrastructure_probes.rb`, unchanged |

## Defect list relevant to scout-rig

The interrupted draft (and the scout-ai support file it came from) had 7 known
defects. The ones that apply to the Python/R probes:

1. **`python?` ignored the subprocess exit status.** `python -c 'import sys'`
   can fail at startup (broken interpreter, missing stdlib) while still writing
   output; only the exit status proves the interpreter works. Fixed in the
   reference below.
2. **`python_modules_reason` read stdout.** Python import tracebacks go to
   **stderr**; reading stdout yields an empty, useless reason. Fixed below.
3. **`memo` rescued `Exception`.** That swallows `SignalException`,
   `NoMemoryError`, and friends. Rescue `StandardError` only; treat timeout and
   launch failure deliberately (they are recorded facts, not surprises).
4. **`run_bounded` drained stdout before stderr** (pipe-deadlock risk with a
   chatty child), spawned **before** its rescue (a launch failure could escape
   the method), and the `capture:false` path drained **neither** pipe. Either
   delegate to `Scout::Testing::Availability.run_command` (preferred — it
   drains concurrently with a deadline and reports launch failure as a result,
   not an exception) or apply the corrected runner included below.
5. (memoization ignoring an argument) — scout-rig has no endpoint probes; the
   analogous rule is applied: memoize keyed on **executable + env + timeout**,
   with an explicit `reset!`.
6. (HF cache ignoring `HF_HUB_CACHE`) — scout-ai only, not applicable here.
7. **Module/package names were interpolated unsafely** into Python/R source.
   A name containing a quote escapes the source string. Pass names as **argv**
   to a fixed probe script (Python: `sys.argv`; R: `commandArgs(TRUE)`), or
   fall back to `Shellwords.escape` only if a source string is unavoidable.

## Corrected reference implementations

Assumes scout-essentials ≥ the version providing
`Scout::Testing::Availability` (`require 'scout/testing/availability'`). The
module is deliberately opt-in and stdlib-only; scout-rig adds the interpreter
knowledge on top of it.

```ruby
# scout-rig test support: interpreter/package availability probes.
# Ordinary unit tests must stay OFFLINE: these probes only run local
# executables. Product-failure assertions must never become skips.
require 'scout/testing/availability'
require 'shellwords' # only used by the *_reason fallbacks

module ScoutRig
  module Testing
    module Availability
      PROBE_TIMEOUT = 30

      class << self
        # --- memoization: keyed on the probe inputs, StandardError only ---

        def memo
          @memo ||= {}
          key = yield.to_s # caller builds the full key first
          return @memo[key] if @memo.key?(key)

          @memo[key] = yield # NOTE: see each probe; key is passed explicitly
        end

        def reset!
          @memo = {}
        end

        def [](key)
          @memo ||= {}
          @memo[key]
        end

        def []=(key, value)
          @memo ||= {}
          @memo[key] = value
        end

        def memoized(key)
          @memo ||= {}
          return @memo[key] if @memo.key?(key)

          @memo[key] = yield
        rescue StandardError => e # defect 3: never rescue Exception
          "probe error: #{e.class}: #{e.message}"
        end
        private :memoized

        # --- executable selection ---

        # SCOUT_TEST_PYTHON wins; else PATH lookup in order python3, python.
        # Return is an absolute-or-PATH executable name, nil when absent.
        def python_executable
          configured = ENV['SCOUT_TEST_PYTHON'].to_s.strip
          return configured unless configured.empty?
          return 'python3' if Scout::Testing::Availability.executable?('python3')
          return 'python' if Scout::Testing::Availability.executable?('python')

          nil
        end

        def rscript_executable
          configured = ENV['SCOUT_TEST_RSCRIPT'].to_s.strip
          return configured unless configured.empty?
          return 'Rscript' if Scout::Testing::Availability.executable?('Rscript')

          nil
        end

        # --- Python probes ---

        # defect 1: the exit status, not the output, decides.
        def python?
          executable = python_executable
          return false unless executable

          result = Scout::Testing::Availability.run_command(
            [executable, '-c', 'import sys'], timeout: PROBE_TIMEOUT
          )
          result.success? && result.exit_status == 0
        end

        # defect 7: module names travel as argv, never interpolated.
        # defect 2: the reason comes from stderr, where tracebacks go.
        def python_modules?(*modules)
          !python_modules_reason(*modules)
        end

        def python_modules_reason(*modules)
          executable = python_executable
          return 'no python executable found' unless executable
          return nil if modules.empty?

          # Fixed probe source; names arrive as argv so quoting is moot.
          probe = <<~PY
            import importlib, sys
            missing = []
            for name in sys.argv[1:]:
                try:
                    importlib.import_module(name)
                except Exception as e:
                    missing.append("%s: %s: %s" % (name, type(e).__name__, e))
            if missing:
                sys.stderr.write("; ".join(missing))
                sys.exit(1)
          PY

          result = Scout::Testing::Availability.run_command(
            [executable, '-c', probe, *modules], timeout: PROBE_TIMEOUT
          )
          return nil if result.success? && result.exit_status == 0

          detail = result.stderr.to_s.strip
          detail = "python exited #{result.exit_status}" if detail.empty?
          detail = "python timed out after #{PROBE_TIMEOUT}s" if result.timed_out
          detail = result.launch_error if result.launch_error
          detail
        end

        # --- R probes: REFERENCE ONLY ---
        # No live call sites in scout-rig today. Keep the code, do not wire
        # it into unit tests until an R integration exists.

        def rscript?
          executable = rscript_executable
          return false unless executable

          result = Scout::Testing::Availability.run_command(
            [executable, '--vanilla', '-e', 'cat("ok")'], timeout: PROBE_TIMEOUT
          )
          result.success? && result.exit_status == 0
        end

        # defect 7: package names as argv via commandArgs(TRUE).
        def r_packages?(*packages)
          !r_packages_reason(*packages)
        end

        def r_packages_reason(*packages)
          executable = rscript_executable
          return 'no Rscript executable found' unless executable
          return nil if packages.empty?

          probe = <<~R
            args <- commandArgs(TRUE)
            # `--args` itself is retained as the first element when the
            # interpreter is invoked as `Rscript -e ... --args pkg1 pkg2`.
            pkgs <- args[args != "--args"]
            missing <- character(0)
            for (p in pkgs) {
              if (!requireNamespace(p, quietly = TRUE)) missing <- c(missing, p)
            }
            if (length(missing) > 0) {
              cat(paste(missing, collapse = ", "))
              quit(status = 1)
            }
          R

          result = Scout::Testing::Availability.run_command(
            [executable, '--vanilla', '-e', probe, '--args', *packages],
            timeout: PROBE_TIMEOUT
          )
          return nil if result.success? && result.exit_status == 0

          detail = result.stderr.to_s.strip
          detail = result.stdout.to_s.strip if detail.empty? # R writes to stdout here
          detail = "Rscript exited #{result.exit_status}" if detail.empty?
          detail = "Rscript timed out after #{PROBE_TIMEOUT}s" if result.timed_out
          detail = result.launch_error if result.launch_error
          detail
        end
      end
    end
  end
end
```

### If scout-essentials cannot be a dependency

Apply the same four corrections in a local bounded runner (this is the shape
`Scout::Testing::Availability.run_command` implements; reproduce only what is
needed):

```ruby
def run_bounded(argv, timeout: 30)
  out_r, out_w = IO.pipe
  err_r, err_w = IO.pipe
  stdout = +''
  stderr = +''
  # defect 4a/4c: drain BOTH pipes concurrently, always, including when the
  # caller does not want the output captured.
  readers = {
    out_r => stdout, err_r => stderr
  }
  pid = nil
  begin                       # defect 4b: spawn INSIDE the rescue scope
    pid = Process.spawn(*argv, out: out_w, err: err_w, pgroup: true)
  rescue StandardError => e   # launch failure is a fact, not an exception
    [out_r, out_w, err_r, err_w].each { |io| io.close rescue nil }
    return Struct.new(:success, :exit_status, :stdout, :stderr, :launch_error, :timed_out)
             .new(false, nil, '', '', "#{e.class}: #{e.message}", false)
  ensure
    out_w.close rescue nil
    err_w.close rescue nil
  end

  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  threads = readers.map do |io, buf|
    Thread.new { io.each_line { |l| buf << l } }
  end
  timed_out = false
  status = nil
  until status
    _w, st = Process.waitpid2(pid, Process::WNOHANG)
    if st
      status = st
      break
    end
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      timed_out = true
      Process.kill('TERM', -pid) rescue nil
      sleep 0.1
      Process.kill('KILL', -pid) rescue nil
      status = Process.waitpid2(pid).last
      break
    end
    sleep 0.05
  end
  threads.each(&:join)
  [out_r, err_r].each { |io| io.close rescue nil }
  Struct.new(:success, :exit_status, :stdout, :stderr, :launch_error, :timed_out)
        .new(!timed_out && status.exitstatus == 0, status.exitstatus,
             stdout, stderr, nil, timed_out)
end
```

### Memoization discipline

Memoize each probe keyed on its full input set — for these probes that is
`(executable, modules/packages, timeout)`, since `SCOUT_TEST_PYTHON` or `PATH`
can change between calls in one process. Provide an explicit
`ScoutRig::Testing::Availability.reset!` and call it from test setup when the
environment is manipulated. Rescue `StandardError`, never `Exception`
(defect 3): a `SignalException` must not be cached as "unavailable".

## Interpreter-selection matrix

scout-rig has **two Python routes** (per `user/PythonEnvironments.md`):

| Route | How the interpreter is chosen | Notes |
|---|---|---|
| Embedded (PyCall) | `ScoutPython.run*` reads `ENV['PYTHON']`, else PATH `python3`/`python`; `PyCall.init` **sets `ENV['PYTHONHOME']`** | Mutates process env; affects everything spawned afterwards |
| Subprocess (`ScoutPython.script` / `run_file` / `python_task`) | literal `'python'` from PATH + `PYTHONPATH` augmentation; **ignores `ENV['PYTHON']`** | Splits from the embedded route: the two can silently use different interpreters |

**Setting `ENV['PYTHON']` alone breaks subprocesses** ("Failed to import
encodings"): the subprocess gets a `PYTHONHOME` pointing at the embedded
interpreter while running a different one. The reliable recipe, which the
reference probes inherit for free by resolving one executable name and passing
it as argv:

> Put the chosen environment's `bin` directory **first on PATH**, and let each
> route resolve the same interpreter from PATH; set `SCOUT_TEST_PYTHON` (or
> `SCOUT_TEST_RSCRIPT`) to pin an absolute interpreter for tests.

Never export `PYTHONHOME` from test setup.

## Motivation: the torch `test_binding` failure

scout-rig's suite is currently 9 tests, and `test_binding` hard-fails on stock
environments because it requires **torch**, which is not a declared dependency.
This is exactly the case a `python_modules?(:torch)` guard exists for: the test
should omit with `python_modules_reason(:torch)` when torch is absent, instead
of erroring. Its `test_helper.rb` has no interpreter selection or skip logic
today — add the `SCOUT_TEST_PYTHON`/PATH recipe above plus the guard.

"Guarded with `python_modules?`" means adding the omit and the reason message,
**not** adding torch to the gemspec or the README prerequisites.

## Constraints

- Ordinary unit tests stay **offline**; these probes only execute local
  interpreters and never touch the network.
- **Product-failure assertions must never become skips**: a probe may omit a
  test when an optional dependency is genuinely absent; it must not convert a
  regression in shipped code into a quiet omission. `rscript?`/`r_packages?`
  are reference-only until an R integration exists — do not wire them into
  unit tests.
- Keep the layer boundary: no endpoint/model/accelerator probes in scout-rig;
  those live in scout-ai (see `testing-availability-scout-ai-handoff.md`).
