# Testing availability handoff — scout-ai

Provenance: salvage packet produced during the scout-essentials layering
cleanup (2026-10). scout-ai keeps the model/accelerator/endpoint probes that
were incorrectly drafted into scout-essentials. This note is self-contained:
verified call-site inventory, retention list, the 7-defect list with the
correction for each, a delegation example, the compat-adapter option, and
constraints.

## Verified call-site inventory (read-only pass over /home/mvazque2/git/scout-ai)

- `python_modules?`
  - `test/scout/model/python/test_torch.rb`
  - `test/scout/model/python/huggingface/test_classification.rb`
  - `test/scout/model/python/huggingface/causal/test_next_token.rb`
- `cuda?`
  - `test/scout/model/python/torch/test_helpers.rb`
- `hf_model_cached?`
  - `test/scout/model/python/huggingface/test_causal.rb`
  - `test/scout/model/python/huggingface/test_classification.rb`
  - `test/scout/model/python/huggingface/causal/test_next_token.rb`
- `hf_model_reason` — same three files as `hf_model_cached?` (omit messages).
- `rscript?`, `r_packages?`, `endpoint_reachable?` — **zero** call sites
  outside `test/support/availability.rb` itself.
- `endpoint_configured?('test')` — `test/integration/scout/llm/test_infrastructure.rb:30`.
- `test/support/infrastructure_probes.rb` — used by
  `test/integration/scout/llm/backends/test_endpoints.rb` and
  `test/integration/scout/llm/test_infrastructure.rb`;
  `test/integration/scout/model/test_base.rb` also uses `Availability`
  (specifically `r_packages?('e1071')` / `r_packages_reason`).
- `SCOUT_TEST_PYTHON` appears **only** inside `availability.rb`.
- `test/test_helper.rb` requires `support/fixtures` and `support/mock_backend`
  but **not** `support/availability`; each test file that needs it requires it
  directly (e.g. `test_causal.rb` documents the dependency).

## Layer table (what stays where)

| Probe / method | Layer | Destination |
|---|---|---|
| `executable?`, `run_command`, `tcp_reachable?` | scout-essentials | `Scout::Testing::Availability` (delivered, stdlib-only) |
| `cuda?` | scout-ai | `test/support/availability.rb` |
| `hf_model_cached?` / `hf_model_reason` (must honor `HF_HUB_CACHE`) | scout-ai | same |
| `endpoint_reachable?`, `endpoint_configured?`, `endpoint_reason`, `configured_endpoints`, `real_endpoints`, `endpoint_available?` | scout-ai | same |
| `InfrastructureProbes` | scout-ai | `test/support/infrastructure_probes.rb` — unchanged |
| `python?`, `python_modules?`(+reason), `rscript?`, `r_packages?`(+reason) | scout-rig | see `testing-availability-scout-rig-handoff.md`; scout-ai may still call them until its own suite stops depending on them (see note on `test_base.rb`) |

## Retention list (do not delete in scout-ai)

- `cuda?` — one live call site.
- `hf_model_cached?` + `hf_model_reason` — three live call sites; must honor
  `HF_HUB_CACHE`.
- `endpoint_reachable?`, `endpoint_configured?`, `endpoint_reason`,
  `configured_endpoints`, `real_endpoints`, `endpoint_available?` — endpoint
  family; memoization must key on the timeout argument.
- `InfrastructureProbes` — used by two integration suites; keep unchanged.

`rscript?`/`r_packages?` have exactly one live consumer
(`test/integration/scout/model/test_base.rb:12`, e1071) and no R integration
in scout-rig; keep them (reference-only, as in the rig handoff) until that
call site is either guarded by an R-availability decision or removed.

## The 7-item defect list with corrections

1. **`python?` ignores subprocess exit status.** A broken interpreter can
   still print. Decide on `exit_status == 0`, not on output presence.
2. **`python_modules_reason` reads stdout.** Import tracebacks go to stderr;
   read `result.stderr`, falling back to a synthesized reason when it is
   empty.
3. **`memo` rescues `Exception`.** Rescue `StandardError` only; timeout and
   launch failure are handled deliberately (recorded on the result), never
   swallowed. Never cache a `SignalException` as "unavailable".
4. **`run_bounded` drains stdout before stderr** (pipe deadlock with chatty
   children), **spawns before its rescue** (launch failure escapes), and the
   **`capture:false` path drains neither pipe**. Corrected shape: spawn inside
   the rescue scope; drain both pipes concurrently (reader threads) with a
   deadline; on timeout TERM the process group, wait a grace, then KILL;
   report launch failure as a structured result.
5. **`endpoint_reachable?` memoization ignores the timeout argument.** Key the
   memo on `(endpoint_or_host, port, timeout)` — a 2s probe and a 30s probe
   must not share an entry.
6. **HF cache lookup ignores `HF_HUB_CACHE`.** Resolve the cache root as
   `ENV['HF_HUB_CACHE']` (if set) else the default
   `~/.cache/huggingface/hub`, then check for the model directory
   (`models--<org>--<name>` with a snapshots dir) beneath it.
7. **Module/package names interpolated unsafely into Python/R source.** Pass
   them as argv to a fixed probe script, or use `Shellwords.escape` when a
   source string is unavoidable.

The corrected generic primitives (`executable?`, `run_command`,
`tcp_reachable?`) now live in scout-essentials'
`Scout::Testing::Availability`; defects 3 and 4 are already fixed there, so
the cheapest correct move for scout-ai is delegation (below) rather than a
local `run_bounded`.

## Delegation example

Reimplement scout-ai's internals on the primitives; keep behavior, drop the
local runner:

```ruby
# scout-ai test/support/availability.rb (revised)
require 'scout/testing/availability' # scout-essentials primitives

module Availability
  PROBE_TIMEOUT = 30
  CACHE_TIMEOUT = 300

  class << self
    # defect 3: StandardError only; explicit reset.
    def reset!
      @memo = {}
    end

    def memoized(key)
      @memo ||= {}
      return @memo[key] if @memo.key?(key)

      @memo[key] = yield
    rescue StandardError => e
      "probe error: #{e.class}: #{e.message}"
    end

    # defect 1 + 7: exit status decides; module names as argv.
    def python_modules?(*modules)
      !python_modules_reason(*modules)
    end

    def python_modules_reason(*modules)
      python = ENV['SCOUT_TEST_PYTHON'].to_s.strip
      python = 'python3' if python.empty? &&
                            Scout::Testing::Availability.executable?('python3')
      return 'no python executable found' if python.nil? || python.empty?

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
        [python, '-c', probe, *modules], timeout: PROBE_TIMEOUT
      )
      return nil if result.success? && result.exit_status == 0

      # Launch failure and timeout are the concrete reasons; otherwise the
      # trimmed stderr (defect 2), else the exit status.
      detail = result.launch_error
      detail ||= "timed out after #{PROBE_TIMEOUT}s" if result.timed_out
      detail ||=
        if result.stderr.to_s.strip.empty?
          "python exited #{result.exit_status}"
        else
          result.stderr.to_s.strip
        end
      detail
    end

    # defect 5: memo key includes the timeout.
    def endpoint_reachable?(name, timeout: PROBE_TIMEOUT)
      endpoint = configured_endpoints[name]
      return "no endpoint '#{name}' configured" unless endpoint

      host, port = endpoint[:host], endpoint[:port]
      key = [:tcp, host, port, timeout] # <-- timeout in the key
      hit = memoized(key) { Scout::Testing::Availability.tcp_reachable?(host, port, timeout: timeout) }
      hit ? nil : "endpoint '#{name}' (#{host}:#{port}) not reachable within #{timeout}s"
    end

    # defect 6: honor HF_HUB_CACHE.
    def hf_model_cached?(model)
      !hf_model_reason(model)
    end

    def hf_model_reason(model)
      cache = ENV['HF_HUB_CACHE'].to_s.strip
      cache = File.join(ENV['HOME'].to_s, '.cache', 'huggingface', 'hub') if cache.empty?
      dir = File.join(cache, 'models--' + model.tr('/', '--'))
      return "model #{model} not in cache (#{dir})" unless File.directory?(dir)

      snapshots = File.join(dir, 'snapshots')
      return "model #{model} cached but empty" unless File.directory?(snapshots) &&
                                                      Dir.children(snapshots).any?

      nil
    end
  end
end
```

The reason-selection block in `python_modules_reason` picks, in order: the
launch error, the timeout note, the trimmed stderr, and finally the exit
status.

## Compat-adapter option

If touching call sites is out of scope for the first pass, keep the existing
public method names and reimplement the internals:

```ruby
module Availability
  def self.endpoint_reachable?(endpoint_name, timeout: PROBE_TIMEOUT)
    host, port = resolve(endpoint_name)
    key = [:tcp, host, port, timeout]
    memoized(key) { Scout::Testing::Availability.tcp_reachable?(host, port, timeout: timeout) }
  end
  # same for any local bounded execution: delegate to
  # Scout::Testing::Availability.run_command
end
```

The four files with `python_modules?`/`cuda?`/`hf_model_cached?` call sites
keep working unchanged; the internals become the fixed primitives.

## Constraints

- **Never download models**: `hf_model_cached?` inspects the local cache only;
  absence reports a reason, it never fetches.
- Ordinary unit tests stay **offline**; integration tests may probe
  **configured** endpoints (that is their purpose).
- Product-failure assertions must never become skips: probes omit only on
  genuinely absent optional dependencies.
- Do not reintroduce interpreter/package probes into scout-essentials; the
  Python/R probes belong to scout-rig (see its handoff note), and the
  primitives layer is frozen at `executable?`/`run_command`/`tcp_reachable?`.
- scout-ai's `test/support/availability.rb` must keep the same public surface
  (`python?`, `python_modules?`/`_reason`, `cuda?`, `hf_model_cached?`/
  `_reason`, `endpoint_reachable?`, `endpoint_configured?`, `endpoint_reason`,
  `configured_endpoints`, `real_endpoints`, `endpoint_available?`,
  `InfrastructureProbes` unchanged) so the seven call-site files need no edits.
