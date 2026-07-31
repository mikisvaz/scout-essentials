# Improvements

Actionable recommendations for improving scout-essentials code, discovered
during the documentation effort. Each item includes a description, impact,
and suggested action.

## Status legend

- 🔴 **Bug** — Incorrect behavior that should be fixed.
- 🟡 **Improvement** — Works, but could be better.
- 🟢 **Done** — Already resolved.

---

## High priority

### I1. 🟡 ConcurrentStream join can deadlock with multi-stage pipelines

When joining a multi-stage pipeline (producer → filter → consumer), if the
producer is joined before the consumer has drained the pipe buffer, the
join can deadlock because the pipe buffer fills and the producer blocks.

**Impact:** Pipeline hangs in production.

**Suggested action:** Document the correct join order (consumer first,
producer last) and consider adding automatic consumer-joins-producer
chaining via `autojoin`.

---

### I2. 🟡 Persist persistence_path can collide for short keys

For short, filesystem-safe keys, Persist uses the key directly as the
filename. If two modules use the same short key, the cache files collide.

**Impact:** Subtle data corruption — one computation overwrites another's
cache.

**Suggested action:** Namespace cache paths by the calling module or
library. Consider prefixing with a digest of the caller's file path.

---

### I3. 🟡 TmpFile cleanup not guaranteed on signal (SIGTERM/SIGKILL)

TmpFile's `with_file` and `with_dir` use `ensure` blocks for cleanup.
However, SIGTERM and SIGKILL bypass `ensure`, leaving temporary files on
disk.

**Impact:** Temporary file accumulation over time in long-running services.

**Suggested action:** Register a PID-based temp directory and add a
periodic cleanup task. Consider using `at_exit` for graceful shutdown.

---

### I4. 🟡 Open remote read via SSH not documented or tested

Open supports reading from SSH paths (`user@host:path`), but this path is
not well documented, and test coverage is limited.

**Impact:** Users may not know SSH support exists; regressions may go
undetected.

**Suggested action:** Document SSH support in [Working with Files](user/WorkingWithFiles.md).
Add tests. Add retry logic for network failures.

---

## Medium priority

### I5. 🟡 No central registry for path maps

Path maps are configured globally via `Path.path_maps` and
`Path.map_order`. There is no central registry where applications can
register their maps in a namespace-safe way.

**Impact:** Map name collisions between applications.

**Suggested action:** Introduce namespaced map registration: e.g.,
`Path.add_path("myapp:data", "/opt/myapp/{PATH}")`.

---

### I6. 🟡 IndiferentHash deep_indifferent not recursive by default

`IndiferentHash.setup` makes the top-level hash key-indifferent, but nested
hashes are not automatically converted. `deep_indifferent` must be called
explicitly.

**Impact:** Surprising behavior when accessing nested keys with mixed
string/symbol access.

**Suggested action:** Document this clearly. Consider making
`deep_indifferent` the default behavior or providing a clearer alternative.

---

### I7. 🟡 Path#find returns self even when file doesn't exist (for located paths)

When a path is "located" (starts with `/`, `~`, or `./`), `find` returns
`self` even if the file doesn't exist. This differs from non-located paths
where `find` may return nil when no map resolves.

**Impact:** Callers may assume `find` returns nil for nonexistent files.

**Suggested action:** Document this behavior clearly. Consider adding a
strict mode where `find` returns nil for nonexistent files regardless of
location status.

---

### I8. 🟡 Resource production failures leave no trace

When a Resource claim's production fails (e.g., download fails), the
production is abandoned silently. No log message is emitted beyond the
exception itself.

**Impact:** Hard to debug resource production issues in production.

**Suggested action:** Add `Log.warn` or `Log.error` calls in Resource
production error paths.

---

### I9. 🟡 CMD tool registry not namespaced

CMD tool registration (`CMD.add_tool`) uses a global registry. Multiple
applications using scout-essentials share the same tool registry.

**Impact:** Tool name collisions.

**Suggested action:** Namespace tool registration by application or provide
a scoped registry.

---

### I10. 🟡 No user-facing guide on custom Annotation modules

While the annotation system is powerful, there was no user-facing guide on
how to define and use custom annotation modules for application-specific
metadata.

**Impact:** Users may subclass instead of annotate, missing the idiom.

**Suggested action:** The new [Annotating Data](user/AnnotatingData.md)
guide covers this. It should be promoted more prominently.

---

## Low priority

### I11. 🟢 Done — Documentation reorganized into three layers

The documentation has been reorganized from a flat class-by-class structure
into a three-layer structure (user/developer/research).

---

### I12. 🟡 Misc module is a catch-all

The `Misc` module (`lib/scout/misc/`) contains many unrelated utilities:
format, digest, math, system, hooks, monitor. This is a code smell.

**Impact:** Hard to find utilities; import surface too broad.

**Suggested action:** Consider splitting into separately named modules or
documenting the sub-namespace usage more clearly.

---

### I13. 🟡 No CI configuration visible

No CI configuration (`.travis.yml`, `.github/workflows/`, etc.) is visible
in the repository.

**Impact:** Tests may not run automatically on commit.

**Suggested action:** Add a CI configuration to run tests on commit.

---

### I14. 🟡 Benchmarking suite absent

There is no benchmarking suite to track performance across releases.

**Impact:** Performance regressions may go unnoticed.

**Suggested action:** Add a simple benchmark suite using `benchmark/ips`
for key operations (Open.read, Persist.persist, Path.find).

---

### I15. 🟡 Annotation `setup` with frozen objects creates a duplicate

When `setup` is called on a frozen object, it duplicates the object before
extending it. The original frozen object is not modified.

**Impact:** This is correct behavior but can surprise callers who expect
the same object to be returned.

**Suggested action:** Document this clearly in the Annotation documentation
and user guides.

---

### I16. 🟡 Persist.persist can raise if cache_dir not writable

If `Persist.cache_dir` is not writable, `persist` will fail with a
permissions error.

**Impact:** Can break production when cache_dir is on a read-only
filesystem.

**Suggested action:** Document this requirement and consider falling back
to a temporary cache dir or raising a clearer error message.

---

## Summary

| Category | Count |
|----------|-------|
| Bugs (🔴) | 0 |
| Improvements (🟡) | 15 |
| Done (🟢) | 1 |
