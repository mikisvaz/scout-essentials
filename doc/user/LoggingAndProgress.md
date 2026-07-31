# Logging and Progress

This guide explains how to log messages and display progress bars in
scout-essentials using the Log module.

## When to use this

- You need to log diagnostic messages at different severity levels.
- You want to show progress bars for long-running operations.
- You need colored terminal output.
- You want to redirect logs to a file.

## Concepts

### Log levels

Scout-essentials uses seven severity levels, from most verbose to least:

| Level | Numeric | Method | When to use |
|-------|---------|--------|-------------|
| DEBUG | 0 | `Log.debug` | Detailed diagnostic information |
| LOW | 1 | `Log.low` | Verbose operational details |
| MEDIUM | 2 | `Log.medium` | Normal operational details |
| HIGH | 3 | `Log.high` | Important operational events |
| INFO | 4 | `Log.info` | Informational messages (default) |
| WARN | 5 | `Log.warn` | Warning conditions |
| ERROR | 6 | `Log.error` | Error conditions |

Messages below the current severity threshold are suppressed.

### Progress bars

Progress bars show real-time progress for operations that process a known
number of items. They display: percentage, count, throughput, and ETA.

```ruby
Log::ProgressBar.with_bar(1000, desc: "Processing") do |bar|
  1000.times do
    process_item
    bar.tick
  end
end
```

## Logging messages

### Basic logging

```ruby
Log.info "Starting analysis"
Log.warn "Low disk space"
Log.error "Failed to connect"
Log.debug "Variable x = #{x.inspect}"
```

### Logging with a block (timing)

```ruby
Log.debug "Loading data" do
  @data = load_large_dataset
end
# Logs: "Loading data" with elapsed time
```

### Setting the log level

```ruby
# At runtime
Log.severity = 0  # DEBUG (show everything)
Log.severity = 4  # INFO (default)
Log.severity = 7  # NONE (silence)

# Via environment variable
SCOUT_LOG=DEBUG ruby my_script.rb
```

### Logging to a file

```ruby
Log.logfile("analysis.log")
Log.info "This goes to the file, not stderr"
```

### Disabling color

```ruby
# Via Ruby
Log.nocolor = true

# Via environment
SCOUT_NOCOLOR=true ruby my_script.rb
```

## Progress bars

### Simple progress bar

```ruby
Log::ProgressBar.with_bar(100, desc: "Processing") do |bar|
  100.times do
    do_work
    bar.tick  # increment by 1
  end
end
```

### Setting position explicitly

```ruby
Log::ProgressBar.with_bar(files.size, desc: "Files") do |bar|
  files.each do |file|
    process(file)
    bar.tick
  end
end
```

### Processing variable-size items

```ruby
Log::ProgressBar.with_bar(1024, desc: "Downloading") do |bar|
  chunks.each do |chunk|
    bar.process chunk.size  # advance by chunk size
  end
end
```

### Using progress bars with objects

```ruby
# Process a collection with automatic progress
Log::ProgressBar.with_obj_bar(items, desc: "Processing") do |bar, item|
  bar.process(item)
  process_item(item)
end
```

### Nested progress bars

Multiple bars can be active simultaneously. The system tracks them
internally and renders them without overlapping.

## Colored output

### Coloring text

```ruby
Log.color(:green, "Success!")
Log.color(:red, "Error!")
Log.color(:yellow, "Warning")
```

### Concept colors

Log provides semantic color names for common concepts:

```ruby
Log.color(:title, "Section Header")
Log.color(:path, "/data/file.txt")
Log.color(:value, "42")
```

### Fingerprinting objects

Log can produce compact summaries of objects for logging:

```ruby
Log.fingerprint(large_hash)  # => "{key1=>val1, key2=>val2, ...}"
Log.fingerprint(array)       # => "[1, 2, 3, ...]"
```

## Common mistakes

### Using puts instead of Log

```ruby
# WRONG: raw puts bypasses log level, logfile, and color
puts "Processing..."

# RIGHT: use Log methods
Log.info "Processing..."
```

### Forgetting to tick the progress bar

```ruby
# WRONG: bar stays at 0%
Log::ProgressBar.with_bar(100) do |bar|
  100.times { do_work }
  # forgot bar.tick!
end

# RIGHT
Log::ProgressBar.with_bar(100) do |bar|
  100.times do
    do_work
    bar.tick
  end
end
```

### Setting severity too high during development

```ruby
# During development, lower the threshold for more detail
Log.severity = 0  # DEBUG

# In production, keep it at INFO or higher
Log.severity = 4  # INFO
```

## See also

- [Running Commands](RunningCommands.md) — CMD logs stderr through Log.
- [Handling Streams](HandlingStreams.md) — Streams carry log metadata.
