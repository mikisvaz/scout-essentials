# Command-Line Options

This guide explains how to define and parse command-line options in
scout-essentials using the SOPT (SimpleOPT) module.

## When to use this

- You're writing a command-line script or tool.
- You need to parse `-f`, `--flag`, `--option=value` style options.
- You want auto-generated help text from compact definitions.
- You need a lightweight alternative to `optparse`.

## Concepts

### SOPT: Simple Option Parsing

SOPT provides a compact DSL for declaring command-line options and parsing
them from ARGV. It supports short and long option names, boolean flags,
string-valued options, defaults, and descriptions.

```ruby
require 'scout/simple_opt'

# Declare options
SOPT.parse <<~DOC
  -f--file*: Input file (required)
  -o--output: Output directory
  -v--verbose: Enable verbose output
DOC

# Parse ARGV
options = SOPT.consume
# => { file: "data.txt", verbose: true, output: nil }
```

## Basic usage

### Defining options with a documentation string

The most common way to define options is with a heredoc string:

```ruby
SOPT.parse <<~DOC
  -f--file* File to process
  -o--output=results Output directory
  -v--verbose Verbose output
DOC
```

Syntax breakdown:

| Component | Meaning |
|-----------|---------|
| `-f` | Short form (single dash) |
| `--file` | Long form (double dash) |
| `*` | Required option |
| `=results` | Default value |

### Parsing options

After defining options, call `SOPT.consume` to parse `ARGV`:

```ruby
options = SOPT.consume
file = options[:file]
verbose = options[:verbose]
```

### Using parsed options

Parsed options are returned as an IndiferentHash (string/symbol keys work):

```ruby
options = SOPT.consume

puts options[:file]    # symbol key
puts options["file"]   # string key — same value
```

## Option syntax

### Required options

Mark required options with `*`:

```ruby
SOPT.parse "-f--file* Required input file"
```

If a required option is missing, SOPT raises an error.

### Boolean flags

Options without a value are treated as boolean flags:

```ruby
SOPT.parse "-v--verbose Enable verbose mode"

# Usage:
#   ruby script.rb -v      # verbose: true
#   ruby script.rb         # verbose: false (default)
```

### Defaults

Use `=value` for defaults:

```ruby
SOPT.parse <<~DOC
  -t--threads=4 Number of threads
DOC

# If not provided, threads defaults to "4"
```

### Short and long forms

Short forms are optional but recommended for frequently used options:

```ruby
SOPT.parse <<~DOC
  -f--file Input file
  -o--output Output path
  -n--dry-run Dry run mode
DOC

# Both forms work:
#   ruby script.rb -f data.txt
#   ruby script.rb --file data.txt
```

## Advanced usage

### Programmatic registration

Instead of a documentation string, register options individually:

```ruby
SOPT.register("f", "file", "*", "Input file")
SOPT.register("o", "output", nil, "Output path")
```

The `register` signature is: `register(short, long, asterisk, description)`.
- `short`: nil, true (auto-pick), or a letter.
- `long`: the long option name.
- `asterisk`: "*" for required, nil otherwise.
- `description`: help text.

### Auto-generated help text

SOPT generates usage documentation from declared options:

```ruby
puts SOPT.usage
# Output:
# -f--file* Input file
# -o--output Output path
# -v--verbose Verbose mode
```

### Resetting options

If you need to re-define options (e.g., in tests):

```ruby
SOPT.reset
```

This clears all registered options.

### Extracting specific options

You can consume only specific options from ARGV:

```ruby
# Parse only file and output
options = SOPT.get inputs: [:file, :output]
```

### Getting option info

SOPT stores metadata about each option:

```ruby
SOPT.inputs              # => ["file", "output", "verbose"]
SOPT.input_types[:file]  # => :string
SOPT.input_types[:verbose] # => :boolean
SOSOPT.input_descriptions[:file] # => "Input file"
SOPT.input_defaults[:file] # => nil
```

## Common mistakes

### Forgetting to parse

```ruby
# SOPT.parse only DEFINES options; it does NOT parse ARGV
SOPT.parse "-f--file* Input file"

# You must call consume to extract values
options = SOPT.consume
```

### Short form collisions

If two options want the same short form, SOPT will warn. You can let SOPT
auto-pick a short form by passing `nil` or `true`:

```ruby
# Let SOPT pick a unique short form
SOPT.register(nil, "force", nil, "Force overwrite")
```

### Not handling missing options

```ruby
# Boolean options default to false when not provided
# String options default to nil when not provided
options = SOPT.consume
if options[:verbose]
  Log.severity = 0
end
```

## See also

- [Annotating Data](AnnotatingData.md) — SOPT uses IndiferentHash for
  parsed options.
