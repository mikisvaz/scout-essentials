# Testing

This guide describes how testing works in `scout-essentials` and establishes conventions intended to be reusable across the Scout ecosystem.

The aim is to make tests easy to write, deterministic, isolated, and understandable by both developers and coding agents. Use the simplest test setup that demonstrates the behavior being tested. Shared helpers should remove repetitive setup, not obscure the test itself.

## 1. Running tests

From the `scout-essentials` checkout, with development dependencies installed:

```sh
bundle install
bundle exec rake test
```

Run a single test file:

```sh
bundle exec rake test TEST=test/scout/test_testing.rb
```

Or invoke it directly:

```sh
bundle exec ruby -Ilib -Itest test/scout/test_testing.rb
```

Run the suite with coverage:

```sh
bundle exec rake simplecov
```

The repository's `Rakefile` defines the `test` task using `test/**/*.rb` files matching `test_*.rb`, with `lib` and `test` on the load path. The `simplecov` task enables coverage through `COVERAGE=true`. The default Rake task delegates to the test suite.

These commands describe `scout-essentials`; other Scout repositories may have additional test tasks, integration suites, or external prerequisites. Check the consuming repository's `Rakefile` and test documentation before assuming the same commands apply.

## 2. Test organization

Tests should normally follow the source directory structure.

For example:

```text
lib/scout/
├── open.rb
├── open/
│   └── remote.rb
└── testing.rb

test/
├── test_helper.rb
└── scout/
    ├── test_open.rb
    ├── open/
    │   └── test_remote.rb
    └── test_testing.rb
```

The convention is that `lib/scout/open/remote.rb` corresponds to `test/scout/open/test_remote.rb`. This is a convention, not an enforced one-to-one mapping: a source file may be covered by several tests, and related behavior may be tested together where that is clearer.

Every new behavior or bug fix should have appropriate test coverage. When adding a source file, normally add its corresponding test file as well.

### Test bootstrap

`test/test_helper.rb` is the local entry point for test setup. It configures the test framework, load paths, coverage, and any shared support needed by the repository.

Individual tests should load the bootstrap following the conventions of their repository and then require the code under test.

Keep these responsibilities separate:

- **Test bootstrap:** framework setup, shared isolation, and repository-wide test configuration.
- **Test support:** reusable fixtures, scenario builders, fake clients, and other test-only utilities.
- **Test files:** setup and assertions specific to the behavior being tested.

Rake discovers files named `test_*.rb` beneath `test/`. Name helper and fixture-builder files differently, usually under `test/support/`, so they are not collected as tests.

## 3. Fixtures: preparing test data

A *fixture* is data or state prepared for a test. Fixtures do not require a special framework. In Scout, ordinary files, Ruby methods, temporary directories, and simple fake objects are sufficient.

Choose between three basic approaches.

### Inline data

Use inline values for short inputs that are easy to understand where they appear.

```ruby
def test_parse_line
  key, values = TSV.parse_line("gene1\tA\tB")

  assert_equal "gene1", key
  assert_equal %w(A B), values
end
```

There is no benefit in creating a separate fixture file for every small input. Keeping the data beside the assertion often makes the test easier to read.

### Static fixture files

Store data in files when it is sizeable, has a meaningful structure, represents an external format, or is reused by multiple tests.

New static test inputs should normally live under `test/fixtures/`, organized by purpose:

```text
test/fixtures/
├── backends/
│   ├── anthropic.json
│   └── anthropic_tool_use.json
└── data/
    └── example.tsv
```

For example, an AI backend test can load a recorded provider response from JSON instead of contacting a real service. A TSV test can use a representative input file instead of embedding several dozen lines in Ruby.

Scout repositories may already use `test/data/` for established datasets. Keep those conventions where they make sense; do not move existing data merely to standardize directory names.

Fixture files belong to the repository whose behavior they test, not to the installed `scout-essentials` library. The shared helper resolves fixture paths relative to the consuming repository.

The generic fixture-path API is:

```ruby
require 'scout/testing'

path = Scout::Testing.fixture_path(
  'backends/anthropic.json',
  from: __FILE__
)

content = File.read(path)
```

`fixture_path` returns a path to the file; it does not parse the contents. Use the appropriate parser, such as `JSON.parse`, when needed. A repository may define a tiny local fixture loader to avoid repeating that parsing code.

### Scenario builders

Sometimes a test needs a group of related files or objects rather than one static input. Examples include workflow directories, persisted conversations, dependency graphs, or a project with source files and corresponding tests.

Create these structures with a small Ruby helper when building them inline would distract from the assertions or when several tests reuse the same scenario.

For example:

```ruby
module ChatFixtures
  def write_chat(dir, name, content)
    path = File.join(dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end
end
```

A more elaborate builder can create several related files and return their paths together. Prefer named results when a scenario has several components:

```ruby
{
  root: root_chat,
  jobs: jobs,
  society_chats: society_chats
}
```

This is easier to understand than a positional array whose entries must be remembered.

Keep builders close to the tests that use them, usually in `test/support/` or a subsystem-specific support file. Introduce a shared builder only when the same meaningful scenario is needed in several places.

**Rule of thumb:** inline data for small examples, static files for substantial inputs, and Ruby builders for constructed scenarios.

## 4. Fakes, mocks, and external services

A fixture supplies data; a fake or mock replaces a dependency or controls its behavior. They are complementary.

Use the least elaborate option that tests the required contract:

- **Inline stub or fake:** when a test needs a small, controlled response from one dependency.
- **Recorded response plus fake client:** when testing how a provider adapter constructs requests and interprets responses.
- **Scripted mock backend:** when testing agent, chat, or workflow behavior without depending on a particular provider's protocol.
- **Real service:** when the service integration itself is the subject of the test.

For normal unit tests, avoid real network requests, live inference, large model downloads, and dependence on a developer's local configuration. Use recorded responses and controlled dependencies instead.

Keep genuine infrastructure tests distinct from ordinary unit tests. Their prerequisites must be explicit, and the default unit-test task should not unexpectedly invoke external services.

## 5. Temporary files and directories

Tests that create files should use isolated temporary storage rather than writing into shared project directories or relying on files left behind by previous runs.

The generic helper is available through an explicit require:

```ruby
require 'scout/testing'
```

For a temporary directory owned by one test:

```ruby
Scout::Testing.with_tmpdir do |dir|
  path = File.join(dir, 'input.txt')
  File.write(path, "example\n")

  # Exercise the code that uses the file.
end
```

The directory is removed in an `ensure` block, including when the test raises an exception.

Use the helper's `parent:` and `prefix:` options when a test needs a particular temporary location or recognizable directory name. Ensure that test processes do not share a cleanup target.

The repository's test bootstrap may expose a local `tmpdir` helper that returns a Scout `Path` object. Use it in tests that depend on Scout path semantics; use the generic temporary-directory helper when building reusable, framework-independent test support.

When a test creates data outside its temporary root, it must arrange cleanup for that data separately.

## 6. Shared testing helpers

The generic testing module is opt-in. It is deliberately not loaded by `require 'scout-essentials'` and does not depend on Scout storage abstractions.

```ruby
require 'scout/testing'
```

Its public helpers are:

| API | Purpose |
|---|---|
| `Scout::Testing.create_tmpdir` | Create a unique temporary directory |
| `Scout::Testing.remove_tmpdir` | Remove temporary storage |
| `Scout::Testing.with_tmpdir` | Create temporary storage, yield it, and clean it up |
| `Scout::Testing.fixture_root` | Locate the fixture directory relative to a consumer |
| `Scout::Testing.fixture_path` | Resolve a fixture file relative to a consumer |
| `Scout::Testing::Assertions#assert_equal_path` | Compare normalized path strings |
| `Scout::Testing::Assertions#assert_path_exists` | Assert that a path exists |

The assertion methods can be included in a Test::Unit test class:

```ruby
class TestExample < Test::Unit::TestCase
  include Scout::Testing::Assertions
end
```

The fixture helpers take `from:` to identify the consuming project's context. They support normal Git repositories and worktrees, as well as conventional `test/` and `lib/` layouts when Git metadata is absent. This is a practical discovery heuristic, not universal repository detection. For nonstandard layouts, pass an explicit `directory:` or construct the path directly.

The shared functions use Ruby standard-library filesystem operations. This is intentional: generic test setup should not depend on Scout's own path resolution or filesystem abstractions, since those abstractions may themselves be under test.

### Scout-specific state isolation

Tests that exercise Scout storage and cache behavior may also need to isolate process-global state. That functionality lives in a separately required module:

```ruby
require 'scout/testing'
require 'scout/testing/scout_state'

Scout::Testing.with_isolated_state('tmp/test-state') do
  # Test code using isolated Scout storage.
end
```

The Scout-state layer isolates and restores selected `TmpFile`, `Persist`, and `Open` settings and the `Persist::MEMORY_CACHE` mapping. It does not reset every global variable, environment setting, singleton, registry, or configuration source.

The shared `test/test_helper.rb` may load both layers because the tests in this repository use both. A consumer that only needs generic filesystem helpers should require only `scout/testing`.

Restoration of process-global state is not synchronization. Tests using this state-isolation mechanism must not run concurrently in the same Ruby process unless they provide additional synchronization. Separate processes or serialized execution are appropriate alternatives.

### Availability primitives

Generic environment-availability primitives live in a third, separately required module:

```ruby
require 'scout/testing/availability'
```

Like the other testing layers, it is opt-in and is never loaded by `require 'scout-essentials'`.

Its scope is deliberately narrow: generic mechanisms only — PATH lookup, bounded child-process execution, and a bounded TCP connect. It contains no knowledge of interpreters, packages, models, or network services. Those probes belong to the layers that own them: the Python/R runtime probes to `scout-rig`, and the accelerator, model-cache, and endpoint probes to `scout-ai`. See the handoff notes `research/testing-availability-scout-rig-handoff.md` and `research/testing-availability-scout-ai-handoff.md` for those layers, including their corrected reference implementations.

The API surface is:

| API | Purpose |
|---|---|
| `Scout::Testing::Availability.executable?(name)` | True when `name` resolves on `PATH`, or contains a path separator and names an executable file. No shell. |
| `Scout::Testing::Availability.run_command(argv, timeout:)` | Run `argv` (never a shell string) with a hard deadline; return a `CommandResult`. |
| `Scout::Testing::Availability.tcp_reachable?(host, port, timeout:)` | True when a TCP connection was established within the timeout. |

`run_command` drains both output pipes concurrently so a chatty child cannot deadlock a pipe, bounds the captured output per stream, and escalates `TERM` then `KILL` to the child's process group when the deadline passes. It is never memoized: availability can change between calls.

The returned `CommandResult` exposes `argv`, `success`/`success?`, `exit_status`, `stdout`, `stderr`, `timed_out`, `launch_error`, and `reason`. Launch failure (for example a missing executable) and timeout are reported on the result rather than raised; only programming errors — a non-positive or non-finite timeout, or an empty `argv` — raise `ArgumentError`.

For example, guarding a test on a local tool:

```ruby
require 'scout/testing/availability'

result = Scout::Testing::Availability.run_command(
  [tool, '--version'], timeout: 10
)
omit result.reason unless result.success?
```

Tests for these primitives follow the same offline discipline as the rest of this guide. The TCP tests bind a local `TCPServer` on `127.0.0.1` with an ephemeral port and add a negative case against a closed local port; the timeout tests use a short deadline against a child that sleeps much longer; no test contacts anything outside the machine.

## 7. Isolation and regression tests

A good test establishes its own relevant conditions, exercises the behavior, and asserts the observable result.

Follow these rules:

- Do not depend on state left by another test or on test-file execution order.
- Use isolated temporary storage for filesystem tests.
- Reset or restore caches, registries, environment variables, logger settings, and other global state that the test changes.
- Use the actual filesystem when testing filesystem semantics, including symlinks and path containment. A mock cannot establish that the real filesystem behaves as expected.
- Make failure cases explicit: invalid input, missing files, rejected operations, exceptions, and cleanup after failure.
- Avoid timing-based assertions when the same property can be checked deterministically.
- Keep test names and assertions focused on behavior rather than implementation details, unless the implementation detail is itself the contract.

For configuration or environment tests, prefer an existing scoped helper when one is available. For example, `Scout::Config.with_config` scopes configuration changes, and `Misc.with_env` restores environment changes. Explicitly save and restore any additional state that the test mutates.

A regression test should capture the smallest useful reproduction of a bug and establish the behavior that must remain stable. Do not reproduce an entire application scenario when a minimal example demonstrates the defect.

## 8. Unit tests, integration tests, and empirical probes

These are different forms of verification.

**Unit tests** establish repeatable behavior using controlled inputs and isolated data. They should normally be fast and should not depend on external infrastructure.

**Integration tests** exercise component boundaries or real services, tools, runtimes, and environments. Record their prerequisites and keep them separate from the default unit-test task where necessary.

**Empirical probes** investigate behavior under particular conditions and record observations. A successful probe does not automatically establish a deterministic contract. When a finding is stable and worth preserving, turn it into a regular test.

These are conceptual categories, not universal Rake task types. Each repository defines how its tests and probes are discovered and executed.

## 9. Boundaries across Scout repositories

The lowest-level testing support should remain small and reusable.

- `scout-essentials` owns generic filesystem helpers, fixture-root lookup, path assertions, its opt-in Scout-state isolation, and the generic availability primitives (`executable?`, `run_command`, `tcp_reachable?`).
- `scout-gear` owns workflow, Step, TSV, Entity, persistence-engine, and scheduler fixtures.
- `scout-ai` owns LLM mocks, fake provider clients, recorded provider payloads, agent scenarios, and Path Engine project fixtures.
- `scout-camp` owns rendering fixtures, temporary view roots, and request-level test support.

Do not put domain-specific setup in the generic test bootstrap simply because several repositories happen to use it. Share mechanics; keep fixtures close to the behavior they represent.

When adding helper code, use a clear name, one responsibility, and the simplest interface that serves its callers. Avoid introducing a general-purpose fixture framework unless repeated, concrete needs justify it.

## References

- [Start Here](../StartHere.md) — installation, overview, and developer-guide index.
- [Architecture](Architecture.md) — library responsibilities and boundaries.
- [Configuration](Configuration.md) — `Scout::Config` behavior.
- [Design Principles](DesignPrinciples.md) — observable library conventions.
- [Caching Results](../user/CachingResults.md) — persistence and caching behavior.

The implementation details described here are grounded in the `Rakefile`, `lib/scout/testing.rb`, `lib/scout/testing/scout_state.rb`, `lib/scout/testing/availability.rb`, `test/test_helper.rb`, and the testing-support tests. The `Rakefile` remains authoritative for the commands and discovery rules of this repository.
