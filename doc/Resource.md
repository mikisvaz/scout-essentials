# Resource

The Resource module provides a filesystem “resource” abstraction and a production system for on-demand creation of files and directories. It integrates tightly with Path and Open: Path objects can be tied to a Resource, and when you attempt to open/read a Path the Resource system may produce that file (download, generate, run a rake task, install software, etc.). Resource also supports simple synchronization, installation helpers and per-package mapping of search paths.

Main responsibilities:
- Declare (claim) resources and how to produce them (string content, proc, URL, rake tasks, installers, etc.).
- Produce (create) resources on demand, with atomic writes and locking to avoid races.
- Map filesystem paths back to logical resource identifiers (identify / relocate).
- Install software helpers and set up environment variables from installed packages.
- Synchronize resources (rsync) into target locations.

Resource is intended to be extended by modules representing package/resource collections. Example in the framework: `Scout` extends Resource and becomes the default resource provider.

---

## Key concepts

- Resource module is extended into a module representing a package or resource collection.
  - Example:
    ```ruby
    module MyPkg
      extend Resource
      self.pkgdir = 'mypkg'
      self.subdir = Path.setup('share/mypkg')   # optional
    end
    ```
- A Resource holds claims: mappings between logical paths and how to produce them.
- Path objects can carry a `pkgdir` referring to a Resource; Path#produce will invoke the corresponding Resource produce logic.

---

## Claiming resources

Use `claim` on a Resource to register how to create a particular logical path:

- Resource.claim(path, type, content = nil, &block)
  - `path` — a Path (or string that will be converted to Path).
  - `type` — a symbol describing how to produce (see below).
  - `content` or block — content, URL, proc, rakefile, installer script, etc.

Common `type` values (used by the built-in produce logic):
- `:string` — static string written to file.
- `:proc` — a Proc that returns content (String, IO, Array, TSV/dumper, etc.). If the proc accepts an arity of 1 it may receive the final filename.
- `:url` — remote URL; the resource is produced by downloading the URL (Open.wget/Open.open).
- `:rake` — a Rakefile or proc to be executed to generate targets via Rake rules (see rake integration).
- `:install` — calls Resource.install to run system-level install helpers for software.
- custom types may be supported by extending Resource.produce or providing other logic.

Examples:
```ruby
module TestResource
  extend Resource
  claim self.tmp.test.string, :string, "TEST"
  claim self.tmp.test.proc, :proc do
    "PROC TEST"
  end
  claim self.tmp.test.google, :url, "http://google.com"
  claim self.tmp.test.rakefiles.Rakefile , :string, "file('foo'){ |t| Open.write(t.name,'FOO') }"
  claim self.tmp.test.work.footest, :rake, TestResource.tmp.test.rakefiles.Rakefile
end
```

---

## Producing resources

- Resource.produce(path, force = false)
  - Produces (creates) the file for `path` according to the claim registered on the Resource.
  - If `force` is true it will overwrite existing file.
  - Uses a lock per target (TmpFile tmp_for_file) and performs atomic write using Open.sensible_write.
  - Supports producing compressed alternatives (tries .gz and .bgz when appropriate).
  - Handles `:string`, `:proc`, `:url`, `:rake`, `:install` and other types as implemented.

Behavior notes:
- For `:proc` type: the proc may return String, IO, Array (written as newlines), TSV dumper, etc. Open.sensible_write is used.
- For streaming scenarios block may produce an IO stream; produce writes the stream atomically using tees and background thread under lock.
- On failure the partial output is removed and exception re-raised.

Convenience wrappers on Path trigger production:
- `Path#produce(force = false)` — call resource-produce for the path.
- `Path#produce_with_extension(ext, *args)` — try producing path or path.ext.
- `Path#produce_and_find(extension = nil, *args)` — produce then return found path.
- `Path#open`/`Path#read` will call `produce` before delegating to Open.

---

## Rake integration

Resource supports producing files by invoking Rake tasks:

- `Resource.claim(..., :rake, rakefile)` — cooker references a Rakefile (Path or proc or string). The Rake file should define file rules/tasks for targets.
- Under the hood:
  - `ScoutRake.run(rakefile, dir, task)` forks and runs Rake in a child, invoking the requested task (task is derived from relative path).
  - `Rake::FileTask.define_task` is hooked to track file tasks.
  - `Resource.run_rake(path, rakefile, rake_dir)` handles invoking the appropriate rake task for a path and supports retries moving up directories to find tasks.

This makes it possible to register a Rakefile that generates many resources via Rake rules.

---

## Identification & relocation

- Resource.identify(path)
  - Given an absolute `path`, try to identify its logical package/path by matching the configured `path_maps` for the resource.
  - Returns an unlocated Path (logical path within the package) or a Path annotated with the resource context.

- Resource.relocate(path)
  - If `path` does not currently exist locally, attempt to identify it and find it in configured maps (e.g., different locations, caches) returning an available path.

- Path#identify (delegates to Resource.identify for Path objects with pkgdir set).
- Use `Resource.identify` to map filesystem locations back to `TOPLEVEL/{PKGDIR}/{SUBPATH}` style logical identifiers.

---

## Sync / rsync support

- `Resource.sync(path, map = nil, options = {})`
  - Copy a resource (file or directory) into a target location determined by resource maps and `map` name (defaults :user).
  - Uses `Open.sync` (rsync wrapper) for actual transfer.
  - Can accept `:resource` option to choose a resource module other than the path's pkgdir.

---

## Software install helpers

Resource includes helpers to install software in a per-resource `software` directory and to set environment variables:

- `Resource.install(content, name, software_dir = Path.setup('software'))`
  - `content` may be a script, Path, String, Hash describing git/src/jar/commands, or a block that returns script text.
  - Builds a wrapper script with a common install helper preamble and executes installation commands (using CMD).
  - After install, calls `Resource.set_software_env(software_dir)`.

- `Resource.set_software_env(software_dir)`
  - Scans `software/opt` configuration files (`.ld-paths`, `.c-paths`, `.pkgconfig-paths`, `.aclocal-paths`, `.java-classpaths`) and adds entries to environment variables (PATH, CLASSPATH, PKG_CONFIG_PATH, etc.).
  - Adds `opt/bin` to PATH and loads `.post_install` exports.

This supports installing package-local tools and updating runtime environment.

---

## Helpers / utilities

- `rake_for(path)`, `has_rake?(path)` — find registered rake dirs that can produce a given path.
- `run_rake(path, rakefile, rake_dir)` — run rake task to produce target.
- `relocate(path)` — attempt to relocate a missing path via resource identification.
- Method delegation: Resource defines `root` and `method_missing` so resource instances behave like a Path root; e.g. `MyResource.foo.bar` delegates to `MyResource.root.foo.bar`.

---

## Concurrency & atomicity

- Resource.produce uses Open.lock to acquire a lockfile for the target before producing, avoiding concurrent producers colliding.
- Writes are performed via `Open.sensible_write` (temp file then atomic mv) to avoid partial files being visible.
- Rake-run and other production steps execute in subprocesses or controlled threads so they don't corrupt the workspace.

---

## Integration details

- Path.open has been overridden to call `produce` for Path objects before delegating to Open.open, so many consumers transparently trigger production when opening resources.
- `Resource.default_resource` can be set to a default package (the framework sets `Resource.default_resource = Scout`).
- Resources use Path.path_maps to find logical locations; packages typically set `pkgdir` and `subdir` and may provide per-resource `path_maps`.

---

## Examples (from tests)

Registering and producing resources:
```ruby
module TestResource
  extend Resource
  self.subdir = Path.setup('tmp/test-resource')

  claim self.tmp.test.string, :string, "TEST"
  claim self.tmp.test.proc, :proc do
    "PROC TEST"
  end
  claim self.tmp.test.google, :url, "http://google.com"
end

TestResource.produce TestResource.tmp.test.string
puts TestResource.tmp.test.string.read   # "TEST"
TestResource.tmp.test.google.produce     # downloads google HTML
```

Rake-based production:
```ruby
# Rakefile claims and tasks:
claim self.tmp.test.rakefiles.Rakefile , :string , <<-EOF
file('foo') { |t| Open.write(t.name, "FOO") }
rule(/.*/) do |t|
  Open.write(t.name, "OTHER")
end
EOF

claim self.tmp.test.work.footest, :rake, TestResource.tmp.test.rakefiles.Rakefile
# produce targets:
TestResource.produce TestResource.tmp.test.work.footest.foo  # runs rake task to create foo
```

Software installation:
```ruby
Resource.install nil, "scout_install_example", tmpdir.software do
  <<-EOF
echo "#!/bin/bash\necho WORKING" > $OPT_BIN_DIR/scout_install_example
chmod +x $OPT_BIN_DIR/scout_install_example
  EOF
end
# then the installed helper is available in PATH via set_software_env
```

Syncing:
```ruby
Resource.sync(source_path, :current)   # rsync source into resource's current map target
```

---

## Notes & caveats

- Resource assumes the availability of external commands when needed (wget, git, bash, rake, etc.).
- Rake tasks are executed in forked subprocesses; Rake definitions must be loadable in that context.
- Production steps must be idempotent or guarded by the lock/atomic write semantics.
- When claiming URL resources, network failures or remote changes can affect production; consider caching strategies or update checks in callers.
- `Resource.identify` relies on path templates and caller libdir heuristics — mapping may require customizing `path_maps` per resource.

---

Resource is intended to centralize how resources for a package are produced and located, to let clients simply ask for a Path and have the resource created on demand with safe concurrency and atomic writes. Use `claim` to declare resources and `produce`/Path.open to trigger creation.