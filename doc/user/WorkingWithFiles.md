# Working with Files

This guide explains how to read, write, and resolve files in scout-essentials.
You'll learn about the Open module for I/O, the Path module for resolution,
and TmpFile for temporary files.

## When to use this

- You need to read or write files, including compressed (`.gz`, `.bgz`,
  `.zip`) and remote files.
- You want logical path names to resolve to physical locations across
  configurable search directories.
- You need atomic, concurrency-safe file writes.

## Concepts

### Open: unified file I/O

The Open module provides a single interface for reading and writing files,
regardless of whether they are local, compressed, or remote.

```ruby
# Read a plain file
content = Open.read("data.txt")

# Read a gzip file (transparent decompression)
content = Open.read("data.txt.gz")

# Write a file (creates parent dirs automatically)
Open.write("output/result.txt", "hello")
```

### Path: logical-to-physical resolution

Path objects are strings that know how to resolve themselves across a
configured set of search directories called "path maps."

```ruby
# A Path is just a String with resolution behavior
path = Path.setup("data/config.yaml")

# find returns the first existing file across search directories
resolved = path.find
```

### TmpFile: temporary files and directories

TmpFile creates temporary files and directories, with automatic cleanup.

```ruby
TmpFile.with_file do |tmp|
  Open.write(tmp, "temporary content")
  process(tmp)
end  # tmp is deleted after the block
```

## Reading files

### Simple read

```ruby
content = Open.read("data.txt")
lines = content.split("\n")
```

### Reading line by line

```ruby
Open.read("data.txt") do |line|
  puts line
end
```

### Reading compressed files

Open automatically detects `.gz`, `.bgz`, and `.zip` extensions and
decompresses transparently:

```ruby
content = Open.read("data.tsv.gz")  # same as reading uncompressed
```

If you want to read compressed content without decompression, pass `noz:
true`:

```ruby
raw = Open.read("data.tsv.gz", noz: true)
```

### Reading remote files

Open supports URLs and SSH paths:

```ruby
# HTTP/HTTPS
content = Open.read("https://example.com/data.txt")

# SSH (if Open.ssh is configured)
content = Open.read("user@host:/path/to/file")
```

### Filtering while reading

```ruby
# Only lines matching a pattern
Open.read("data.txt", grep: "interesting") do |line|
  puts line
end

# Exclude lines matching a pattern
Open.read("data.txt", invert_grep: "comment")
```

## Writing files

### Simple write

```ruby
Open.write("output/result.txt", "content here")
```

### Writing with a block

```ruby
Open.open("output/result.txt", mode: 'w') do |io|
  io.puts "line 1"
  io.puts "line 2"
end
```

### Streaming content from an IO

```ruby
source = CMD.cmd("generate_data", pipe: true)
Open.write("output/data.txt", source)
```

### Atomic writes

For concurrency-safe writes, use `sensible_write`:

```ruby
Open.sensible_write("output/result.txt", content)
```

This writes to a temporary file first, then moves it into place, preventing
partial reads by other processes.

## Path resolution

### Creating a Path

```ruby
path = Path.setup("data/config.yaml")

# Path objects are also created by Resource modules
path = MyResource.data.config  # builds hierarchical paths
```

### Building paths fluently

```ruby
base = Path.setup("/project")
base.data.samples          # => "/project/data/samples"
base / :config / :default  # => "/project/config/default"
base[:results, :final]     # => "/project/results/final"
```

### Finding files

```ruby
path = Path.setup("data/config.yaml")
path.find        # => first existing match across search maps
path.find_all    # => all existing matches
path.located?    # => true if path is absolute (starts with / ~ or ./)
```

### Path maps

Path maps are templates that define where to look for files. The default
maps include: `current`, `user`, `global`, `cache`, `tmp`, `lib`, and more.

```ruby
# View configured maps
Path.path_maps.keys  # => ["current", "user", "global", ...]

# Add a custom map
Path.add_path(:my_location, "/custom/dir/{PATH}")
Path.prepend_path(:my_location, "/priority/{PATH}")

# Override map order
Path.map_order = [:current, :my_location, :user, :global]
```

Map templates can use placeholders:
- `{PATH}` — the logical path
- `{PKGDIR}` — package directory
- `{SUBPATH}` — sub-path within package
- `{HOME}`, `{PWD}`, `{TOPLEVEL}` — standard locations

### Checking existence

```ruby
path = Path.setup("data/config.yaml")
path.exists?           # => true if file exists at resolved location
path.exists?(produce: true)  # => triggers production if Resource-backed

# Alternative extensions are checked automatically
path.find  # checks .gz, .bgz, .zip alternatives
```

## Temporary files

### Temporary files with automatic cleanup

```ruby
# Create, use, and delete
TmpFile.with_file do |tmp|
  Open.write(tmp, "data")
  process(tmp)
end

# Pre-populate with content
TmpFile.with_file("initial content") do |tmp|
  process(tmp)
end

# Keep the file after the block
TmpFile.with_file("content", false) do |tmp|
  process(tmp)
end  # tmp is NOT deleted
```

### Temporary directories

```ruby
TmpFile.with_dir do |dir|
  # dir is a temporary directory
  Open.write(File.join(dir, "file1"), "a")
  Open.write(File.join(dir, "file2"), "b")
end  # dir is deleted
```

### Generating temporary paths without blocks

```ruby
tmpfile = TmpFile.tmp_file     # => "/home/user/tmp/scout/tmpfiles/tmp-12345"
tmpdir = TmpFile.tmp_for_dir   # => a temporary directory path
```

## Common mistakes

### Forgetting that Open.read handles compression

```ruby
# WRONG: manual decompression
content = `gunzip -c data.gz`

# RIGHT: Open handles it
content = Open.read("data.gz")
```

### Not using atomic writes for shared files

```ruby
# RISKY: other processes may read a partial file
File.write("shared.txt", "content")

# SAFE: atomic write
Open.sensible_write("shared.txt", "content")
```

### Confusing Path#find with file existence

```ruby
# find returns the resolved path or nil; it does NOT return a boolean
path = Path.setup("missing_file")
path.find  # => nil (not false)

# Use exists? for boolean checks
path.exists?  # => false
```

## See also

- [Caching Results](CachingResults.md) — Persist uses Open for atomic writes.
- [Producing Resources](ProducingResources.md) — Resource uses Path for
  resolution.
- For path map internals, see
  [Path Resolution](../developer/PathResolution.md).
