# Phase 3 — Cross-repo ecosystem attribution (scout-essentials)

Date: 2026-02 (audit working copy)
Audit target: `/bulk/mvazque2/git/scout-essentials` (defines the `Scout` namespace).

## Evidence sources

| Repo | Where examined | Status |
|---|---|---|
| scout-essentials | `/bulk/mvazque2/git/scout-essentials` (worktree, VERSION 1.8.8) + installed gem `scout-essentials-1.8.8` | LOCAL, authoritative |
| scout-gear | installed gem `~/.rvm/gems/ruby-3.3.1/gems/scout-gear-10.12.2` (also 10.11.x, 10.12.1) | LOCAL (gem copy); the `/bulk/mvazque2/git/scout-gear` worktree is only bound for `tmp/` in this sandbox, so gem copies were used |
| scout-ai | installed gem `scout-ai-1.2.6` (gemspec stub says 1.2.5) | LOCAL (gem copy); worktree similarly `tmp/`-only |
| scout-rig | installed gem `scout-rig-0.2.6` | LOCAL (gem copy only) |
| scout-camp | installed gem `scout-camp-0.2.0` | LOCAL (gem copy only) |
| rbbt-util | installed gem `rbbt-util-6.0.5` | LOCAL (relevant for the refactor shim layer) |

Method: every attribution below was verified by locating the defining
`class`/`module` line, or the `require`/`add_runtime_dependency` edge — never by
name alone. File paths are gem paths; `SE = /bulk/mvazque2/git/scout-essentials`,
`GEAR = ~/.rvm/gems/ruby-3.3.1/gems/scout-gear-10.12.2`,
`AI = .../scout-ai-1.2.6`, `RIG = .../scout-rig-0.2.6`,
`CAMP = .../scout-camp-0.2.0`, `RU = .../rbbt-util-6.0.5`.

## Attribution table

| # | Concept | Implementing repo | Evidence (file:line) | Classification | Notes |
|---|---|---|---|---|---|
| 1 | `TSV` class | **scout-gear** | `GEAR/lib/scout/tsv.rb:17 module TSV` (required by `GEAR/lib/scout-gear.rb:2 require_relative 'scout/tsv'`) | PROVIDED_BY_DEPENDENCY (w.r.t. essentials) | Not present anywhere in `SE/lib`. essentials' `lib/scout-essentials.rb` never requires `scout/tsv` — hence the standalone `NameError`s in the P-probes. |
| 1b | `TSV::Dumper` | **scout-gear** | `GEAR/lib/scout/tsv/dumper.rb:2 class Dumper` (inside `module TSV`) | PROVIDED_BY_DEPENDENCY | The `when TSV::Dumper` branch that `SE`'s produce code tests can only be reached with scout-gear loaded. |
| 2 | `Annotation.tsv` / `Annotation.load_tsv` | **scout-gear** | `GEAR/lib/scout/tsv/annotation.rb:46 def self.tsv(objs, *fields)`; `:127 def self.load_tsv_values(id, values, *fields)` (also referenced at `:158`) | PROVIDED_BY_DEPENDENCY (reverse dependency: gear reopens essentials' Annotation module) | `SE/lib/scout/persist/serialize.rb:37-38` (`Annotation.tsv(content, :all).to_s`) and `:74-75` (`Annotation.load_tsv(TSV.open(serialized))`) call methods that only exist once scout-gear's `scout/tsv/annotation.rb` is loaded. → **CONSUMED_OR_INTEGRATED_HERE** for the caller side. The `:annotation` Persist serializer in essentials is therefore only functional inside the full scout stack. |
| 3 | `Workflow` / `Task` / `Step` / Job machinery | **scout-gear** | `GEAR/lib/scout/workflow.rb:17 module Workflow`; `GEAR/lib/scout/workflow/task.rb:8 module Task`; `GEAR/lib/scout/workflow/step.rb:16 class Step`; entry chain `GEAR/lib/scout.rb → require 'workflow-scout' → require 'scout-gear' + require 'scout/workflow'` | NOT_IMPLEMENTED_IN_ESSENTIALS / PROVIDED_BY_DEPENDENCY | Confirms the P-inventory: `SE` defines none of these. |
| 3b | `.info` file format read by `Open.mtime` | **scout-gear** | `GEAR/lib/scout/workflow/step.rb:6 SERIALIZER = Scout::Config.get(:serializer, :step_info, ...)`; `GEAR/lib/scout/workflow/step/info.rb:7 def info_file`, `:16 def self.load_info` | CONSUMED_OR_INTEGRATED_HERE | `SE/lib/scout/open/final.rb:147-150` reads `<file>.info` and calls `Persist.load(info_file, Step::SERIALIZER)[:]` — it hard-depends on scout-gear's `Step::SERIALIZER` constant while never requiring scout-gear. Same silent-coupling pattern as #2. |
| 4 | Scheduler / HPC / orchestration (SLURM, PBS, LFS, orchestrator rules, job arrays, `scout camp`) | **scout-gear** (SLURM/PBS/LFS/orchestrator) + **scout-camp** (infra provisioning) | SLURM: `GEAR/lib/scout/workflow/deployment/scheduler/slurm.rb:4 module SLURM` (sibling files `job.rb`, `lfs.rb`, `pbs.rb`); orchestrator: `GEAR/lib/scout/workflow/deployment/orchestrator/rules.rb:220` reads `Scout.etc.batch[...]`; camp: `CAMP/lib/scout-camp.rb`, `CAMP/lib/scout/{offsite,terraform_dsl,aws,render}.rb`, `CAMP/bin/scout-camp` (ends `load Scout.bin.scout.find`), `CAMP/scout_commands/{find,glob,offsite,sync,terraform}` | NOT_IMPLEMENTED_IN_ESSENTIALS | No scheduler/HPC/SLURM/camp code or docs exist in scout-essentials (grep over `SE/lib` and `SE/doc` returns nothing). Note `CAMP`'s HPC/scheduler layer itself is **thin** — `scout-camp`'s gemspec runtime deps are scout-essentials + aws-sdk-s3 + sinatra + terraform + mimemagic + omniauth (no scout-gear edge), and its bin simply loads scout-gear's `bin/scout`; the SLURM/PBS/orchestrator logic lives in gear. |
| 5 | `deep_indifferent` | **NOWHERE (in this ecosystem snapshot)** | grep `def deep_indifferent` across all installed scout gems + rbbt-util-6.0.5/lib → 0 hits. Only textual mention: `SE/doc/Improvements.md:85-89` ("deep_indifferent must be called explicitly") and the AnnotatingData ledger citing `Misc.deep_indifferent` | NOT_FOUND | `SE/lib/scout/misc.rb` requires only format/insist/digest/filesystem/monitor/system/helper/matching/math — no `misc/indiferent_hash` and no such method. `SE/lib/scout/indiferent_hash.rb` has `deep_merge` (line 21) but no `deep_indifferent`. rbbt-util 6.0.5's `lib/rbbt/util/misc/indiferent_hash.rb` is a **refactor shim**: `Rbbt.require_instead 'scout/indiferent_hash'`, i.e. it points *back* at essentials, so it cannot be the implementation either. Doc claim that this is available behavior is **stale/hallucinated**; only nested *access* works, and only incidentally (ledger C17). |
| 6 | `Misc.notify` / `Misc.send_email` | **rbbt-util (legacy), not scout-gear/ai/rig/camp/essentials** | `RU/lib/rbbt/util/misc/communication.rb:15 def self.notify`, `:29 def self.send_email_old`, `:48 def self.send_email` | CONSUMED_OR_INTEGRATED_HERE (implicit, no require) | `SE/lib/scout/open/util.rb:89-99` (`Open.notify_write`) calls `Misc.notify` / `Misc.send_email`; `SE/lib/scout/misc.rb` does not require any communication module, and no scout gem defines these. In an essentials-only install these are `NoMethodError`s (rescued by `rescue` in `notify_write`). rbbt-util's communication.rb is **not** a shim (it contains the real implementation), unlike its other files. So the definitions survive only in the legacy rbbt-util gem, outside the Scout stack proper. |
| 7 | `Bgzf` (bgzip/bgzf decompression) | **rbbt-util (legacy)** | `RU/lib/rbbt/util/misc/bgzf.rb:5 module Bgzf` (used at `:24`) | CONSUMED_OR_INTEGRATED_HERE (implicit, no require) | `SE/lib/scout/open/util.rb:35 Bgzf.setup stream` (in `Open.bgunzip`) references a constant that no scout gem defines. rbbt-util's `lib/rbbt/tsv/util.rb:112` even has the Bgzf branch commented out. Same pattern as #6: works only when legacy rbbt-util happens to be loaded. |
| 8 | `ScoutRake` / `rake_dirs` | **scout-essentials** | `SE/lib/scout/resource/produce/rake.rb:5 class Rake::FileTask` patch, `:25 module ScoutRake`, `def self.run`; `rake_dirs` registry in `SE/lib/scout/resource/produce.rb` (claim → `@rake_dirs[path]`), consumed at `produce.rb:127 when :rake` | IMPLEMENTED_IN_ESSENTIALS | Genuinely local. `rake` is a declared runtime dep (`SE/scout-essentials.gemspec:174`). scout-gear does NOT use `rake_dirs`/`ScoutRake` (0 hits in `GEAR/lib`), so this is currently essentials-only plumbing consumed by end-user Resource claims. |
| 8b | `Scout.etc` / `etc` path convention | **scout-essentials** (mechanism) — consumed by all | mechanism: `SE/lib/scout/resource/scout.rb:9 Path.load_path_maps(Scout.etc["path_maps"])` + `SE/lib/scout/config.rb:29 Path.setup("etc").config.find_all...`; `etc` is not a hard-coded map — `Path.method_missing` (`SE/lib/scout/path.rb:44-53`) + `Resource#method_missing` (`SE/lib/scout/resource.rb:69`) turn `Scout.etc`/`Scout.share` into path-joins resolved through the map registry (`SE/lib/scout/path/find.rb:84-100` path_maps incl. `:user => "{HOME}/.{PKGDIR}/..."`) | IMPLEMENTED_IN_ESSENTIALS | Downstream consumers confirmed: `AI/lib/scout-ai.rb:1-9`, `RIG/lib/scout-rig.rb:1-4`, `CAMP/lib/scout-camp.rb:1-9` all do `require 'scout' + require 'scout/path' + require 'scout/resource'` then `Path.add_path :<self>_lib, ...`; gear reads `Scout.etc.batch[...]` (`GEAR/.../orchestrator/rules.rb:220`). |
| 8c | `Scout.share.software` / `share/software` + `install_helpers` | **scout-essentials** (convention + assets) | `SE/lib/scout/resource.rb:7,16 require_relative 'resource/software'`; `SE/lib/scout/resource/software.rb:4 File.expand_path(Scout.share.software.install_helpers.find(:lib))`, `:7 def self.install(...)`; assets shipped in `SE/share/software/install_helpers`; software claim branch `SE/lib/scout/resource/produce.rb:138-141` (`self.root.software`, `Resource.install`, `set_software_env`) | IMPLEMENTED_IN_ESSENTIALS | scout-rig contains **no** `software`/`share/software` references (0 hits in `RIG/lib` + Rakefile), so the "rig relationship" is only the generic `Path`/`Resource` integration above, not a software-install one. |
| 9 | `Scout` module default resource (`Resource.default_resource = Scout`, pkgdir `scout`) | **scout-essentials** | `SE/lib/scout/resource/scout.rb:1-10` (`module Scout; extend Resource; self.pkgdir='scout'`; `Resource.default_resource = Scout`); `Path.default_pkgdir` `SE/lib/scout/path.rb:10-15` | IMPLEMENTED_IN_ESSENTIALS | `Scout.version` is the only thing scout-gear adds (`GEAR/lib/scout.rb:4-7`). |
| 10 | CLI binary (`scout`) and `scout_commands/` dispatch | **scout-gear** (bin) — plus per-gem command dirs | `GEAR/bin/scout` (loads scout_commands: alias, batch, cat, doc, entity, find, glob, kb, log, purge, rbbt, resource, system, template, update, workflow); `CAMP/bin/scout-camp` ends with `load Scout.bin.scout.find`; `CAMP/scout_commands/{find,glob,offsite,sync,terraform}`; `AI/bin/scout-ai` + `AI/scout_commands/{agent,llm,workflow}` | NOT_IMPLEMENTED_IN_ESSENTIALS | Matches inventory: essentials ships no bin/ and no scout_commands/. |
| 11 | IndiferentHash, Path.find/path_maps, Log, SOPT/SimpleOpt, CMD, Persist, Resource claims, Open, TmpFile, Annotation (core), NamedArray, Config | **scout-essentials** | `SE/lib/scout-essentials.rb` require list; per-file definitions in `SE/lib/scout/{indiferent_hash,path,log,simple_opt,cmd,persist,resource,open,tmpfile,annotation,named_array,config}.rb` (verified in Phase 1/2 inventories and re-checked here) | IMPLEMENTED_IN_ESSENTIALS | — |

## Dependency graph

### What scout-essentials depends on (runtime)

From `SE/scout-essentials.gemspec:172-175`:
`term-ansicolor`, `yaml`, `rake`, `listen`. Dev deps: shoulda, rdoc, juwelier.

That is: **no scout-family or rbbt-family runtime dependency at all.**
Everything scout-flavoured it touches (TSV, Step::SERIALIZER, Annotation.tsv,
Misc.notify/send_email, Bgzf) is reached *implicitly* without a require or a
gemspec edge — the "phantom integrations" documented above.

### Who depends on scout-essentials

Verified from installed gemspecs (grep `add_runtime_dependency`):

- **scout-gear** — yes. `GEAR/scout-gear.gemspec: add_runtime_dependency scout-essentials (>= 0)` (also in 10.11.6, 10.11.10, 10.12.1). Code edge too: `GEAR/lib/scout-gear.rb:1 require 'scout-essentials'`.
- **scout-camp** — yes. `CAMP/scout-camp.gemspec: add_runtime_dependency scout-essentials (>= 0)`; `CAMP/lib/scout-camp.rb:1-3 require 'scout'/'scout/path'/'scout/resource'` (which resolve to essentials' files, e.g. `SE/lib/scout/path.rb`, `SE/lib/scout/resource.rb`, `SE/lib/scout/resource/scout.rb`).
- **scout-rig** — **no scout-essentials edge in its gemspec** (`RIG/scout-rig.gemspec` runtime deps: `pycall` only), but **code-level dependency**: `RIG/lib/scout-rig.rb:1-4` requires `'scout'`, `'scout/path'`, `'scout/resource'` and calls `Path.caller_lib_dir`, `Path.add_path`; `RIG/lib/scout/python/paths.rb:26 add_paths(Scout.python.find_all)` uses essentials' Path machinery (and `RIG/lib/scout/workflow/python.rb:1 require 'scout/workflow'` needs scout-gear). So rig is a *declared* transitive consumer at best — the gemspec simply omits the constraint.
- **scout-ai** — **directly depends on scout-rig** (`AI/scout-ai.gemspec` runtime deps: scout-rig, ruby-openai, ollama-ai, ruby-mcp-client, hnswlib) and *transitively* on essentials via rig's runtime requires and via `AI/lib/scout-ai.rb:1-3 require 'scout'/'scout/path'/'scout/resource'` (0 direct mentions of scout-gear/scout-essentials in its gemspec). Its bin delegates to gear's CLI (`AI/bin/scout-ai`).
- **rbbt-util 6.0.5** — reverse-compat consumer: `RU/lib/rbbt/util/misc/indiferent_hash.rb` and 29 other files are two-line `Rbbt.require_instead 'scout/<path>'` shims redirecting rbbt requires onto essentials/gear files (`scout/persist/tsv`, `scout/resource`, `scout/workflow/step`, `scout/semaphore`, `scout/tmpfile`, `scout/tsv`, `scout/work_queue`, ...). Note this shim set targets the *whole* Scout stack, not only essentials, and rbbt-util's own gemspec is not readable at the audited path (gemspec file absent in the installed tree) → dependency *direction* for rbbt-util UNVERIFIED at gemspec level (see below).

### Graph summary

```
term-ansicolor/yaml/rake/listen
            ▲
   scout-essentials  (Scout namespace core: Path, Open, Log, Persist, CMD,
        ▲    ▲   ▲      Resource/claims, Annotation core, IndiferentHash, SOPT…)
        │    │   │ (runtime requires; rig/camp also declare the gemspec edge,
        │    │   │  rig's gemspec omits it)
        │    │   └────────────── scout-camp ──(bin loads)──► bin/scout (gear)
        │    └──── requires ──── scout-rig  ──(gemspec dep)─► scout-ai
        └─ gemspec+require ───── scout-gear (TSV, Workflow/Task/Step, HPC/
                                 scheduler, CLI bin/scout, scout_commands)
                                   ▲
                                   └── loaded by CAMP/bin, AI/bin

   legacy rbbt-util 6.0.5 ── require_instead shims ──► scout-essentials/gear
   (and keeps the only surviving definitions of Misc.notify/send_email, Bgzf)
```

### "Foundation of Scout and Scout-AI" — verdict

`SE/doc/StartHere.md:3-5` says essentials "is the foundation upon which Scout
and Scout-AI ... are built". As a **dependency-graph statement**:

- **TRUE for scout-gear ("Scout")** — direct gemspec + `require 'scout-essentials'` edge; gear builds TSV/Workflow/Step/HPC on top of it.
- **TRUE for scout-camp** — direct gemspec edge.
- **ONLY INDIRECTLY TRUE for scout-rig** — required in code, missing from rig's gemspec (omitted dependency).
- **TRUE for scout-ai ("Scout-AI")** — as a *transitive* dependency via scout-rig + its own `require 'scout'`; scout-ai has **no direct** dependency declaration on essentials.

So the claim is substantively correct but imprecise: essentials is the
namespace/foundation layer of the *whole* family, yet scout-ai (and rig) reach it
without declaring it, and several essentials features are themselves only
completable by scout-gear (see misattributions).

## Claims in scout-essentials docs that misattribute functionality

1. **Persist `:annotation` serializer presented as working** (`SE/lib/scout/persist/serialize.rb:37-38, 74-75`; documented in the data/persistence doc pages): the `Annotation.tsv` / `Annotation.load_tsv` / `TSV.open` it invokes are implemented in **scout-gear** (`GEAR/lib/scout/tsv/annotation.rb:46,127`; `GEAR/lib/scout/tsv.rb:17`), not in essentials, and are never required. Correcting attribution: *scout-gear*; standalone essentials raises `NoMethodError`/`NameError`.
2. **`Resource#produce` `:proc` / `:csv` claim types documented as usable** (`SE/lib/scout/resource/produce.rb`, branches testing `when TSV` / `when TSV::Dumper` before `when nil`, and `:csv` → "Not implemented yet"): the `TSV`/`TSV::Dumper` constants come from **scout-gear** (`GEAR/lib/scout/tsv.rb:17`, `GEAR/lib/scout/tsv/dumper.rb:2`). With gear absent, nil-returning procs crash with `NameError`. Correcting attribution: integration point with *scout-gear*, not an essentials feature.
3. **`Open.mtime` documented as a plain file-metadata helper**: `SE/lib/scout/open/final.rb:147-150` parses `<file>.info` with `Step::SERIALIZER` — `Step` and that constant are defined in **scout-gear** (`GEAR/lib/scout/workflow/step.rb:6,16`). Correcting attribution: essentials *reads* a **scout-gear Step** file format; the format is owned by gear.
4. **`Misc.notify` / `Misc.send_email` implied to exist** (`SE/lib/scout/open/util.rb:89-99` `Open.notify_write`): implemented only in **legacy rbbt-util** (`RU/lib/rbbt/util/misc/communication.rb:15,48`); no scout gem defines them. Correcting attribution: rbbt-util, and it is *not* a declared dependency of essentials.
5. **`Bgzf` / `Open.bgunzip` implied to work** (`SE/lib/scout/open/util.rb:35`): `Bgzf` is defined only in **legacy rbbt-util** (`RU/lib/rbbt/util/misc/bgzf.rb:5`). Correcting attribution: rbbt-util, undeclared.
6. **`deep_indifferent` (and the "call it explicitly" guidance)** — `SE/doc/Improvements.md:85-89`, plus the AnnotatingData ledger's `Misc.deep_indifferent` reference: **no implementation exists** in any audited repo (0 grep hits for `def deep_indifferent` across essentials, gear, ai, rig, camp, rbbt-util 6.0.5). Not merely misattributed — **NOT_FOUND**. The nested-IndiferentHash claim in the user docs (ledger C17) is correspondingly wrong.
7. **"Foundation upon which Scout and Scout-AI are built"** (`SE/doc/StartHere.md:5`): correct in substance (see verdict) but should be qualified — scout-ai depends on it only *transitively* (via scout-rig, whose own gemspec omits the essentials edge), and essentials itself silently *depends upward* on scout-gear types (TSV, Step) and legacy rbbt-util methods for items 1-5.
8. **Scheduler/HPC/"scout camp" style orchestration** — no essentials doc makes this claim (grep found none), but for completeness of the attribution ledger: all such functionality is in **scout-gear** (`workflow/deployment/scheduler/{slurm,pbs,lfs}.rb`, `orchestrator/`) with **scout-camp** adding cloud/offsite/terraform layers; nothing of it lives in essentials.

## UNVERIFIED items

- **rbbt-util dependency direction (gemspec level)** — `rbbt-util-6.0.5`'s installed tree has no readable gemspec at the audited path, so I could not confirm whether rbbt-util *declares* scout-essentials/scout-gear as runtime deps (the `require_instead` shim mechanism suggests intent, but the edge is UNVERIFIED).
- **`rake_dirs` external consumers** — verified essentials implements it and gear does not use it; whether any *user* workflow repos use `:rake` claims could not be checked (outside audited set).
- **`NamedArray#setup` `key:` kwarg semantics** (ledger C13) — orthogonal to attribution, still unresolved in Phase 2; not re-attempted here.
- **Camp "job arrays"** — I located SLURM/PBS/LFS in gear and the camp command dirs (`offsite/sync/terraform`); I did not exhaustively enumerate every camp subcommand or array-job helper, so any *specific* "job array" implementation claim in camp remains UNVERIFIED.
- **GitHub/upstream repositories** — Scout-Camp and Scout-Rig were NOT present as local git worktrees in this sandbox (only their installed gem copies), so file:line citations for them are from gems, which may lag their git heads. Marked as gem-snapshot evidence above.
