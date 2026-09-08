# Start Here

`scout-essentials` is the lowest layer of the Scout stack: a Ruby gem of
small, composable modules for paths, file I/O, command execution, caching,
annotations, logging, progress bars and option parsing. It deliberately
contains **no** CLI, no TSV handling, no workflow engine and no job
scheduler — those live in other repos (see
[Architecture](developer/Architecture.md), attribution table).

## Installation and first require

```ruby
gem 'scout-essentials'      # Gemfile
```

```ruby
require 'scout-essentials'
Path.setup('tmp/data.txt')          # => annotated String
Open.write('tmp/data.txt', "1\n2\n")
Log.info "wrote 2 lines"
```

### What that single require actually loads

`lib/scout-essentials.rb` is the whole surface — in this order:

| require | gives you |
| --- | --- |
| `scout/exceptions` | `Aborted`, `DontClose`, `DontPersist`, `ParameterException`, … |
| `scout/indiferent_hash` | `IndiferentHash` |
| `scout/tmpfile` | `TmpFile` (also pulls `scout/open`) |
| `scout/log` | `Log`, `Log::ProgressBar` |
| `scout/path` | `Path`, `Resource`-adjacent path helpers |
| `scout/simple_opt` | `SOPT` |
| `scout/resource` | `Resource`, `Scout::Resource` |
| `scout/resource/scout` | scout resource defaults (`pkgdir`, `subdir`) |
| `scout/persist` | `Persist` |
| `scout/config` | `Scout::Config` |

Transitive pulls: `scout/open` (hence `Open`, `CMD`, `NamedStream`),
`scout/annotation` (hence `Annotation`), `scout/misc` (via
`scout/tmpfile`/`scout/open`). Notably **not** loaded by the umbrella
require (against the current `lib/`):

- `NamedArray` — `require 'scout/named_array'`
- `Hook` (a **top-level** `module Hook`, *not* `Misc::Hook`) —
  `require 'scout/misc/hook'`

`Scout::Config` is loaded but you must use the namespaced name.

## What is *not* in this repository

| Not here | Where it lives |
| --- | --- |
| `bin/` CLI, `scout` executable, `scout_commands/` | scout-gear |
| TSV, `TSV` parsing, `Annotation.tsv` | scout-gear |
| `Workflow`, `Step`, job dependencies | scout-gear / scout-rig |
| scheduler, HPC/DRMAA/LSF/SLURM orchestration | scout-workflows |
| `notify`, `send_email` | rbbt-util |
| Bgzf (`Open.bgunzip` is here, the Bgzf block API is not) | scout-gear |
| `deep_indifferent` | nowhere — it does not exist |

See the [attribution table in Architecture](developer/Architecture.md) for
the full map.

## Bug log

[Improvements.md](Improvements.md) is the running log of known
misbehaviours that were documented during the audit
(`TmpFile.with_file` leaking on exception, `Persist` lock races, …). It is
**not** a roadmap; it records what the code actually does versus what you
might expect.

## Development and testing

```sh
bundle install
rake test          # runs the whole suite (49 test files)
rake test TEST=test/scout/test_open.rb
```

The `test` task is defined at `Rakefile:26-28`; the suite lives under
`test/scout/**` and mirrors the module layout (`test_path.rb`,
`test_open.rb`, `test_persist.rb`, `test_annotation.rb`, …). Tests are
plain `Test::Unit` and can be run directly:

```sh
ruby -Ilib -Itest test/scout/test_misc.rb
```

## Where to go next

**User guides** — how to *use* the library:

- [Annotating Data](user/AnnotatingData.md)
- [Working with Files](user/WorkingWithFiles.md)
- [Remote Data](user/RemoteData.md)
- [Running Commands](user/RunningCommands.md)
- [Handling Streams](user/HandlingStreams.md)
- [Caching Results](user/CachingResults.md)
- [Producing Resources](user/ProducingResources.md)
- [Logging and Progress](user/LoggingAndProgress.md)
- [Command-Line Options](user/CommandLineOptions.md)
- [Cookbook](user/Cookbook.md)

**Developer guides** — how the library *works*:

- [Architecture](developer/Architecture.md)
- [Design Principles](developer/DesignPrinciples.md)
- [Annotation System](developer/AnnotationSystem.md)
- [Path Resolution](developer/PathResolution.md)
- [Persistence and Resources](developer/PersistenceAndResources.md)
- [Streaming Model](developer/StreamingModel.md)
- [Configuration](developer/Configuration.md)
- [Error Handling](developer/ErrorHandling.md)
- [Locking and Concurrency](developer/LockingAndConcurrency.md)
- [Core Utilities](developer/CoreUtilities.md)

**Research artifacts** (`../research/`) are non-normative supporting
material: design and behaviour analyses written while this
documentation was produced. The behaviour they describe is captured in
`doc/` and in the `test/` suite, which now carry the same facts in
executable form.
