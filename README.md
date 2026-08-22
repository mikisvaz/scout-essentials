# scout-essentials

scout-essentials is a small Ruby library (gem `scout-essentials`, [VERSION](VERSION)) that provides the shared substrate the other Scout repositories are built on: path and resource resolution, persistence/caching, file and stream I/O, command execution, streaming, annotations, logging and progress reporting, configuration, CLI-option parsing, remote data access and locking.

It deliberately contains no CLI executable, no TSV handling, no workflow engine and no job scheduler. Runtime dependencies are only `term-ansicolor`, `yaml`, `rake` and `listen` ([scout-essentials.gemspec](scout-essentials.gemspec)); it depends on no other scout-family or rbbt-family gem at runtime.

## Central abstractions

| Abstraction | What it is |
|---|---|
| `Path` / `Resource` | `Path` is a `String` carrying annotations that resolves logical names (`data/config.yaml`) to real locations through configurable *path maps*; `Resource` modules declare claims over those paths and `produce` them on demand |
| `Persist` | typed on-disk caching: `Persist.persist(key, type) { ... }` with per-type serialization drivers, staleness invalidation (`:update`/`:check`), an in-memory cache and lock-protected recompute |
| `Open` | one interface for local, compressed (`.gz`/`.bgz`/`.zip`) and remote (`http(s)://`, `ssh:`) file and stream I/O, including atomic `sensible_write` and the `wget`/`rsync` remote cache |
| `CMD` | the subprocess layer: `CMD.cmd` for shell and no-shell commands, stdin piping, timeouts, stderr capture and external-tool bootstrap |
| `ConcurrentStream` | an `IO` extended with the producer threads/pids that feed it, plus join/abort callbacks — the lifecycle layer behind every pipe |
| `Annotation` / `AnnotatedObject` / `AnnotatedArray` | a mixin that attaches named metadata to ordinary Ruby objects (Strings, Arrays, Hashes) without changing their class; the mechanism `Path`, `Resource` and `NamedArray` are built on |
| `Log` / `Log::ProgressBar` | a severity-gated logger writing to STDERR (constants `Log::DEBUG … Log::NONE`) plus stacked progress bars rendered in the same place; colors via `term-ansicolor` |
| `Scout::Config` | a flat `key -> [tokens, value]` registry where, among the entries whose token matches the caller's context, the one with the lowest priority number wins |
| `SOPT` | a minimal option parser: options declared as a single string, a **destructive** consumer that edits `ARGV` in place, no subcommands and no coercion beyond booleans |
| `TmpFile` | scratch files and directories under `$HOME/tmp/scout`, with `·`-flattened names and a 150-character cap |
| `IndiferentHash` | a `Hash` extended so String and Symbol keys are interchangeable, plus the options-processing helpers built on it |
| `NamedArray` | Arrays with named positions (`NamedArray.setup(arr, [:a, :b])`), giving both positional and field-name access |
| `Misc` | small load-bearing helpers: the `Misc.format` family, `timespan`, digests, `insist`, filesystem and process utilities |
| `Lockfile` / `Open.lock` | `Open.lock(file, &block)` is the locking primitive, built on the vendored `Lockfile` at `lib/scout/open/lock/lockfile.rb`; there are three lock namespaces under `$HOME/.scout/tmp` |

`require 'scout-essentials'` is the only entry point (`lib/scout-essentials.rb`); it loads the modules above plus `Open::NamedStream` and the exceptions (`Aborted`, `DontClose`, `ParameterException`, …). `NamedArray` and `Hook` are not auto-loaded and must be required explicitly.

## Getting started

```ruby
require 'scout-essentials'

Open.write('tmp/data.txt', "1\n2\n")   # creates parent directories
Log.info "wrote 2 lines"
Persist.persist('count', :integer) { Open.read('tmp/data.txt').lines.count }
```

Documentation lives in the [`doc/`](doc/StartHere.md) directory — start with [doc/StartHere.md](doc/StartHere.md).

## Relationship to the other Scout repositories

scout-essentials is the lowest layer of the Scout stack; everything above it is implemented in separate repositories:

- **scout-gear** — adds TSV, `Workflow`/`Task`/`Step`, the `scout` CLI and `scout_commands/` dispatch, and the scheduler/HPC layer (SLURM/PBS/LSF, orchestrators) on top of essentials. It declares `scout-essentials` as a runtime dependency.
- **scout-camp** — deploys workflows to the cloud: offsite/terraform/AWS provisioning around the CLI. Its bin loads scout-gear's `bin/scout`; the scheduler logic itself lives in gear.
- **scout-rig** — consumes essentials' `Path`/`Resource` machinery at the code level (`require 'scout'`, `Path.add_path`); its gemspec does not declare the essentials edge.
- **scout-ai** — reaches essentials transitively, via scout-rig and its own `require 'scout'`; it declares no direct dependency on essentials.

Attribution facts worth keeping straight (verified against installed gem sources; see the attribution table in [Architecture](doc/developer/Architecture.md)):

| Concept | Where it actually lives |
|---|---|
| `TSV`, `TSV::Dumper`, `Annotation.tsv`, `Workflow`/`Task`/`Step`, `.info` files, the `scout` CLI and `scout_commands/` | scout-gear |
| scheduler / HPC (SLURM, PBS, LSF, orchestrators) | scout-gear (scout-camp adds the cloud/offside deploy layer) |
| `Misc.notify` / `Misc.send_email` and the `Bgzf` block API | legacy rbbt-util **only** — scout-essentials references them without a require or gemspec edge, so they are `NoMethodError`/`NameError` in an essentials-only install |
| `deep_indifferent` | does not exist anywhere in the audited ecosystem |
| rbbt-util `require_instead` shims | rbbt-util 6.0.5 redirects ~30 requires onto scout files; the *dependency direction* at gemspec level is UNVERIFIED |

## Documentation

22 Markdown pages under [`doc/`](doc/StartHere.md).

Entry points:

- [Start Here](doc/StartHere.md) — installation, the single require, what loads and what does not, what is *not* in this repo
- [Improvements](doc/Improvements.md) — running log of known misbehaviours (bug log, not a roadmap)

User guides:

- [Annotating Data](doc/user/AnnotatingData.md) — attaching metadata to objects
- [Working with Files](doc/user/WorkingWithFiles.md) — `Open` I/O, compression, grepping, atomic writes, locking, `TmpFile`
- [Remote Data](doc/user/RemoteData.md) — HTTP(S)/FTP/SSH fetch, the URL cache, rsync helpers
- [Running Commands](doc/user/RunningCommands.md) — `CMD.cmd`, piping, timeouts, stderr, tool bootstrap
- [Handling Streams](doc/user/HandlingStreams.md) — using `ConcurrentStream` objects: join, abort, callbacks
- [Caching Results](doc/user/CachingResults.md) — `Persist.persist`, serialization types, invalidation, in-memory cache
- [Producing Resources](doc/user/ProducingResources.md) — the `claim` syntax and `produce`
- [Logging and Progress](doc/user/LoggingAndProgress.md) — `Log`, severity, colors, fingerprints, progress bars
- [Command-Line Options](doc/user/CommandLineOptions.md) — `SOPT`
- [Cookbook](doc/user/Cookbook.md) — short executed recipes combining the modules

Developer guides:

- [Architecture](doc/developer/Architecture.md) — module dependency graph, load order, ecosystem boundaries
- [Design Principles](doc/developer/DesignPrinciples.md) — composition by annotation, and the other repo-wide conventions
- [Annotation System](doc/developer/AnnotationSystem.md) — the internals of annotations
- [Path Resolution](doc/developer/PathResolution.md) — path maps, map order, `find`/`follow`, `Resource#method_missing`
- [Persistence and Resources](doc/developer/PersistenceAndResources.md) — the `Persist` and `Resource#produce` write contracts
- [Streaming Model](doc/developer/StreamingModel.md) — how `ConcurrentStream` is built and how errors travel
- [Configuration](doc/developer/Configuration.md) — `Scout::Config` token priorities
- [Error Handling](doc/developer/ErrorHandling.md) — the exception taxonomy and the control-flow signals
- [Locking and Concurrency](doc/developer/LockingAndConcurrency.md) — the vendored `Lockfile` and the three lock namespaces
- [Core Utilities](doc/developer/CoreUtilities.md) — `IndiferentHash`, `NamedArray`, `Misc`, `TmpFile` naming, `Hook`

## Development and testing

```sh
bundle install
rake test                                 # whole suite
rake test TEST=test/scout/test_open.rb    # one file
ruby -Ilib -Itest test/scout/test_misc.rb # run a file directly
```

The `test` task is defined in the [Rakefile](Rakefile) (`Rake::TestTask`, pattern `test/**/test_*.rb`, which matches 49 files on disk: 47 test files (one of which, `test/scout/log/test_color.rb`, is empty) plus the two `test_helper.rb` files, one of which itself defines `TestMiscHelper`). Tests are plain `Test::Unit` and mirror the `lib/scout/` layout. The gemspec is generated by juwelier from the Rakefile — regenerate it with `rake gemspec` rather than editing it.

## License

MIT-style license, Copyright (c) 2023 Miguel Vazquez — see [LICENSE.txt](LICENSE.txt).
