# Documentation review — how `doc/` and `research/` are organized

**Status:** Non-normative process artifact.

This note records how the scout-essentials documentation set is
structured after the 2026-09 review, and the standard each layer holds
itself to. It is for future maintainers deciding where new material
belongs.

## The two-layer contract

- **`doc/`** — normative, well-proven, core concepts only. A claim
  belongs here once it is stable, verified against the current `lib/`,
  and something a user or developer needs to operate the library. Pages
  cite `file:line` anchors rather than probes or transcripts: the source
  itself is the citation.
- **`research/`** — non-normative investigations, process records, and
  claims that are interesting but either not core, not fully proven, or
  machine/lesson specific. Every file declares
  `**Status:** Non-normative investigation artifact. May be outdated.`

## Layout

```
doc/
  StartHere.md          — the entry point + reading paths
  Improvements.md       — running log of known defects / improvement ideas
  user/                 — how to *use* each subsystem, task-oriented
    WorkingWithFiles, RemoteData, RunningCommands, HandlingStreams,
    CachingResults, ProducingResources, AnnotatingData,
    LoggingAndProgress, CommandLineOptions, Cookbook
    (Path itself is covered by developer/PathResolution.md and used
    throughout the user pages)
  developer/            — how each subsystem *works*, mechanism-oriented
    Architecture, DesignPrinciples, AnnotationSystem, PathResolution,
    PersistenceAndResources, StreamingModel, Configuration,
    ErrorHandling, LockingAndConcurrency, CoreUtilities
research/
  *-analysis.md         — per-chunk behavioural analyses (annotations,
                          commands/streaming, io/paths, design philosophy)
  implementation-inventory-*.md — file:line inventories per chunk
  doc-audit-findings.md — forensic audit report (hallucinations found,
                          corrected claims, decisions taken)
  ecosystem-attribution.md — which repo owns which constant
  behavior-probes.md    — historical probe transcripts (the probes
                          themselves were promoted to tests / deleted)
  lock-namespace-blindness.md — promoted-from-cortex behavioural hazard
```

## Where new material goes

| kind of finding | destination |
|---|---|
| core, verified behaviour a user needs | `doc/user/<Topic>.md` |
| core, verified mechanism a maintainer needs | `doc/developer/<Topic>.md` |
| known defect / improvement candidate | `doc/Improvements.md` (numbered `I#`) |
| hazard, heuristic, environment-specific behaviour | `research/<topic>.md` |
| one-off verification transcript | nowhere — write a regression test instead |
| cross-repo attribution of a constant | `research/ecosystem-attribution.md` |

## The promotion path (2026-09 episode)

The 2026-09 documentation review followed this ladder:

```
probes (cortex probe/*.rb artifacts)
  → claims (cortex *.md artifacts)
  → doc/ pages (claims rewritten pedagogically, probe citations removed)
  → tests (selected probes promoted to test/scout/**/test_*.rb)
  → cortex probes + execution records deleted
```

Rules applied:

1. **No probe references in `doc/`.** Documentation cites `file:line`
   anchors and regression tests; transcripts are process, not product.
2. **Probes whose claims were promoted became tests, not corpses.**
   Eight regression tests were extracted (NamedArray resolution,
   CaseInsensitiveHash staleness, `string2hash` false-asymmetry,
   `Misc.timespan` tokens, Open compression detection, broken
   `:gzip => true`, annotation dup/clone, TmpFile cleanup).
3. **Probes with no durable claim were deleted**, together with their
   `properties/Observation/probe` execution records. The four promoted
   claims artifacts stay in cortex with a "promoted out of cortex"
   banner naming their new home.
4. **Cortex claims that document a hazard stay in cortex** only while
   unproven; `persist_lock_theft_across_agents` was promoted to
   `research/lock-namespace-blindness.md` with the operational advice
   folded into `doc/developer/LockingAndConcurrency.md`.
