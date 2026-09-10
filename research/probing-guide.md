# Probing guide — general advice for empirical Scout investigation

Promoted from the Cortex artifact `guides/probing.md` (v3, 2026-09-09).
Source of truth for future revisions remains the Cortex artifact; this
file is the in-research copy for agents that do not have the Cortex
workspace mounted. Cortex addresses cited below resolve in the
scout-essentials / scout-gear Cortex path maps.

Audience: any coding agent probing behavior in **any** Scout package or
workflow (scout-gear, scout-essentials, scout-ai, scout-camp, scout-rig,
installed workflows). This guide distills the frictions and successes of
the 2026-09-07/09 CortexCoder documentation-and-probing campaigns
(scout-essentials + scout-gear, 106 probe artifacts, 8 claims documents,
~7,600 bash and 60 `cortex_entity_property` calls across the session
chats), plus one new probe written to pin down the timeout mechanics.

Evidence is cited by Cortex address throughout. The guide is deliberately
general: subsystem-specific facts stay in the `scout-gear/*` claims
artifacts.

## 1. The ladder (unchanged, it works)

```text
uncertainty
 → tmp/ experiment (throwaway)
 → standalone run under an escalating timeout guard
 → probe/ artifact (versioned, commented, JSON-returning)
 → Observation/probe execution (receipt + registry record)
 → claims/ artifact (proposition, observed vs inferred, citations)
 → research / doc / test promotion
```

This was executed end-to-end twice and is the single most reliable
pattern in the corpus (`harness/cortex-coder-first-episode-review.md` F5).
Nothing below replaces it; everything below is how to avoid the
frictions the same corpus recorded.

## 2. Before writing a probe

- **Name the question first.** One probe answers one sharply-stated
  question ("does `WorkQueue#abort` leave `join` blocked?"), not "learn
  about concurrency". A probe that cannot be titled is a browsing
  session, not an investigation.
- **Check what is already known.** `cortex_list type=artifacts prefix=probe/`,
  `cortex_search`, and `cortex_activity` for the entity. Campaigns left
  106 probes behind; re-probing an answered question is the most common
  wasted motion.
- **Read the docs and the code path before probing.** Probes are for
  *resolving* disagreement between doc, code and expectation — state in
  the probe header which doc sentence the question came from.
  (`probe/persist_engine_selection.rb`, `probe/assoc_field_specs.rb` are
  good templates: they quote the doc claim being tested.)
- **Record the environment you are testing.** Live checkout vs installed
  gem (`-Ilib` vs plain `ruby`), HEAD hash, RUBY_VERSION. Campaign
  artifacts drifted between batches because line numbers and HEAD moved
  (`scout-gear/overview.md` open item 6); re-pin before quoting line
  numbers.

## 3. Probe anatomy

Follow the doctrine header, proven in the corpus:

```ruby
# Observation: <snake_case_name>
#
# What it investigates
# Why it matters
# Assumptions / conditions   (environment, isolation, what is NOT tested)
# Result kind                (JSON object with these keys: ...)
```

Rules that emerged as load-bearing:

- **Return one JSON-serializable object with string keys.** Every key you
  intend to cite from a claim should be a distinct result key; claims
  cite `Observation/probe/<job>.json` *key names*
  (`scout-gear/concurrency.md` does this per claim).
- **Rescue each section independently** so one failure does not hide the
  rest; collect per-section errors into an `errors` key instead of
  letting the probe die (`probe/entity_persisted_property_invalidation.rb`).
- **Put the `puts JSON.pretty_generate` at the end AND return the
  object** — standalone runs need stdout, property runs need the return
  value.
- **Errors are results.** Capture `"#{e.class}: #{e.message[0, 60]}"`,
  not just a boolean. The class/message pair is usually the interesting
  fact (see `fork_each_raises` in the semaphore probe).

## 4. Determinism and isolation

- **No network. Fixed tmpdirs. Close everything you open** (databases,
  semaphores, sockets, queue dirs). Scratch under `tmp/probe_<name>_<pid>`
  or `Dir.mktmpdir`, and remove it in the same run.
- **Prefer sleep-free observation.** Where you need timing facts, read
  recorded trace timestamps (`Workflow.trace_job_times`) instead of
  sleeping (`probe/deploy_local_end_to_end.rb`). Where you need
  cache-hit vs recompute, use `rand` inside blocks so the two are
  distinguishable without delays.
- **Isolate global state before declaring anything.** If the library
  keeps process-global caches (`Entity.entity_property_cache`,
  `Entity.formats`), reassign them to a tmpdir *before* registering
  modules/properties — several defaults are captured at declaration
  time (`probe/entity_persisted_property_invalidation.rb`).
- **Isolate the user environment.** For CLI/load-path probes pass
  `HOME` = fresh tmpdir so per-user config cannot mask the failure you
  are testing (`probe/cli_process_trace_broken_commands.rb`).
- **Normalize environment artifacts before claiming.** Anonymous module
  names (`#<Module::…>::M9::AA`), PIDs, tmpdir paths, timestamps differ
  between runs — compare shapes and counts, not raw strings
  (`probe/wf_remote_step_api.rb` notes this explicitly: "an environment
  artifact, not a behavioral difference").
- **Scope claims to what you ran.** Report `RUBY_VERSION` and the
  interpreter (MRI/GVL) when concurrency semantics depend on it
  (`probe/entity_formats_registry_concurrency.rb`).
- **Make rare interleavings deterministic by widening the window** (alias
  patch around a check-compute-write-back), and *label it as an exhibit*
  in both the probe and the claim — an exhibit proves the interleaving
  exists, not that it occurs at stock timing.

## 5. The execution environment (bwrap / property sandbox)

Probe bodies are `eval`ed by `Observation/probe` with `self` = a Scout
Step, and tasks run under bwrap. Facts that cost the campaigns real
debugging time:

- **`include` is unavailable** at top level (`NoMethodError: undefined
  method 'include' for #<Step>`). Use modules explicitly:
  `FU = FileUtils; FU.mkdir_p …` (`probe/persist_engine_selection.rb`).
- **`Kernel#include`-style sugar and some constants resolve differently.**
  Prefer explicit `Process.clock_gettime(Process::CLOCK_MONOTONIC)`
  forms over constants; define helpers as plain `def`s (they work).
- **Modifier-rescue precedence can make a body unparseable** in the
  eval context: `File.read(lp).split… rescue []` inside a hash literal
  broke `cli_preprocess_flags` until rewritten flat. Keep hash-literal
  contents rescue-free (`scout-gear/cli.md` §7, v3→v4 fix).
- **Sandbox and plain-ruby values can differ.** The first episode
  recorded `join_pid_fail*` differing between bwrap and plain ruby.
  Never claim a value you only measured in one environment when the
  question is about the other; state both, or say which one you ran.
- **Writability is layered**: the Ruby allowlist (read/write tasks) and
  the bwrap mounts (bash/ruby/python) are different sets. When a path is
  rejected, call `sandbox_paths` instead of guessing
  (the campaign repeatedly re-discovered which repo tmp dirs were bound).

## 6. Blocking, forking, and timeouts — the F1 class

The one friction that hung real executions. General rules:

- **Single-process by default.** Do not fork/join in probe bodies unless
  the question *is* about forking. Static/no-fork variants answer most
  questions (`wq_lifecycle_static` vs `wq_fork_run` split).
- **A forking probe must graduate:** standalone first, 3/3 clean runs
  under the escalating guard, every blocking `join` boxed in
  `Timeout.timeout(k) { … }`, executed through the property exactly once
  (`probe/wq_fork_run.rb` header is the template;
  `scout-gear/concurrency.md` "Probe discipline note").
- **Always use an escalating guard, never bare `timeout N`:**
  `timeout --kill-after 5 60 ruby probe.rb`. Measured fact: against a
  child that traps SIGTERM — exactly what forked Scout workers and
  rescuing loops do — plain `timeout 2` let the child run to natural
  exit (8.12 s under a 2 s bound) **while still reporting exit 124**, so
  the guard lies; `--kill-after 1 2` killed it at 3.01 s with SIGKILL
  (`Observation/probe/shell_timeout_kill_after_…3940752058….json`,
  `claims/timeout_kill_after.md`). Keep the escalation short relative to
  the bound.
- **Put the guard on the leaf command.** Nested timeouts do not compose:
  the outer KILL reaches only its direct child, and a trapping
  grandchild survives (measured: 8.12 s under a 2 s outer guard). Do not
  wrap a wrapper.
- **Do not trust exit status 124 as proof of a bounded run** — check
  elapsed time or wrap the measurement yourself.
- **Property execution has its own bound** (default 3600 s, no progress
  signal). For probe-shaped bodies pass a short per-call `timeout:` to
  `cortex_entity_property`. A hung probe inside a property is invisible
  from the outside until the bound fires; the first-episode branch that
  hung simply stopped making tool progress (F1).
- **Hung probes vanish from the transcript.** Killed executions leave no
  completed tool output, so chat-level latency analysis shows nothing —
  the evidence of a hang lives in harness reviews and forced-re-run
  records. If a run "disappeared", suspect a hang, not a skip.

## 7. Property execution and caching subtleties

- **Standalone first, then property.** The standalone run is your
  pre-flight (parses, terminates, produces JSON); the property run is
  your receipt.
- **Editing a probe artifact does NOT auto-invalidate its property job.**
  The Step is content-addressed on entity + arguments + definition
  identity — not on artifact contents, which are read by `eval` at run
  time. After editing `probe/<name>.rb`, re-run with `update: true` or
  you will be reading a stale cached result while believing you tested
  the new body (observed live this session: v3 result served after the
  v4 edit until `update: true` forced recompute).
- **Check the receipt:** `definition_version`, `definition_digest`,
  `property_job` and the artifact `version` in `content` should match
  what you wrote. A `version` in the receipt that lags your edit is the
  stale-cache signature.
- **Registry records accumulate**: `cortex_list type=properties` /
  `cortex_activity` show run counts and last-run times — cheap way to
  check whether a probe has ever been executed and against which
  definition version.

## 8. Negative probes

Deliberate failure probes are first-class evidence (77 of the first
episode's tool-call failures were intentional):

- Test the documented error path, not only the happy path: unknown
  workflow/task, missing args, broken `require`s, worker-block raises,
  `abort` after `close`. Capture exit status + first stderr signature
  (`probe/cli_dispatch_and_surface.rb`, `cli_process_trace_broken_commands`).
- A `require` that fails in a stock install is a stronger statement than
  "has a bug" — say which level failed.
- Keep negative probes as *separate, tiny* probes or clearly-keyed
  sections, so a claim can cite "exit_status" keys without ambiguity.

## 9. Debugging a failed property run

- **Bisect wrapper pattern:** when a probe works standalone but fails in
  the property context, run its lines cumulatively in the property
  context to find the exact failing statement
  (`probe/tmp_open3_sanity.rb` — returns the failing line number, code
  and error).
- Read the Step files the receipt points at before re-running anything;
  re-running blind is the expensive habit.
- The two-layer sandbox (§5) explains most "works in bash, fails in
  read" mysteries — `sandbox_paths` settles it in one call.

## 10. Evidence discipline

- **Never transcribe numbers a probe can return.** Claims cite the
  property job and the result keys; humans (and later agents) re-run
  rather than trust copy-paste.
- **Separate observed from inferred.** The claim format that worked:
  proposition → *Observed* (probe evidence, exact keys) → *Inferred
  rule* (scoped, justified) → *Docs impact* (gap/correct/wrong).
  Code-reading-only findings are labelled as such and never mixed with
  runtime receipts (`scout-gear/concurrency.md` Claim marked
  "unprobed at runtime: cross-process effect").
- **One observation ≠ one universal claim.** Scope the rule to the
  environment, Ruby version, and code revision you measured.

## 11. Lifecycle

- Probes that support a durable claim stay under `probe/`; scratch and
  bisect helpers get deleted once their question is answered.
- A probe with a crisp failure signature can be promoted **into a
  regression test** in the target repo — prefer that over keeping an
  out-of-cortex behavior pinned only in Cortex.
- When the claims are promoted out of Cortex (docs/tests), the probe may
  be deleted; the property registry keeps the run history either way.
- Record cross-session harness learnings (hangs, concurrency, provenance
  gaps) under `harness/` — that is where the F1–F5 evidence lives and
  where this guide's timeout section came from.

## 12. Quick checklist before executing any new probe

```text
[ ] one named question, doc/code disagreement stated in the header
[ ] string-keyed JSON result; sections individually rescued
[ ] no network; fixed tmpdir; globals reassigned to scratch; cleanup
[ ] sleep-free where a trace/timestamp alternative exists
[ ] environment recorded (checkout vs gem, HEAD, RUBY_VERSION)
[ ] standalone run OK under: timeout --kill-after 5 60 ruby probe.rb
[ ] forking only if the question needs it; joins boxed in Timeout.timeout
[ ] property run with a short per-call timeout; receipt version matches
[ ] after editing the artifact: re-run with update: true
[ ] claim cites property_job + result keys; observed vs inferred separated
```

## Evidence index

- `claims/timeout_kill_after.md` +
  `Observation/probe/shell_timeout_kill_after_3940752058e155e185253a096bb3d07f.json`
  — the `--kill-after` mechanics (control / trap / kill-after / nested
  guard), written for this guide.
- `harness/cortex-coder-first-episode-review.md` — F1 (hang), F2
  (artifact edit races), F3–F4 (accounting/provenance), F5 (the ladder
  executed correctly).
- `harness/cortex-coder-second-episode-record.md` — corpus consumption
  and promotion decisions.
- `probe/wq_fork_run.rb`, `probe/wq_lifecycle_static.rb`,
  `probe/entity_formats_registry_concurrency.rb`,
  `probe/entity_persisted_property_invalidation.rb`,
  `probe/persist_engine_selection.rb`,
  `probe/cli_process_trace_broken_commands.rb`,
  `probe/deploy_local_end_to_end.rb`, `probe/tmp_open3_sanity.rb` —
  the pattern templates referenced above.
- `scout-gear/concurrency.md` (probe discipline note, abort/join hazard),
  `scout-gear/cli.md` §7 (sandbox parse failure),
  `scout-gear/overview.md` §5 (106-probe inventory & citation audit),
  `scout-gear/consolidation-survey.md` (rev drift, HEAD pinning).

### Where the session evidence lives (for future ChatAnalyst passes)

The `~/git/<repo>/chats/<name>` paths are not visible from inside the
sandbox; the same sessions persist as root chats under
`~/.scout/tmp/tmp-*.chat` (this campaign: `tmp-772567689` scout-gear CLI
owner, `tmp-869423640` scout-gear gap-closing, `tmp-725846580` /
`tmp-908860370` / `tmp-879155263` scout-essentials doc-review owners,
`tmp-171141240` scout-gear CLI batch 4, `tmp-373370430` scout-gear
consolidation, `tmp-72174883` synthesis). `chat_overview` /
`chat_tool_calls` / `provenance_relationships` work on those files
directly. Corpus stats extracted for this guide: `timeout` durations
used — 60 s ×350 (the norm), 30 ×82, 120 ×38, 90 ×9, 150 ×5, 300 ×2;
~207 non-zero bash exit statuses out of ~3,900 recorded (status 1 ×207
plus stray 231/235/240/246 — 246 is the WorkQueue abort exit code),
overwhelmingly deliberate negative probes; bash dominates the tool mix
(~7,600 calls) with `cortex_read` (384) second — probing in this stack
is a bash + Cortex discipline. No `--kill-after` appears anywhere in
the corpus: the guard discipline existed, the escalation half did not,
which is precisely the friction that motivated this guide.
