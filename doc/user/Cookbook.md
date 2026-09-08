# Cookbook

Short, self-contained recipes that combine the scout-essentials modules.
Every snippet here was executed against the current `lib/scout/`.

The theme of the library: plain objects annotated with provenance, paths
resolved from a declaration, work cached on disk, streams piped without
holding everything in memory.

## Get-or-build a file: `claim` + `produce_and_find`

```ruby
require 'scout-essentials'

module Data
  extend Resource
  self.pkgdir = 'cookbook_probe'
end

Data.claim Data.tmp['list'], :string, "S001\nS002\nS003\n"
found = Data.tmp['list'].produce_and_find
Open.read(found)              # => "S001\nS002\nS003\n"
Data.tmp['list'].produce_and_find   # second call returns the same path, no work
```

`Resource.claim(path, type, contents, block)` registers *how* a file is
produced (a type like `:string`/`:proc`, literal contents, or a block); the
claimed `Path` is annotated and its `produce` materialises it into the
resource tree (`lib/scout/resource/path.rb:2`,
`lib/scout/resource/produce.rb`). `produce_and_find` produces when needed and
returns `self.find` (first and second call return the same path, `Open.read`
yields the claimed content).

## Cache invalidation with `:update` and `:check`

`Persist.persist` normally returns the cached value untouched. Two options
change that (`lib/scout/persist.rb`):

```ruby
a = Persist.persist('expensive', :marshal, :update => false) { "computed-once" }
b = Persist.persist('expensive', :marshal, :update => false) { "recomputed" }
a == b                        # => true, block skipped both times
c = Persist.persist('expensive', :marshal, :update => true)  { "forced-recompute" }
c                             # => "forced-recompute" — block re-run

d = Persist.persist('dependent', :marshal,
                    :check => 'tmp/src.txt') { "from-#{Open.read('tmp/src.txt')}" }
```

`:update => true` always re-runs the block; `:check` names a file whose mtime
invalidates the entry (a == b, block not re-run; `:update`
re-runs; `:check` path resolves).

## Fetch a remote file

```ruby
require 'scout-essentials'

url  = 'https://example.org/data.tsv'
Open.wget(url, :auto)         # downloads; cached under Open.remote_cache_dir
data = Open.wget(url)         # serves from cache on the next call

Open.scp('user@host:/path/file', 'local_copy', :target => 'user@host')
```

`Open.wget` shells out to `wget` (`lib/scout/open/remote.rb`); `Open.read` on
an `http(s)://` or `ssh:` URL fetches transparently. Retries and rate limits
are controlled by `Open.wait(lag, key)`. See
[RemoteData.md](RemoteData.md) and
[Working with Files](WorkingWithFiles.md).

## Annotate, serialise, restore

```ruby
require 'scout-essentials'

module SampleInfo
  extend Annotation
  annotation :organism, :tissue
end

sample = SampleInfo.setup('S001', :organism => 'Human', :tissue => 'Liver')
sample.annotation_hash        # {:organism=>"Human", :tissue=>"Liver"}
sample.serialize              # {:organism=>"Human", :tissue=>"Liver",
                              #  :annotation_types=>[SampleInfo], :annotated_array=>false,
                              #  :literal=>"S001"}

restored = Annotation.setup('S003', 'SampleInfo',
                            'organism' => 'Human', 'tissue' => 'Liver')
restored.tissue               # => "Liver"
```

`Annotation.setup(obj, "A|B", hash)` is the module-level deserialiser; the
`"A|B"` string is split on `|` and each name is looked up as a constant. An
unknown type name is **warned about and skipped** (the run prints
`Annotation NoSuchAnnotation not defined` on STDERR, then
`Annotation.setup('S004', 'NoSuchAnnotation', ...)` returns the plain
un-annotated string). `serialize` produces a plain `Hash` with `:literal`,
`:annotation_types` (module objects) and `:annotated_array` keys. There is no
TSV serialisation of annotations in this repo — `Annotation.tsv` belongs to
scout-gear (see the [attribution table](../developer/Architecture.md)).

## Stream a pipeline without buffering

```ruby
require 'scout-essentials'

stream = Open.open_pipe do |sin|
  ['S001', 'S002'].each { |s| sin.write "1\t#{s}\n" }
  sin.close
end
Open.consume_stream(stream)   # => "1\tS001\n1\tS002\n"
```

`Open.open_pipe` builds an IO from a block and returns it unread; `consume_stream`
drains it. `tee_stream` splits one stream into two consumers:

```ruby
Open.write('tmp/in.txt', "1\n2\n3\n")
main, copy = Open.tee_stream(
  CMD.cmd('gzip -c', :pipe => true, :in => Open.open('tmp/in.txt'))
)
Open.consume_stream(main, true, 'tmp/in.txt.gz')   # writes the file
copy.join                                          # waits for the copy thread
File.exist?('tmp/in.txt.gz')                       # => true
```

Consumers follow the rescue contract for the deliberate-abort signals:

```ruby
begin
  data = Open.consume_stream(stream)
rescue Aborted, AbortedStream
  Log.warn "aborted mid-stream"
end
```

(open_pipe data, tee_stream producing a real gzip file).
See [Handling Streams](HandlingStreams.md) and the
[Streaming Model](../developer/StreamingModel.md).

## Progress bars

```ruby
require 'scout-essentials'

items = (1..100).to_a

Log::ProgressBar.with_obj_bar(items, 100) do |bar|
  items.each { bar.tick }
end

Log::ProgressBar.with_bar(20, :desc => 'Counting') do |bar|
  20.times { bar.tick }
end

bar = Log::ProgressBar.new_bar(10, :desc => 'Half-way')
10.times { bar.tick }
Log::ProgressBar.remove_bar(bar)
```

The block of `with_obj_bar` receives **only the bar**; the object is never
yielded back (`log/progress/util.rb:167-170`). The *second* argument selects
the bar: a String is the description, a Numeric the max, a Hash the options,
an existing bar object is reused, and `true` guesses the max from the first
argument via `guess_obj_max` — which returns `nil` even for a plain `Array`
in a bare scout-essentials process: the first `when TSV` arm raises
`NameError` (the constant is not defined here) and the surrounding
`rescue Exception` turns that into `nil` (live check;
`log/progress/util.rb:101-137`). Pass a Numeric max or a `:max` hash for
deterministic sizing. There is no `Log.bar` helper; use
`Log::ProgressBar.new_bar` / `remove_bar`.

## Command-line usage with SOPT

```ruby
require 'scout-essentials'

SOPT.parse <<~OPT
  -o--organism* Organism code
  -t--tissue*   Tissue of origin
  -d--dry-run   Skip writing
OPT

argv    = ['-o', 'Human', 'positional', '-d']
options = SOPT.consume(argv)   # argv is mutated: matched args removed
argv                          # => ["positional"]

SOPT.require(options, :organism)   # ParameterException when nil
```

The `*` marks an option as **taking a string value**; without it the option is
a boolean. (options hash, `argv_left == ["positional"]`,
`SOPT.require` raising). See
[Command-Line Options](CommandLineOptions.md).

## Recipe index

| Task | Tool | Page |
| --- | --- | --- |
| Resolve a path | `Path.setup`, `Resource` | [Working with Files](WorkingWithFiles.md) |
| Run a command | `CMD.cmd` | [Running Commands](RunningCommands.md) |
| Cache a computation | `Persist.persist` | [Caching Results](CachingResults.md) |
| Build a file on demand | `Resource.claim` + `produce_and_find` | [Producing Resources](ProducingResources.md) |
| Annotate objects | `Annotation` | [Annotating Data](AnnotatingData.md) |
| Pipe data | `Open.open_pipe`, `CMD.cmd(:pipe)` | [Handling Streams](HandlingStreams.md) |
| Log and show progress | `Log`, `Log::ProgressBar` | [Logging and Progress](LoggingAndProgress.md) |
| Parse options | `SOPT` | [Command-Line Options](CommandLineOptions.md) |
