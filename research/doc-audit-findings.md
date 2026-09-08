# Forensic doc audit of scout-essentials — final findings (durable report)

Audit target: `/bulk/mvazque2/git/scout-essentials` (gem v1.8.8, HEAD `a0324a4`).
Outcome: `doc/` fully rewritten (17 pages) + 5 new pages + `README.md` rewritten;
Critic final gate: **ACCEPT_WITH_NOTES** (notes applied).
This file is the retained summary. Of the full evidence trail, the
durable parts still in the repository are
`research/behavior-probes.md` (66 behavior probes, executed
transcripts) and the three `research/implementation-inventory-*.md`
file:line inventories; the transient working directories
(`research/doc_audit/`, `tmp/critic/`) were removed after the audit
closed.

Disposition counts (coverage-matrix sections A–F, 238 rows): OK 3 · FIX 117 ·
EXPAND 67 · NEW_PAGE 27 · INTERNAL 6 · ELSEWHERE 13 · OUT_OF_SCOPE 6.

---

## (a) Major hallucinations discovered and corrected

59 confirmed false claims (coverage-matrix section E), grouped by theme:

**1. Invented APIs / nonexistent names (≈18).** Documented methods that do not
exist anywhere in `lib/` or the ecosystem: `Persist.lock(file){}` (API is
`Open.lock`), `Persist.save_job_run_info`, `CMD.add_tool` (real API
`CMD.tool(tool, claim, test, block, cmd)`), `Log.none` (only `Log::NONE`
exists), `TmpFile.tmp_dir` (real: `TmpFile.user_tmp`), `Path.map_order=`,
`Path#sync`, the `base[:results, :final]` `Path#[]` API, the `{PATH}` map
placeholder (exists only inside `Path.follow` rewriting), the `ANNOTATIONS`
constant (real: `@annotations` via `.annotations`), `MyMetadata.purge` (real:
`Annotation.purge`), `Log::Color`, `stream.join_callback <<` (real:
`add_callback`), `add_abort_callback`, `Open.pipe("a","b","c")` (takes no
args), `SOPT.get inputs: [...]`, `SOSOPT.input_descriptions` (typo),
`invert_grep` alone filtering at `Open.read` level, `deep_indifferent`.

**2. Inverted dependency graph (Architecture, 6+ rows).** Architecture.md had
ConcurrentStream above Open/Path/CMD (it is *required by* CMD and requires only
IndiferentHash), "Resource depends on Persist" / "produce acquires a Persist
lock" (no reference; the lock is `Open.lock` on `Resource#lock_dir`), "Open/CMD
depend on TmpFile" (TmpFile requires Open), and a phantom "extend `Log::Color`"
extension point. Rewritten from verified `require` edges.

**3. Wrong data types / return values (≈12).** `Persist.cache_dir`/`lock_dir`
"# => #<Path ...>" (both plain Strings), `find` "returns nil when nothing
resolves" (never nil — it falls through the map order), serialization types
`:array/:path/:file/:string_array` with invented semantics (rebuilt from
serialize.rb), `annotated_str.is_a?(MyAnnotation) # => false` (it is true),
`annotation_types.include?("MyAnnotation")` (entries are module objects),
`values.count` as a field accessor (plain `Array#count`), `zip` "propagates
annotations" (drops them), fabricated output "S003 (Human, Lua)" (prints
`(Human, Liver)`), "`Persist::Path` appends the serialization type to the
filename" (no suffix is ever appended).

**4. Fabricated semantics for real methods (≈15).** Abbreviated default
`map_order` (13 real entries), `persistence_path(name, :marshal)` positional
type (options-hash only), `save_drivers`/`load_drivers` as constants (accessor
hashes), `claim self.data.file` `self.`-prefixed paths and block-only
`claim do ... end` (type mandatory), "extend `Resource.produce` for new claim
types" (hard-coded `case`), `io.exit_status` reliable post-join (normally nil;
only `join_pids` sets it), CMD block "runs post-join" (accepted, never
invoked), progress bar "shows ETA" (elapsed + rate), `Log.debug "msg" do ... end`
"logs elapsed time" (lazy message evaluation), `with_obj_bar{|bar, item|}`
two-arg block (bar only), SOPT `=value` defaults and "`*` marks required"
(`*` = string-valued; `SOPT.require` enforces), `class MyPersist < Persist`
"wrong style" example (raises TypeError — Persist is a Module), "resources are
always released, even on error" (`TmpFile.with_file` leaks on raise), "always
pair method_missing with respond_to_missing?" (none in lib/), NamedArray "a
String with a name" / "NamedArray extends AnnotatedArray" (it does not),
**`dup` and `clone` both lose annotations — only `dup` loses; `clone` keeps
them** (clone copies the singleton class), "nested hashes are automatically
IndiferentHash" (plain Hash).

**5. Misdescribed streaming model (StreamingModel/HandlingStreams, 6+).** "CMD
creates paired stdout/stderr streams" (pairs are pipe ends; stderr is a thread),
"paired streams are joined on cleanup" (`join` never touches `@pair`), "Log
writes to the stream's paired stderr" (logfile/STDERR; per-stream capture is the
`std_err` attribute). Also the two synthesis-level artifacts: `Persist` is
*name*-based, not "content-addressed caching" (keys are names + option digests),
and `Open.read_stream`'s documented IO.select/Thread.pass loop was the **dead
first definition** (stream.rb:382-399); the effective method (stream.rb:401) is
a plain blocking read of exactly N bytes — same observable contract, corrected
in the final pass.

Top examples (doc:claim → actual): `find` nil-returns → never nil ·
`Persist.lock` → `Open.lock` · `save_drivers` constants → accessor hashes ·
paired stderr streams → pipe ends + stderr thread · `clone` loses annotations →
only `dup` does · invert_grep filters alone → no-op without `grep`.

---

## (b) Major omissions discovered and documented

From the 67 EXPAND rows and 27 NEW_PAGE rows.

**Five subsystems had no doc home at all** → new pages created:
1. `doc/developer/Configuration.md` — `Scout::Config` token-priority resolution
   (`workflow`4 > `task`3 > `file`2 > `line`1; `key:` = 20 = lowest; explicit
   `::N` wins), `etc/config` line format, `:env`/`env:VAR` values,
   `with_config` snapshot/restore, `process_config`, no-mutex caveat.
2. `doc/developer/ErrorHandling.md` — 20-class exception taxonomy, control-flow
   signals deriving from `Exception` not `StandardError` (`StopInsist`,
   `DontClose`, `DontPersist`, `KeepLocked`, `KeepBar` — a bare `rescue =>` will
   NOT catch them), `canfail`/`no_fail`, abort protocol.
3. `doc/developer/LockingAndConcurrency.md` — vendored `Lockfile` (Ara T. Howard
   v2.1.8, modified; guarded `unless defined?`), `Open.lock`/`LockInterrupted`,
   the **three distinct lock namespaces** (`Persist.lock_dir` + `.persist`
   suffix; `Resource#lock_dir` with TmpFile-digest names;
   `sensible_write_lock_dir`), KeepLocked streaming persistence, fork model,
   thread-safety caveats.
4. `doc/developer/CoreUtilities.md` — TmpFile naming conventions (`·` U+00B7
   per `/`, `PREFIX:`, `[key]`, `&F[m=<digest(value)>]` + `:md5` tail,
   `MAX_FILE_LENGTH` 150), IndiferentHash instance protocol, Misc format/timespan/
   digest/insist families, Hook (not auto-required), `NamedArray`/`Hook` explicit
   require.
5. `doc/user/RemoteData.md` — `Open.remote?`/`ssh?`, wget cache (`var/cache/open-remote`,
   digest over url+post data; no TTL), `:force` behaviour (raises OpenURLError,
   does not touch cache), ssh/scp/rsync, `Open.wait` `LAST_TIME` rate limiter.

**Biggest in-page gaps (EXPAND) now filled:**
- `update:`/`check:` cache staleness invalidation (persist.rb:41-47) — the single
  most useful persistence feature, previously entirely absent.
- `save_stderr` three shapes (commit `ee24c68`): `true` → `std_err`; a file path
  (CMD opens/truncates, creates parent dirs, line-buffered so `tail -f` works);
  any IO-like (written+flushed, never closed). Old docs only showed
  `save_stderr: true`.
- TmpFile naming + `$HOME/tmp/scout/tmpfiles` root with `tmpdir=` override; the
  three lock namespaces, previously conflated into one.
- Annotation mechanics: `setup` extends in place (same object unless frozen),
  `@produced` tri-state latching on `Path#produce`, `serialize` → plain Hash,
  Marshal round-trip, `dup` vs `clone`.
- `:memory` + `MEMORY_CACHE` + `Persist.memory("key", key:)`, `TRUE_STRINGS`
  (13 spellings), `:serializer == :json` default, `Open.json`/`Open.yaml`
  `find_with_extension` fallback (`:yaml` load may return a Psych AST node).
- Log: severity constants, `Log::LAST` protocol, `with_severity`, `fingerprint`,
  `Log.logfile` no-arg call *resets* the logfile, `SCOUT_NOCOLOR == 'true'`
  exact string, ProgressBar YAML resume, `percent == 100` when `max == 0`.
- SOPT: `*` = string-valued, `SOPT.require` enforcement, destructive `consume!`,
  `## SYNOPSYS` (sic) header, partial `reset`.
- CMD: `CMD::Timeout`, `:in`/`:in_pipe`/`:post`/`:wait`/`:canfail`/
  `:empty_inputs`/`:separator`, pipe-mode timeout via stream abort, default
  stderr severity `Log::DEBUG`.
- Path: `find_all`/`glob_all`, `@where`/`@original`, `identify`, `relocate`,
  `#read`/`#open` produce first but `#write` does not, `method_missing` segment
  building (`Scout.etc`), explicit `require 'scout/named_array'`.
- Resource: `rake_dirs` + `ScoutRake.run` fork model, `share/software` +
  `install_helpers`, `Resource.install`.

---

## (c) Important concepts that remain undocumented, with reasons

**Dead / unreachable code — documented as known limitations, not as API:**
- First `Open.read_stream` definition (stream.rb:382-399, IO.select/Thread.pass
  loop) — shadowed by the second def at :401; never reachable.
- Dead `Open.read_stream` duplicate + commented-out `sort_stream` (stream.rb:442-444).
- `Open.append` instance method (dead); docs teach `mode: 'a'` instead.
- `Open.notify_write` is a silent no-op in an essentials-only install (`Misc.notify`/
  `send_email` are not defined here — see (d)); noted, not taught.
- `Open.with_fifo` cannot clean a pre-existing path (`File.rm` NoMethodError) —
  listed as a known limitation.

**Kept as INTERNAL footnotes (not user-facing guarantees):**
- `Scout::Config` legacy rbbt caller-token regexes (`file:`/`line:` frames rarely
  filtered by scout code) — implementation residue; explaining them in user docs
  would document dead parsing branches.
- `Scout::Config` has no mutex around the shared CACHE — recorded as a known gap
  in LockingAndConcurrency rather than as behaviour to rely on.
- `Misc` double definitions (`counts` defined twice), `intersect_sorted_arrays`
  mutating its args, `file_md5` fallback hashing the *path string* rather than
  content — all noted as code-health items, none is a documented guarantee.
- `Persist::CONNECTIONS` registry — internal plumbing.

**OUT_OF_SCOPE (by design):**
- The stale gemspec doc manifest (lists 12 nonexistent `doc/*.md` files). This is
  a maintenance task (`rake gemspec` regeneration), not a documentation issue;
  left open and flagged rather than claimed fixed.
- Cross-repo surfaces that this repo must not teach (see (d)).

---

## (d) Functionality previously attributed to this repo that is implemented elsewhere

From coverage-matrix section F + `research/ecosystem-attribution.md` (every row
verified by locating the defining line or the require/dependency edge, never by
name alone):

| concept | actually implemented in | key evidence |
|---|---|---|
| `TSV` class, `TSV::Dumper` | **scout-gear** | `GEAR/lib/scout/tsv.rb:17`, `tsv/dumper.rb:2` |
| `Annotation.tsv` / `Annotation.load_tsv` (hence the `:annotation` Persist serializer) | **scout-gear** (reopens essentials' Annotation) | `GEAR/lib/scout/tsv/annotation.rb:46,127`; essentials' serialize.rb:37-38,74-75 call it without requiring it → NoMethodError standalone |
| `Workflow` / `Task` / `Step` | **scout-gear** | `GEAR/lib/scout/workflow{,_task,_step}.rb` |
| `.info` Step blob format read by `Open.mtime` | **scout-gear** | essentials `open/final.rb:147-150` calls `Persist.load(info_file, Step::SERIALIZER)` — a gear constant, never required |
| Scheduler / HPC (SLURM/PBS/LFS/orchestrator) | **scout-gear**; **scout-camp** only adds cloud/terraform deployment (its bin loads gear's `bin/scout`) | `GEAR/.../deployment/scheduler/{slurm,pbs,lfs}.rb`; `CAMP/lib/scout-camp.rb` |
| `Misc.notify` / `Misc.send_email` | **legacy rbbt-util only** (no scout gem defines them) | `RU/lib/rbbt/util/misc/communication.rb:15,48` |
| `Bgzf` / bgzip path of `Open.bgunzip` | **legacy rbbt-util only** | `RU/lib/rbbt/util/misc/bgzf.rb:5` |
| `deep_indifferent` | **exists NOWHERE** (0 grep hits across essentials, gear, ai, rig, camp, rbbt-util 6.0.5) | ecosys #5 |
| CLI `bin/scout` / `scout_commands/` dispatch | **scout-gear** (+ per-gem command dirs) | `GEAR/bin/scout` |
| rbbt-util 6.0.5 `require_instead` shims (30 files redirecting rbbt requires onto scout files) | **rbbt-util**; direction UNVERIFIED at gemspec level | `RU/lib/rbbt/util/misc/indiferent_hash.rb` |

Genuinely local (for contrast): `ScoutRake`/`rake_dirs` (gear does not use it),
`Scout.etc` mechanism, `share/software` + `install_helpers`, Path/Resource/
Persist/Open/CMD/Log/SOPT/TmpFile/IndiferentHash/NamedArray/Misc/Annotation core,
vendored Lockfile, `Scout::Config`.

Dependency direction: scout-gear and scout-camp *declare* essentials;
scout-rig requires it in code but **omits the gemspec edge**; scout-ai reaches it
only transitively. Conversely essentials silently depends *upward* on gear types
(TSV, Step::SERIALIZER) and legacy rbbt-util methods for the items above — no
scout-family or rbbt-family runtime dependency is declared at all
(term-ansicolor, yaml, rake, listen only).

---

## (e) Significant inter-document inconsistencies corrected

From the critic gates (`tmp/critic/gate1|gate2/report.md`, final
acceptance notes) and the phase-6 consistency audit:

- **invert_grep no-op example** (WorkingWithFiles) — the rewrite claimed
  `Open.read(f, invert_grep: 'an')` filters lines; live probe shows it returns
  the whole file (`invert_grep` only takes effect together with `grep`; the
  underlying `Open.grep(io, 'an', true)` works). New regression caught by gate 1.
- **dup-vs-clone** — AnnotationSystem said *both* lose annotations; its own cited
  probe shows `clone` **keeps** them (clone copies the singleton class). Gate 2.
- **`&F[match={:m=>1}]` naming shape** (CoreUtilities) — real shape is
  `&F[m=c4ca4238a0b923820dcc509a6f75849b]:<md5-of-options>`; the value is
  *digested*, not inspected, and a `:md5` tail is appended. Gate 2.
- **`tmp_for_file` arity** (CoreUtilities) — `tmp_for_file('/a/b/c', :prefix =>
  'P')` raises NoMethodError (a Hash in the `tmp_options` slot); the runnable
  form is `tmp_for_file('/a/b/c', {}, :prefix => 'P')`. Gate 2.
- **`save_job_run_info`** (Cookbook) — nonexistent API pointing at a page that
  documents no such feature; sentence removed. Phase 6.
- **`TmpFile.tmp_dir`** (WorkingWithFiles) vs `TmpFile.user_tmp` (CoreUtilities)
  — two pages disagreed, one referenced a nonexistent method; unified on
  `user_tmp` (`$HOME/tmp/scout`). Phase 6.
- **`Log.none`** (LoggingAndProgress) — no such convenience method; ladder top
  expressed via the `Log::NONE` constant. Phase 6.
- **Terminology anchors now enforced tree-wide** — "pipe ends" (never "paired
  stdout/stderr streams"), `std_err` for the capture attribute, severity ladder
  `DEBUG LOW MEDIUM HIGH INFO WARN ERROR NONE`, bare `claim` (never
  `self.claim`), `find` never nil, drivers as accessor hashes.
- **Lock-dir examples** no longer hard-code a machine-specific home path
  (`$HOME/.scout/tmp/{persist,produce,sensible_write}_locks`), while the literal
  `·home·mvazque2·...probeD2` lock name is retained verbatim (it is actual
  `TmpFile.tmp_for_file` output) and now annotated as a machine-specific example
  value. Final pass.

---

## (f) Areas where the implementation is ambiguous and documentation remains uncertain

From `research/doc_audit/resumption-reference.md` §5 decisions and the
UNVERIFIED list:

- **AnnotatedArray Integer elements** — raise TypeError (`cm_aa2/3/4` probes);
  annotated arrays require extendable elements. Documented as a requirement plus
  an Improvements-style note; arguably a bug.
- **`AnnotatedArray#each_with_index` without a block** — NoMethodError. Treated
  as a bug; explicitly not promised in the docs.
- **IndiferentHash `"false"` coercion asymmetry** — `string2hash`/`parse_options`
  never coerce `"false"` to `false` (P20), while `Scout::Config.get` does.
  Documented as-is and flagged as a bug candidate.
- **rbbt-util dependency direction** — `require_instead` shims clearly *consume*
  scout files, but rbbt-util 6.0.5's installed tree has no readable gemspec, so
  the declared edge is UNVERIFIED. Kept flagged in Architecture's table.
- **NamedArray `key:` kwarg** — claimed, but the signature is `*args` with no
  kwarg handling; the claim was dropped rather than resolved.
- **Log severity env/file precedence** — both sources are real; resolved by probe
  (environment variables override the config file) and documented with that order.
- **Persist driver registry naming** — resolved: the accessor-hash form
  (`Persist.save_drivers` / `Persist.load_drivers`) is what the code uses;
  documented accordingly.
- **`ConcurrentStreamProcessFailed` clobber** — the exception carries
  `concurrent_stream => nil` in practice; documented as an unreliable attribute.
- **`Open.wgrep` / `Open.rgrep` claims** — nonexistent; removed from the docs.
- **`NamedArray` `key:` kwarg and Camp "job arrays"** — both remain UNVERIFIED in
  the research record (see `research/ecosystem-attribution.md` §UNVERIFIED).

---

## Post-audit state

- 22 doc files delivered (17 rewritten + 5 NEW_PAGE); README.md rewritten and
  gate-verified (all links resolve, getting-started snippet executable,
  abstractions table traced live).
- `doc/Improvements.md` deliberately **untouched** — it is a bug/improvement log,
  not documentation; its `deep_indifferent` guidance stays as a historical entry.
- Critic final verdict ACCEPT_WITH_NOTES; the three optional notes were applied:
  HandlingStreams `read_stream` mechanism sentence (stream.rb:401), README
  test-count parenthetical (49 files = 47 test files, one of which
  `test/scout/log/test_color.rb` is empty, + 2 `test_helper.rb`, one defining
  `TestMiscHelper`), and machine-specific-value annotations on the two remaining
  `/home/mvazque2` strings.
- Open maintenance items (not docs): regenerate the gemspec doc manifest;
  decide the fate of the untracked `test/scout/test_cmd_save_stderr.rb`.
- Nothing committed; `research/doc_audit/` retained pending user confirmation.
