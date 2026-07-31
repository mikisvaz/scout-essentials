# Synthesis Report

**Status:** Non-normative investigation artifact. May be outdated.

## Purpose

Cross-check all investigation artifacts for consistency, overlaps, and gaps.
Produce a concrete file mapping from investigation content to target
documentation files.

---

## Module → Concept → Documentation mapping

| Module | Concept | User doc | Developer doc |
|--------|---------|----------|---------------|
| Annotation | Annotating objects | AnnotatingData.md | AnnotationSystem.md |
| NamedArray | Named arrays | AnnotatingData.md | AnnotationSystem.md |
| IndiferentHash | Key-indifferent hashes | AnnotatingData.md | AnnotationSystem.md |
| Open | File I/O | WorkingWithFiles.md | PathResolution.md |
| Path | Path resolution | WorkingWithFiles.md | PathResolution.md |
| TmpFile | Temp files | WorkingWithFiles.md | PathResolution.md |
| CMD | Running commands | RunningCommands.md | (covered in user doc) |
| Log | Logging | LoggingAndProgress.md | (covered in user doc) |
| ConcurrentStream | Stream lifecycle | HandlingStreams.md | StreamingModel.md |
| Persist | Caching | CachingResults.md | PersistenceAndResources.md |
| Resource | On-demand resources | ProducingResources.md | PersistenceAndResources.md |
| SOPT | CLI options | CommandLineOptions.md | (covered in user doc) |
| Misc | Utility functions | (cross-cutting) | DesignPrinciples.md |

---

## Target documentation structure

```
doc/
    StartHere.md
    Improvements.md
    user/
        AnnotatingData.md
        WorkingWithFiles.md
        RunningCommands.md
        LoggingAndProgress.md
        HandlingStreams.md
        CachingResults.md
        ProducingResources.md
        CommandLineOptions.md
        Cookbook.md
    developer/
        Architecture.md
        DesignPrinciples.md
        AnnotationSystem.md
        PathResolution.md
        PersistenceAndResources.md
        StreamingModel.md
```

---

## Writing order (by priority)

1. **StartHere.md** — entry point
2. **developer/Architecture.md** — mental map
3. **developer/DesignPrinciples.md** — coding style
4. **user/AnnotatingData.md** — Annotation foundation
5. **user/WorkingWithFiles.md** — most used
6. **user/RunningCommands.md** — CMD
7. **user/LoggingAndProgress.md** — Log
8. **user/HandlingStreams.md** — ConcurrentStream
9. **user/CachingResults.md** — Persist
10. **user/ProducingResources.md** — Resource
11. **user/CommandLineOptions.md** — SOPT
12. **user/Cookbook.md** — recipes
13. **developer/AnnotationSystem.md** — internals
14. **developer/PathResolution.md** — path maps
15. **developer/PersistenceAndResources.md** — caching internals
16. **developer/StreamingModel.md** — stream internals
17. **Improvements.md** — recommendations
18. **research/** — curate SHARED artifacts
19. **Validation** — check links, coverage
