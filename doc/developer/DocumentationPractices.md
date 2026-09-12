# Documentation Practices

This page defines the normative practices for running documentation
campaigns in the Scout-AI ecosystem (`scout-essentials`, `scout-gear`,
`scout-ai`) with CortexCoder, Cortex, and ChatAnalyst. It is written for
campaign Managers planning a documentation review, CortexCoder agents owning
a subsystem study, Critic/verifier agents gating results, and any agent
resuming an interrupted campaign. Every practice below carries an evidence
label; thin or single-reviewer evidence is marked as such and never
presented as verified. The content is promoted from
`research/doc-practices-guide.md`, which was retired after Critic-verified
promotion; its unique associated-elements inventory is preserved in the
Cortex closure artifact `doc-guide/promotion-record.md`.

## Notation and evidence grades

Citations use the compact session keys below. Each advice item carries a
grade marker showing how strong its evidence is; **no item's grade may be
read as stronger than marked**.

- `[V]` — the cited message was re-read directly (via
  `message_index`/`message_content` or the persisted chat) by the round-3
  extraction that produced this page.
- `[R1]` — inherited from a round-1 review artifact; not re-verified.
- `[R2]` — inherited from the round-2 area map; not re-verified.
- `[REPT]` — ChatAnalyst report accounting only. Reported magnitudes,
  never practice. In particular, token totals are accounting figures; do
  not cite them as behavioral evidence.

Session keys (root chats): `ES-ROOT#N`, `GE-ROOT#N`, `SA-ROOT#N` are
message *N* of the scout-essentials, scout-gear, and scout-ai root
sessions. Society refs `<root>.files/agent.society/<Agent>/<conversation>/
agent.chat#N` are abbreviated: essentials `AH` (essentials-annotation-hash),
`OCS` (essentials-open-cmd-stream), `PRL`
(essentials-persist-resource-log), `COF` (cortexcoder_open_finish), `OCC`
(open_cmd_closeout); gear `SCC` (sgdoc-conc), `SKB` (sgdoc-kb), `DC-cli`
(docconsol-cli), `GE` (gear_entity), `STUB(<conv>)`; scout-ai `SAD`
(scoutai-subsys-agent-delegation), `STATE` (docrev-state), `B0B4`/`B5B7`
(docrev-exec-*), `CRITIC` (Critic/docrev-verify), `SUBSYS-*`, `PROMO-*`.

## Areas

### A1 — Campaign architecture: phases, root-vs-society, actor roles

Split the campaign into phases with distinct modes and name the boundary
explicitly. Study phases operate under an explicit "do not modify the
repository" scope and flip to writes only after a state probe confirms
authority (SA-ROOT#11 [V]); a phase-1 scope that leaves README untouched is
a *task scope*, not an omission, and is lifted only by user authorization
(GE-ROOT#146→#147 [V]).

- Do: make one delegation unit = one subsystem in one named conversation;
  dispatch in waves and verify artifacts with `cortex_list` before
  consolidating (SA-ROOT#11 [V]; R1-s D2 [R1]).
- Do: keep the roles distinct — Manager plans, CortexCoder owns subsystems,
  Critic gates, Searcher/Worker support (SA-ROOT#68 [V]).
- Don't: keep the root hands-on once work parallelizes. A root doing the
  first investigation itself is fine for a single artifact, but parallel
  branches dispatched outside the parent transcript leave provenance gaps
  (see A8) — this is what happened in the essentials session
  (ES-ROOT#118/#148 [V]).

Context: the practice evolved across the three sessions — essentials
pioneered a root-hands-on root, gear systematized Manager-run batch
campaigns plus promotion, scout-ai governed phases behind independent
verification.

### A2 — Docs-first, gap-derived, labeled evidence

Review maintained documentation and prior Cortex artifacts *first*, derive
an explicit gap list, and probe only genuine gaps (STUB(gear_cli)#11 [V];
GE-ROOT#51 [R1]; SA-ROOT#11 [V]). Never probe what the documentation
already answers.

- Do: label every statement `[doc]`/`[code]`/`[verified]` (plus
  `[artifact]` when prior Cortex work exists) and list doc–code mismatches
  separately with `file:line`. The labels are what make later promotion
  auditable (SA-ROOT#11 [V]).
- Do: make claims executable: each claim cites an executed probe and its
  property-job receipt, never a transcribed number — "Claims must come from
  executed probes, not transcription" was hard-coded in every essentials
  packet (AH#11 [V]); the finished form is a bold claim plus an Evidence
  paragraph naming result keys and the receipt JSON (ES-ROOT#118 [V]).
- Do: treat a probe failure as a bug in the probe — fix and re-run, never
  transcribe. The annotation branch looped a failing probe through twelve
  versions until it ran (AH#299/#305→#481 [V]); a delegation study drove
  its probe past v40 the same way (SAD#768/#769 [V]).
- Don't: write unlabeled claims into durable artifacts (SA-ROOT#11 [V]).

### A3 — Delegation packets, parallel ownership, reconciliation

- Do: send five-section self-contained packets — Introduction / Current
  state / Design / Task / Output required — carrying the checkout path,
  HEAD, existing artifacts *with versions*, property digest, naming
  prefixes, and a structured reply contract (AH#11 [V]; SA-ROOT#11 [V];
  GE-ROOT#55 [V], #219 [V]). Self-contained packets are what make stub
  re-dispatch cheap (A5).
- Do: name one canonical exemplar as the template and partition claim
  territory. Every essentials packet named `path_map.md` the
  "citation-style exemplar" and forbade duplicating it (AH#11 [V]);
  scout-ai packets listed persisted siblings as "read if useful for
  cross-refs, do not duplicate" plus explicit ownership splits
  (R1-s D3 [SA-ROOT#18/#24/#27/#33/#35] [R1]).
- Do: run parallel owners in batches of three with a cross-edit
  prohibition, and appoint a dedicated reconciler for shared files. The
  reconciler reviews every modified path, fixes shared files, stages and
  commits without pushing (GE-ROOT#51/53/55 [V]; GE-ROOT#219 [V]).
- Do: serialize long delegations that share an uncommitted tree (gear
  phase-2 ran one at a time against survey-listed conflict risks — R1-g F7
  [R1]); split big close-outs into ordered packets (scout-ai B0–B4 then
  B5–B7, SA-ROOT#61 [V]).
- Do: for a dead branch, send a closeout-only packet that says "Do NOT redo
  exploration", enumerates the existing probes *and their receipts*, and
  includes a scratch-cleanup step (ES-ROOT#301 [V]).
- Don't: re-type an "established pattern (follow it exactly)" block into
  every packet — that is a brief's job. The essentials campaign paid that
  cost three times (AH#11, OCS#11, PRL#11 [V]; see A7).

### A4 — Persistence ladder & promotion governance

The persistence ladder as practiced: `tmp/` scratch → `probe/` Cortex
artifacts → claims artifacts → `research/` → `doc/`, with scratch deleted
after promotion (ES-ROOT#82→#88, #141–#143 [R1]; explicit
probe→`research/`→`doc/` mapping GE-ROOT#148 [R1]; scout-ai B-series
SA-ROOT#61 [V]).

- Do: promote into `doc/` only under explicit user authorization
  (GE-ROOT#147 [V]).
- Do: survey before batching. One bounded read-only recon (git state,
  per-subsystem status, conflict risks) can re-cut the whole plan — the
  gear survey found all eight subsystems already had uncommitted doc edits
  and shrank the batches accordingly (GE-ROOT#198/#199 [R1]; final report
  GE-ROOT#225 [V]); in scout-ai the read-only state probe overturned the
  inventory with 20/21 doc files already edited (SA-ROOT#61 [V]).
- Do: distill before delete. Retirement is a transfer: bounded diff of the
  doomed file against `doc/` and the probe-verified counterpart, promote
  the unique verified facts, drop the unverifiable, then delete
  (SA-ROOT#61 B3/B4/B5 [V]; R1-s D7 [R1]).
- Do: use decision-bound retention instead of blanket deletion: when a
  file's fate belongs to an open decision, keep it, add a dated retention
  note, and flag it for the maintainer in the final report
  (SA-ROOT#83 [V]).
- Do: pre-plan commit granularity and per-batch invariants; one retirement
  per commit; deletions never mixed into the commit under test
  (SA-ROOT#61 [V]). Name the record of truth per change class — the
  Improvements ledger records promotions, commit messages record
  retirements — and state the split explicitly (SA-ROOT#69 [V];
  SA-ROOT#83 [V]).
- Do: route live code defects to the issue ledger with receipts, never
  document broken behavior as normal (SCC#84 [V]); the gear campaign filed
  48 receipt-cited items with 6 deliberate non-filings, each with a
  recorded reason (GE-ROOT#225 [V]).
- Do: delete scratch after promotion, verifying each file is superseded
  and leaving unrelated pre-existing `tmp/` material alone (81 files
  deleted, older material kept; ES-ROOT#310 [V]).

### A5 — Interruption, hang, and recovery

Distinguish two failure families. A native-blocking hang (`sem_wait`,
fork+join, cross-pipe misuse) returns `exit_status:-1` with null stdout
only after the ~3600 s harness kill (SCC#83 [V]); a Cortex-side property
exception returns fast and is not a hang (OCS#507 [V]).

- Do: diagnose a suspect probe standalone under a short shell timeout
  before re-executing it through the entity property (COF#11 step 2 [R1]).
- Do: salvage dead branches with a bounded closeout packet, never
  re-exploration (ES-ROOT#301 [V]; outcome ES-ROOT#310 [V]).
- Do: on interruption, trust durable artifacts over memory — "a missing
  transcript cannot establish execution; recover confidence from durable
  outputs" (SA-ROOT#47 [V]) — and resume a mutation campaign only after a
  fresh read-only state probe that closes every planning gap and persists
  a state artifact (STATE#13 [V]; outcome SA-ROOT#83 [V]).
- Expect: zero-tool stub residue. A dispatch lands (full packet, zero
  inferences, zero tool calls) and execution never starts; the gear
  campaign accumulated five such conversations before the subsystem landed
  elsewhere (STUB(gear_cli)#11 [V] + chat_overview [V]; R1-g F2 [R1]).
  Recovery is re-dispatch — cheap precisely because packets are
  self-contained.

### A6 — Artifact iteration & honest-limits hygiene

- Do: write once, refine with small targeted edits, and treat version
  history as the audit trail (`path_map.md` v4 — ES-ROOT#118 [V] plus
  three edits [R1]; annotation claims v6 with one probe at v12 — AH#481
  [V]; scout-ai state artifact closed v3 [R1]).
- Do: re-read the current version before `cortex_edit` — editing from
  memory fails with "text not found" (ES-ROOT#127/#128 [V]; recovered by
  re-read then re-edit [R1]).
- Do: encode environment and divergences inside the deliverable: record
  which version observations ran against (installed 1.9.0 gem vs 1.9.1
  checkout in the essentials closeout) and keep both values as citation
  when a sandbox diverges from the host (ES-ROOT#310 [V]).
- Do: ship a "not probed / why" section in every branch report (AH#481 §5
  [V]; PRL#1661 §5 [V]) and declare missing result keys instead of
  inventing values — demand this verbatim in closeout packets
  (ES-ROOT#301 [V]).
- Do: strike through stale lines rather than deleting them
  (SA-ROOT#81 [R1]); leave `# ScoutCoder:` gap notes in code where
  undocumented behavior was discovered, as `Observation/probe` does for the
  undocumented `.meta` sidecar layout (ES-ROOT#100 [V]).

### A7 — Cortex workspace usage patterns

- Do: recall first at every phase boundary — `cortex_list`/`cortex_search`
  before any dispatch (GE-ROOT#3–#49 [R1]; R1-s [R1]; SA-ROOT#47 [V]).
- Do: recall before recompute: when a prior campaign already covered 7/8
  subsystems, re-scope the "fresh" instruction to gap-filling and do not
  attribute orphaned prior work to the current campaign (GE-ROOT#42 [V]).
- Do: use named conversations as durable delegation units and *reuse* an
  executor conversation for follow-ups that depend on its accumulated
  conventions — a one-line repair went back to `docrev-exec-b5b7` "because
  it knows the pattern" (R1-s D9 [SA-ROOT#70/#71/#80] [R1]).
- Do: define one shared entity property as the probe interface and treat
  the `properties/` registry as the execution ledger: define once with a
  smoke test (ES-ROOT#100 [V]), share across branches, mine for diagnosis
  ("28/28 entries", COF#16/#17 [R1]).
- Don't: confuse the `ask` tool's `conversation` parameter with the Cortex
  conversations namespace — verify deliverables via `cortex_list prefix=`
  (R1-g F3 [R1]). Don't invoke `Agent/<brief>` before the brief exists
  ("No briefs exist yet"; fall back to the default agent)
  (GE#217/#219 [V]).
- Gap (thin): the essentials campaign created no conversations, briefs, or
  lists and re-typed its "established pattern" into every packet (AH#11
  [V]) where a brief would have been cheaper. The brief counterfactual
  lives in `guides/briefer-usage.md` and
  `harness/briefed-agent-efficiency.md` — cross-linked artifacts, not chat
  evidence of these campaigns.

### A8 — Provenance, receipts, attribution

- Do: route delegation through recorded `ask` calls so `agent_meta`
  receipts survive. The gear root's 12 asks embed 3,111 receipt records
  deduplicated against saved society logs with 0 conflicts (R1-g [R1]);
  scout-ai's asks each returned receipts and the Critic job produced the
  session's single `agent_job` edge (R1-s [R1]).
- Don't: dispatch work outside the persisted transcript. The essentials
  root launched its three parallel branches and the first closeout with no
  manager turn around them — only one `ask` is recorded (ES-ROOT#301 [V])
  — leaving 54.97 M of the 59.09 M reported tokens unattributed to any
  recorded delegation (chat_report [REPT V]; R1-e D12 [R1]).
- Do: cite `property_job` receipts (JSON name + definition version +
  digest) per claim; this is the citation currency of every claims
  artifact (ES-ROOT#118 [V]; "Never transcribe numbers without a probe
  receipt", GE-ROOT#51 [R1]).
- Do: audit citation integrity against the registry before closing —
  "verify every number you write against the actual artifacts/registry";
  the gear synthesis chased a reported sixth mismatch into a transcription
  error and closed at 238 claims / 101 unique receipts / 0 broken
  (GE-ROOT#146 [V]; R1-g D2 [R1]).
- Expect: interrupted runs drop root segments while society children
  persist — a 14-message zero-call stub holding the full packet
  (PROMO-DOC#13 [V], chat_overview [V]) with no root ask for it
  (R1-s F4 [R1]). Budget a state-reconstruction pass; durable artifacts
  make it cheap (A5).

### A9 — Sandbox, path, and exec friction

- Do: state the concrete `/bulk/...` checkout path in packets. `~/git/<repo>`
  does not exist inside bwrap while doc tooling advertises it; the
  divergence is resolved with hypothesis-driven probes plus the designated
  `sandbox_paths` diagnostic (STATE#19/#20/#30/#31 [V]); subsequent
  packets carried the `/bulk` path explicitly (R1-s F1 [R1]).
- Do: reformulate bash commands against sandbox-visible paths when bwrap
  rejects one (`exit_status:-1`, "Process failed - bwrap …" on an
  unreadable target; DC-cli#77 [V], #1040 [V]). Redirect-heavy one-liners
  fail more often under bwrap (R1-s F2 [R1]).
- Do: guard every risky subprocess with a shell `timeout`, and know the
  limit: a SIGTERM-based timeout does not interrupt native-blocking
  primitives (`sem_wait` on a missing name), so a "fixed" script can still
  burn the full 3600 s (SCC#82/#83 [V]; use `timeout -s KILL` per R2 §2a
  [R2]). The full friction table is under *Friction table* below.

### A10 — Cost, cache, and context economics

All totals in this section are `[REPT]` accounting — reported magnitudes,
never practice (see *Caveats and evidence limits*). Only the essentials
total was re-anchored: deduplicated 59,088,981 tt (pt 58,627,925; cct
56,841,472 ≈ 96.9 % of pt) over 1,346 calls / 990 events (chat_report +
chat_tool_calls [REPT V]). scout-ai ≈ 460.6 M tt over 6,989 calls
[REPT R1]; gear ≈ 775 M tt over 12,254 calls [REPT R1] — both inherited,
not re-anchored.

- Do: prefer cheap local probes; `bash` dominates every session's tool mix
  (essentials 877/1,346 [REPT V]; gear 9,502/12,254 [R1]) and long
  cache-friendly conversations made the economics work.
- Do: read artifacts page-wise even mid-task — every scout-ai consumption
  used `cortex_read` with `start_line`/`lines` (SUBSYS-INDEX#16/#34 [V];
  R1-s D12 [R1]).
- Don't: grow single-branch chats without bound — one branch reached 1,662
  messages / 550 calls [R1], the shape that invites compaction (inferred
  risk; no compaction events were observed — R1-e D11 [R1]).

### A11 — Campaign outputs & verification gates

- Do: independently re-verify load-bearing claims with fresh minimal code
  in an isolated process before finalizing (ES-ROOT#136/#137 [V]; reported
  at ES-ROOT#148 [V]).
- Do: gate the final report behind an independent verifier with concrete
  numbered checks, its own methods, a PASS/NEEDS_WORK/BLOCKED verdict, and
  a required "smallest next action". The scout-ai Critic found one real
  defect (13 stale gemspec entries the promotion commits had missed); the
  Manager chose the smallest repair, sent it to the same executor
  conversation, and re-validated (SA-ROOT#68/#69/#72 [V]). Don't expand
  repair scope beyond the verdict.
- Do: run the test suite and record counts per subsystem before commit —
  including an explicit "no dedicated suite exists" — then review every
  modified path, reconcile shared files, stage intentionally, commit
  without pushing (GE-ROOT#219 [V]; GE-ROOT#225 [V]; R1-g D7 [R1]).
- Do: audit citation integrity as a closing gate (GE-ROOT#146 [V]) and let
  the verifier expose implicit batch invariants — the gemspec defect
  existed because "deletion must sweep file lists" had never been written
  down (SA-ROOT#69 [V]); encode it as a standard retirement step
  (R1-s F5 [R1]).

Context: the verification practice progressed from essentials' spot
re-verification, to gear's reconciler audit plus test gate, to scout-ai's
independent Critic with a smallest-repair loop.

## Failure-mode playbook

**Native-blocking hang: shell timeout is insufficient.** A planning
discipline that mandates `timeout 15` wrappers on forking probes
(SCC#60 [V]) is necessary but not sufficient. In the gear chain, a guard
with `timeout 120` correctly tripped (`exit=124`) and let the agent
diagnose its own cross-pipe bug (SCC#76/#77 [V], #78 [V]); after the fix,
`timeout 180` still hung for the hour — `exit_status:-1`, null stdout,
bwrap "exceeded 3600 seconds", timestamps 19:43:02.736→20:43:02.778
(SCC#82/#83 [V]) — because the blocker was
`ScoutSemaphore.wait_semaphore` (native `sem_wait`), which SIGTERM cannot
interrupt. Recipes: short `timeout` per invocation; `timeout -s KILL` for
native blockers [R2]; read `exit_status:-1` + null stdout + a ~3600 s
timestamp gap as a harness kill, not a quick failure.

**Hang recovery: staged, time-boxed, split probes.** After a kill returns,
wrap each individual script in its own timeout and split verification into
small scripts so one hang does not block everything: a deterministic
script with no waits plus a time-boxed script with waits — "even if B
hangs, A's evidence is in hand" (SCC#84 [V]). Then `pkill` cleanup and a
`/dev/shm` semaphore check — both themselves messy under bwrap (exit 143;
SCC#85/#86 [V]). Inbox advice posted during a blocked call is delivered
only when the call returns; it cannot interrupt it
(harness-findings/bash-tool-blocking-hangs.md [R1], cited for taxonomy
only — its message indices are unreliable; see caveats).

**Zero-tool stub residue.** A dispatch lands (full packet, zero
inferences, zero calls) and execution never starts; the gear campaign
accumulated five such conversations (STUB(gear_cli)#11 [V]; R1-g F2
[R1]). Recovery is re-dispatch. Whether stub prompts ever reached a model
anywhere is unproven (see caveats).

**Interruption resume: state artifacts plus read-only state probe.** On
"You were interrupted, please finish up" with no memory of prior work:
recall the workspace (SA-ROOT#47 [V]), run a dedicated read-only probe
closing every planning gap (git state, checkout identity, byte counts,
fix-sweep presence), persist a state artifact, and only then resume
mutation (STATE#13 [V]; outcome SA-ROOT#83 [V]). In scout-ai this probe
overturned the inventory — 20/21 doc files were already edited
(SA-ROOT#61 [V]).

**Dead-branch closeout.** Diagnose from the registry (executions with
forced updates, no claims artifact), then send a closeout-only packet: "Do
NOT redo exploration", enumerate probes and receipts, require scratch
cleanup with per-file supersession checks (ES-ROOT#301 [V];
ES-ROOT#310 [V]). Standalone-under-timeout diagnosis: COF#11 step 2 [R1].

**Cortex-side property exception is not a hang.** A fast-failing
`cortex_entity_property` ("Property execution raised: no implicit
conversion of Step into Integer", ~0.2 s, from the entity-task rescue)
blocked a branch at its tail (OCS#500→#507→#521 [V]). What happened after
the last fast edit (OCS#521, 18:14:05.202Z [V]) is unobservable in the
transcript (see caveats).

**Dispatch-provenance gap.** Work dispatched outside recorded calls leaves
society children hanging off log edges with no parent record and most cost
unattributable (essentials: 0 `agent_job` edges, 5 log edges, one recorded
`ask`; ES-ROOT#301 [V]; chat_report [REPT V]). Recovery is prevention:
route delegation through `ask`/`cortex_continue`.

## Friction table

First recovery move per observed harness/tool friction. Symptom → first
recovery move, with citation and grade:

| Friction | Symptom | First recovery move |
| --- | --- | --- |
| `search` path rejected | allowlist exception naming the path | `pwd`, then bash (ES-ROOT#16–#20 [R1]) |
| `cortex_edit` text-not-found | exception names the missing text | `cortex_read` current version, re-edit (ES-ROOT#127/#128 [V]) |
| `list_directory` recursive+stats | 142,439 chars truncated at the 100k cap | bash `ls`-based listing (COF#12/#13 [R1]) |
| `cortex_read type=properties` | ".json" suffix rejected | `cortex_list type=properties` prefix listing (OCC#68/#69, COF#16/#17 [R1]) |
| bwrap path divergence | `~/git/...` absent, `/home/.../git` ENOENT | hypothesis probes + `sandbox_paths`; carry the `/bulk` path in packets (STATE#19/#20/#30/#31 [V]) |
| bash under bwrap | `exit_status:-1`, "Process failed - bwrap…" | reformulate against sandbox-visible paths (DC-cli#77, #1040 [V]) |
| native-blocking hang | `-1` + null stdout after ~3600 s | `timeout -s KILL`; staged split probes (SCC#82/#83, #84 [V]) |
| `patch` auto-strip under bwrap | strips −p0…−p4 fail, hunk context lost | re-anchor the edit manually (DC-cli#1039/#1040 [R1]; tool identity not re-verified — see caveats) |
| test-unit multi-file | only the first file executes | one file per runner invocation (STATE#81–#85 [R1]) |
| `pkill` under bwrap | exit 143, argv elided | verify stray processes/semaphores another way (SCC#85/#86 [V]) |
| `Agent/<brief>` without a brief | "No briefs exist yet" | continue with the default agent (GE#217/#219 [V]) |
| ask-vs-Cortex namespace | "No conversation named …" | verify via `cortex_list prefix=` (R1-g F3 [R1]) |

## Caveats and evidence limits

These limits are Critic-mandated and binding on this page. They are limits
of the evidence, never practices to follow.

1. **Message-index mismatch in the bash-hang finding.**
   `harness-findings/bash-tool-blocking-hangs.md` is cited on this page
   **only for its hang taxonomy and its inbox-advice limit**; its message
   indices are unreliable and must not be trusted: its `#52→#53` is in
   fact a fast monitor.rb read pair and `#822→#823` a ConcurrencyModel
   grep at ~22:47Z; the real hang chain is #76/#77 and #82/#83; the
   claimed 22:54:57Z fifth hang was not located.
2. **Unresolvable artifact set.** The `scout-gear/*` campaign artifact set
   (overview, 8 claims artifacts, consolidation series) is cited
   throughout `GE-ROOT` and R1 but was **not resolvable via `cortex_list`
   in this workspace's readable maps at extraction time** — verify with
   `cortex_list prefix=` before reuse.
3. **The patch-tool friction row is R1-confirmed only.** The re-read of
   DC-cli#1040 confirmed a bwrap process failure but not that the failing
   tool was `patch`; the row stays `[R1]` and is not upgraded.
4. Token totals for scout-gear (~775 M tt) and scout-ai (~460.6 M tt) are
   R1/REPT figures; only the essentials total was re-anchored (R2 §7.7).
   Reported magnitudes only — never practice.
5. Open threads that stand from the round-2 map: the unobserved
   post-#521 fate of the essentials Open/CMD/Stream branch; the sgdoc-kb
   interior (structural only); whether stub prompts ever reached a model;
   ES-ROOT#302 (552 KB) unread; PRL/AH/COF/OCC interiors R1-sampled only;
   `Searcher/default` and `CortexCoder/default` structurally accounted
   only.
6. The "no implicit conversion of Step into Integer" Cortex entity-task
   error deserves its own harness finding (R2 §7.3) — it blocked a branch
   and is distinct from the fork-hang family.
7. Essentials compaction risk is inferred, not observed (R1-e D11 [R1]).

## Provenance

This page is promoted from `research/doc-practices-guide.md` (491 lines),
which was retired in a follow-up commit after Critic-verified promotion
(931f728, PASS 97/100); retirement followed the distill-before-delete
rule in A4.

The guide was produced by a staged process: (1) a chat manifest fixed
session identity, path caveats, and the guide host repo; (2) three
independent ChatAnalyst reviewers — one per session, fresh conversations,
none seeing another's output — produced the round-1 reviews; (3) a distinct
round-2 mapper reconciled them into the eleven-area taxonomy (A1–A11) with
gap-closing direct reads; (4) a Critic gate passed that map (PASS, 88/100);
(5) a round-3 extraction (briefed CortexCoder, conversation `doc-guide`)
read the artifacts page-wise, spot-verified citations, and wrote the single
guide file. The guide itself was then Critic-reviewed (93/100) before this
promotion.

Working-review substrate (Cortex logical paths; working artifacts retained
for provenance, not re-inlined here): `doc-guide/chat-manifest.md`,
`doc-guide/R1-dimensions-essentials.md`,
`doc-guide/R1-dimensions-gear.md`,
`doc-guide/R1-dimensions-scout-ai.md`, `doc-guide/R2-area-map.md`,
`search/doc-guide-source-map.md`.

Underlying sessions (exact spellings; the `~/git/...` form does not
resolve):

- `~/chats/scout-essentials/cortex_coder` — 311 root msgs / 6 chats /
  1,346 tool calls (09-07→09-08); pioneer root-hands-on campaign.
- `~/chats/scout-gear/cortex_coder` — 226 root msgs / 41 chats / 12,254
  tool calls (09-08→09-10); Manager-orchestrated gap-fill then
  user-authorized consolidation.
- `~/chats/scout-ai/cortex_coder` — 84 root msgs / 22 chats / 6,989 tool
  calls (09-10→09-12); eleven labeled subsystem studies, interrupted
  promotion, governed close-out (B0–B7, 22 commits) behind an independent
  Critic gate.

Cross-linked campaign artifacts named by the guide (probe sets, claims
exemplars, harness findings, the scout-ai subsystem index and
promotion-state pair) remain in the Cortex workspace; the guide's
§17 associated-elements inventory is preserved verbatim in the Cortex
closure artifact `doc-guide/promotion-record.md` (campaign closure
record), which is the authoritative inventory.
