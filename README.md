# scout-essentials

scout-essentials is the core library of the Scout framework. It provides a small, focused set of primitives used across the rest of the Scout ecosystem: process/stream management, file and path utilities, persistence and caching, logging and progress reporting, lightweight annotations for objects, and simple option parsing. The additional, domain-level functionality lives in companion packages such as `scout-gear`, `scout-ai`, etc. — see the mikisvaz GitHub account for those repositories.

This README points you to the key modules, shows quick usage patterns and explains where to find more detailed documentation in the `doc/` directory.

## Overview

Core capabilities included in scout-essentials:

- Process and stream management with safe concurrency: `ConcurrentStream`, `CMD`
- Robust file/stream I/O and remote access: `Open`
- File/path abstraction and package-oriented lookup: `Path`, `Resource`
- Atomic persistence and caching: `Persist`, `TmpFile`
- Logging, color output and progress reporting: `Log`
- Lightweight typed annotations on arbitrary objects: `Annotation`, `NamedArray`
- Flexible indifferent Hash and option helpers: `IndiferentHash`, `SimpleOPT` (SOPT)

Each module is documented in the repository `doc/` directory; see the "Documentation" section below for direct links.

---

## Documentation

Full module-level documentation is shipped in `doc/`. The most important documents are:

- doc/Annotation.md — add typed annotations to objects and arrays; AnnotatedArray
- doc/CMD.md — process execution, streaming, tool discovery and helper wrappers
- doc/ConcurrentStream.md — concurrent stream lifecycle, joining, aborting and callbacks
- doc/IndiferentHash.md — string/symbol indifferent Hash helpers and options utilities
- doc/Log.md — logging, colors, fingerprinting and ProgressBar
- doc/NamedArray.md — small record-like arrays with named fields and fuzzy matching
- doc/Open.md — unified file/stream I/O, remote fetch (wget/ssh), atomic writes, sync
- doc/Path.md — Path helpers, mapping, finding and extension utilities
- doc/Persist.md — typed serialization, persistence/caching and `Persist.persist`
- doc/Resource.md — resource production, claim/produce and rake-based producers
- doc/SimpleOPT.md — small option parsing and usage generation (SOPT)
- doc/TmpFile.md — temporary file/dir helpers and stable cache path generator

Open those files for detailed API descriptions, examples and notes.

---

## Quick start (examples)

These short snippets show typical usage patterns — the docs in `doc/` contain more detail and examples.

Annotation:
```ruby
module Tag
  extend Annotation
  annotation :code, :note
end

s = "hello"
Tag.setup(s, :code)    # s.code -> :code
s2 = "other"
s.annotate(s2)         # copies annotations
```

Open (reading a file, auto-decompress):
```ruby
content = Open.read("data.tsv.gz")
```

Persist (cache a computed value):
```ruby
value = Persist.persist("my-result", :json, dir: Path.setup("var/cache")) do
  expensive_computation()
end
```

CMD + ConcurrentStream (run a pipeline):
```ruby
io = CMD.cmd("tail -n 100", :in => some_file_io, :pipe => true)
io2 = CMD.cmd("grep foo", :in => io, :pipe => true)
puts io2.read
io2.join
```

Log + ProgressBar:
```ruby
Log::ProgressBar.with_bar(100, desc: "Working") do |bar|
  100.times { bar.tick; work_item }
end
```

Path + Resource:
```ruby
# Resource modules typically claim resources and produce them on demand.
# Accessing a Path calls produce, so opening a resource Path triggers creation.
p = Path.setup("share/data/myfile", 'mypkg')
p.produce
Open.read(p)
```

---

## Running tests

The test suite exercises the modules (unit tests use Test::Unit). To run the tests in this repository, use your normal Ruby test runner; the test files are under `test/` — examples:

```bash
# from repository root
ruby -Ilib test/scout/test_tmpfile.rb
# or run the whole suite with your preferred runner
```

Tests in the suite show practical usages and edge cases for the provided utilities.

---

## Related projects

scout-essentials is intentionally focused on low-level primitives. Higher-level, domain-specific functionality is implemented in companion projects maintained on the mikisvaz GitHub account (look for repositories named `scout-gear`, `scout-ai`, etc.). Those packages build on what you find here to provide workflows, tools and integrations.

GitHub: https://github.com/mikisvaz  
Look for repositories that begin with `scout-` (e.g. `scout-gear`, `scout-ai`).

---

## Contributing

Contributions and improvements are welcome. Please follow the repository contribution guidelines (if present) or submit issues / pull requests on the project repository.

If you extend or reuse code from this package in companion packages, prefer to keep core primitives here and implement domain logic in separate modules/packages (as done by the Scout ecosystem).

---

## License

See the repository LICENSE (if present) for licensing information.

---

If you need help finding a specific API, open the corresponding file in `doc/` (listed above) or search the `lib/` tree for concrete implementations and tests in `test/` for usage examples.