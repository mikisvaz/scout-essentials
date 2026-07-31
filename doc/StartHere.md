# Scout-Essentials Documentation

Scout-essentials is a foundational Ruby library providing utilities for
file I/O, path resolution, command execution, logging, caching,
annotations, and more. It is the foundation upon which Scout and
Scout-AI are built.

This documentation is organized into three layers, depending on what
you're trying to do:

## Which documentation should I read?

### I want to build applications using scout-essentials

→ Read the **[User Documentation](user/)**

The user docs are concept-oriented guides that teach you how to use the
library to solve problems. They are organized around tasks, not classes.

**Start here:**
- [Annotating Data](user/AnnotatingData.md) — Attach metadata to objects.
- [Working with Files](user/WorkingWithFiles.md) — Read, write, resolve files.
- [Running Commands](user/RunningCommands.md) — Execute external commands.
- [Logging and Progress](user/LoggingAndProgress.md) — Log messages and progress bars.
- [Handling Streams](user/HandlingStreams.md) — Work with pipes and streams.
- [Caching Results](user/CachingResults.md) — Avoid redundant computation.
- [Producing Resources](user/ProducingResources.md) — Create files on demand.
- [Command-Line Options](user/CommandLineOptions.md) — Parse CLI options.
- [Cookbook](user/Cookbook.md) — Practical recipes combining multiple modules.

### I want to understand how scout-essentials is implemented

→ Read the **[Developer Documentation](developer/)**

The developer docs explain the internal architecture, key abstractions, and
design decisions behind the library.

**Start here:**
- [Architecture](developer/Architecture.md) — Module map and dependency graph.
- [Design Principles](developer/DesignPrinciples.md) — Coding philosophy and idioms.
- [Annotation System](developer/AnnotationSystem.md) — Runtime object extension.
- [Path Resolution](developer/PathResolution.md) — Map-based file resolution.
- [Persistence and Resources](developer/PersistenceAndResources.md) — Caching and production.
- [Streaming Model](developer/StreamingModel.md) — ConcurrentStream lifecycle.

### I'm investigating a subsystem in deep detail

→ Read the **[Research Artifacts](../research/)**

These are curated architectural investigations. They are **non-normative**:
they may contain implementation history, abandoned ideas, and experimental
observations. They are supporting material, not primary documentation.

## Documentation philosophy

- **User documentation** teaches how to build with scout-essentials.
- **Developer documentation** explains how scout-essentials itself is built.
- **Research artifacts** preserve the reasoning behind the current design.

Each layer becomes progressively more detailed while remaining focused on
its intended audience.
