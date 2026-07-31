# Cookbook

Practical recipes combining multiple scout-essentials utilities to solve
common tasks. Each recipe is self-contained and shows the recommended
approach.

---

## Reading a large TSV file line by line

```ruby
Open.read("data.tsv") do |line|
  fields = line.chomp.split("\t")
  process(fields)
end
```

Open handles `.gz`/`.bgz`/`.zip` compression transparently, so the same code
works for `data.tsv.gz`.

---

## Caching the result of a download

```ruby
content = Persist.persist("ref_data", :string, path: "cache/ref.fa") do
  Open.read("https://example.com/reference.fa")
end
```

First call downloads and caches. Subsequent calls load from cache.

---

## Streaming a command pipeline

```ruby
# Generate → filter → sort, all streaming, with error propagation
generator = CMD.cmd("seq 1 1000", pipe: true)
filter    = CMD.cmd("grep 5", in: generator, pipe: true)
sorter    = CMD.cmd("sort -n", in: filter, pipe: true)

sorter.each_line { |line| puts line }

# Join in reverse order (consumer to producer) to detect failures
sorter.join
filter.join
generator.join
```

---

## Annotating a list of sample names with metadata

```ruby
module SampleInfo
  extend Annotation
  annotation :organism, :tissue, :donor
end

samples = ["S001", "S002", "S003"].map do |name|
  SampleInfo.setup(name.dup, organism: "Human", tissue: "Liver")
end

samples.each do |s|
  puts "#{s} (#{s.organism}, #{s.tissue})"
end
# S001 (Human, Liver)
# S002 (Human, Liver)
# S003 (Human, Lua)
```

---

## Building a progress-bar-enhanced file processor

```ruby
files = Dir.glob("data/*.txt")

Log::ProgressBar.with_bar(files.size, desc: "Processing") do |bar|
  files.each do |file|
    content = Open.read(file)
    process(content)
    bar.tick
  end
end
```

---

## Atomic write of computed results

```ruby
result = compute_result()

# sensible_write ensures no partial reads by other processes
Open.sensible_write("output/result.txt", result)
```

---

## On-demand resource production with caching

```ruby
module GenomeRef
  extend Resource
  self.pkgdir = 'genome'

  claim self.hg38_fa, :url, "https://example.com/hg38.fa.gz"
  claim self.hg38_index, :proc do
    CMD.cmd("samtools faidx #{GenomeRef.hg38_fa.produce}")
  end
end

# First access downloads and builds
index_path = GenomeRef.hg38_index.produce

# Subsequent accesses are instant
Open.read(index_path)
```

---

## Using key-indifferent hashes for configuration

```ruby
config = IndiferentHash.setup({
  server: { host: "localhost", port: 8080 },
  retries: 3,
  "timeout" => 30
})

config[:server][:host]   # => "localhost"
config["server"]["port"] # => 8080
config[:timeout]         # => 30
config["retries"]        # => 3
```

---

## Temporary file with automatic cleanup

```ruby
TmpFile.with_file do |tmp|
  Open.write(tmp, "temporary data")
  result = CMD.cmd("wc -l #{tmp}").read
  puts result
end  # tmp is deleted
```

---

## Named array for structured data

```ruby
record = NamedArray.setup(
  [42, "active", 3.14],
  [:count, :status, :score]
)

puts record[:status]   # => "active"
puts record.to_hash    # => {:count=>42, :status=>"active", :score=>3.14}
```

---

## Annotated streams with metadata

```ruby
stream = CMD.cmd("grep error /var/log/syslog", pipe: true)
stream.filename = "error_lines"
stream.extend(Log)  # not necessary; for illustration

lines = stream.read.split("\n")
stream.join

Log.info "Found #{lines.size} error lines from #{stream.filename}"
```

---

## Path resolution with custom maps

```ruby
# Add a custom search location
Path.add_path(:cluster_data, "/shared/data/{PKGDIR}/{SUBPATH}")

path = Path.setup("genome/hg38.fa")
path.find  # checks current dir, user dir, global, /shared/data/..., etc.
```

---

## Persisting complex objects

```ruby
# Marshal can store any Ruby object
Persist.persist("model_state", :marshal) do
  { weights: [0.1, 0.2, 0.3], bias: 0.5, trained: true }
end
```

---

## Combining annotation and path resolution

```ruby
module DataPipeline
  extend Resource
  self.pkgdir = 'pipeline'

  claim self.input.data, :url, "https://example.com/input.dat"
  claim self.output.results, :proc do |filename|
    input = DataPipeline.input.data.produce
    output = CMD.cmd("process_tool #{input}").read
    Open.write(filename, output)
    nil
  end
end

# Everything is lazy — production chains automatically
results = DataPipeline.output.results.produce
```

---

## Logging with timing

```ruby
Log.debug "Loading dataset" do
  @data = Open.read("large_file.tsv").split("\n")
end
# Log output: "Loading dataset (1.2s)"
```

---

## Case-insensitive hash for user input

```-resync
```ruby
params = CaseInsensitiveHash.setup({Format: "CSV", TYPE: "gene"})

params["format"]  # => "CSV"
params[:type]     # => "gene"
```

---

## Writing a command-line tool with SOPT

```ruby
#!/usr/bin/env ruby
require 'scout/simple_opt'
require 'scout/open'
require 'scout/log'

SOPT.parse <<~DOC
  -f--file* Input file
  -o--output Output file
  -v--verbose Verbose mode
DOC

options = SOPT.consume

Log.severity = 0 if options[:verbose]
file = options[:file]

content = Open.read(file)
processed = process(content)

if options[:output]
  Open.sensible_write(options[:output], processed)
else
  puts processed
end
```

---

## See also

Each recipe builds on the concepts explained in the individual user guides:

- [Annotating Data](AnnotatingData.md)
- [Working with Files](WorkingWithFiles.md)
- [Running Commands](RunningCommands.md)
- [Logging and Progress](LoggingAndProgress.md)
- [Handling Streams](HandlingStreams.md)
- [Caching Results](CachingResults.md)
- [Producing Resource](ProducingResources.md)
- [Command-Line Options](CommandLineOptions.md)
