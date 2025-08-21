# SimpleOPT (SOPT)

SimpleOPT (module SOPT) is a lightweight command-line option definition and parsing helper. It provides:

- a small DSL to declare command options (long names, optional single/multi-letter shortcuts),
- automatic generation of usage/documentation text,
- parsing of ARGV-style option lists (boolean flags and string-valued options),
- helpers to build option docs from compact strings or heredocs,
- storage of option metadata (types, descriptions, defaults, shortcuts),
- convenience functions to parse/require options in scripts.

SOPT is split across several files:
- accessor — stores option metadata and simple mutators
- parse — parsing option-definition strings and registering options
- doc — builds usage/documentation output
- get — consumes ARGV-like arrays to produce parsed options
- setup — parse a help string (heredoc) and auto-consume ARGV

Important storage/accessors (module-level):
- SOPT.inputs — ordered list of long option names
- SOPT.shortcuts — map from shortcut string -> long option name
- SOPT.input_shortcuts[long] — chosen shortcut for a long name
- SOPT.input_types[long] — :string or :boolean
- SOPT.input_descriptions[long] — description string
- SOPT.input_defaults[long] — default values (used in docs)
- SOPT.GOT_OPTIONS — IndiferentHash accumulating consumed options across consumes
- SOPT.all (internal map for future use)

Utility accessors: SOPT.reset, SOPT.delete_inputs.

---

## Declaring options

SOPT supports two main declaration styles:

1) Programmatic registration via SOPT.parse or SOPT.register
- parse accepts a compact definition string (see below) and registers options.
- register(short, long, asterisk, description) registers one option:
  - `short` may be nil or a single/multi-letter string (SOPT will try to pick a unique short if you pass nil or true)
  - `long` is the long option name (string)
  - `asterisk` truthy value => treat the option as a string-valued option (type :string). falsy => boolean.
  - `description` is the human-readable description.

2) Declaration via SOPT.setup with a help/heredoc string
- setup parses a help text in the common manpage-ish format: optional summary line, optional `$` synopsys line, description paragraphs, then option lines starting with a dash (one or more).
- Example format (see tests):
  ```
  Test application

  $ test cmd -arg 1

  It does some imaginary stuff

  -a--arg* Argument
  -a2--arg2* Argument
  ```
  - Lines with `-s--long* Description` register options; `*` after `--long` marks a string-valued option.

parse() supports two separators for entries:
- newline-separated entries, or colon-separated entries (when string has no newlines).

parse() expects each entry to contain short and long names in the pattern `-(short)--(long)(*)?` and optional trailing description.

Examples:
- SOPT.parse("-f--first* first arg:-f--fun") registers two options with long names "first" (string) and "fun".
- If you pass '*' in the name pattern, the option is treated as a string-valued input (input_types[long] = :string). Otherwise it is boolean.

SOPT.register handles choosing a unique shortcut:
- SOPT.fix_shortcut picks a non-conflicting short string (initially the first char, then adds additional characters if needed, skipping punctuation characters).
- If fix_shortcut cannot find a unique short, it may return nil — the option will be registered with no shortcut.

---

## Parsing command-line arguments

Primary function: SOPT.consume(args = ARGV)

Behavior:
- Scans through an array of tokens (defaults to ARGV) and removes recognized option tokens from the args array.
- Recognizes:
  - `--key=value` and `-k=value`
  - `--key value` (if option type is :string) or `-k value`
  - boolean flags: `--flag` sets true, `--flag=false` or `--flag=false` will be interpreted as false.
- When parsing, it finds which long option corresponds to the given token:
  - token key string resolved either directly in SOPT.inputs or via SOPT.shortcuts lookup.
  - if the token is not a registered option it is skipped (left in args).
- For :string-typed options, the parser will consume the next token as the value if no `=` was provided.
- For boolean options: if a token immediately following the flag is one of F/false/FALSE/no the parser will warn and treat that token as the value; otherwise presence sets true.
- After parsing, returned options are normalized:
  - IndiferentHash.setup is run on the options hash and keys are converted to symbols via keys_to_sym!
  - The parsed options are merged into SOPT.GOT_OPTIONS (cumulative across calls).
- SOPT.consume returns the parsed options hash (IndiferentHash).

Example:
```ruby
SOPT.parse("-f--first* first arg:-f--fun")
args = "-f myfile --fun".split(" ")
opts = SOPT.consume(args)
# opts[:first] == "myfile"
# opts[:fun] == true
```

Utility:
- SOPT.get(opt_str) — convenience: parse(opt_str) then consume(ARGV) (useful inline to define and parse immediately).
- SOPT.require(options, *parameters) — raise ParameterException if one of the listed parameter names is not present in options (useful to assert required options).

---

## Documentation / usage generation

SOPT can generate usage/help text:

- SOPT.input_format(name, type, default, shortcut)
  - builds a colored option usage fragment, e.g. "-n,--name=<type> (default: ...)"
  - type values used: :string, :boolean (boolean prints [=false] in usage), :tsv/:text/:array treated specially.

- SOPT.input_doc(inputs, input_types, input_descriptions, input_defaults, input_shortcuts)
  - Builds a formatted options block for the help text for a list of inputs.

- SOPT.input_array_doc(input_array)
  - Accepts an array of arrays: [name, type, description, default, options]
    - options may be a shortcut or an options hash (with :shortcut or other info).
  - Produces formatted help entries.

- SOPT.doc
  - Produces a full manpage-style documentation string containing SYNOPSYS, DESCRIPTION and OPTIONS using the stored SOPT.* metadata (command, summary, synopsys, description, inputs, types, defaults).
  - SOPT.usage prints doc text and exits.

- SOPT.setup(str)
  - Conveniently builds the command doc from a help heredoc, registers options, and calls SOPT.consume to parse current ARGV.

Colors and layout use the framework's Log and Misc helpers (Log.color, Misc.format_definition_list, etc.). The doc generation includes default values in option usage.

---

## Metadata & helpers

- SOPT.inputs — list of long option names (strings).
- SOPT.shortcuts — map of chosen shortcut => long option (strings).
- SOPT.input_shortcuts[long] — the chosen shortcut for the given long option.
- SOPT.input_types[long] — :string or :boolean
- SOPT.input_descriptions[long] — documentation string for the option
- SOPT.input_defaults[long] — documented default value (not used by parser automatically)
- SOPT.GOT_OPTIONS — IndiferentHash accumulating parsed options between calls

Mutators / maintenance helpers:
- SOPT.reset — clears internal maps (@shortcuts and @all).
- SOPT.delete_inputs(list_of_inputs) — remove listed inputs and related metadata from SOPT registry.

---

## Edge cases and notes

- Shortcut selection:
  - If you pass `nil` or request automatic shortcuts, SOPT.fix_shortcut attempts to choose a unique shortcut starting from the first char and adding letters if collisions exist. It may return multi-letter shortcuts.
  - fix_shortcut skips punctuation chars (., -, _) when building multi-letter shortcuts.
  - If a unique shortcut cannot be chosen (rare), no shortcut is registered for the option.

- Option value parsing:
  - `*` in the option definition (parse/register) means the option is string-valued; otherwise it is boolean.
  - For booleans, presence sets true; to specify false on the command line either use `--flag=false` or provide `false` (or `F`/`no`) token after the flag — the parser will accept these but warns that `--flag=[true|false]` is preferred.
  - If a string option is given without an explicit `=` and the next token is missing, the value will become `nil` (the parser consumes next token if present).

- Default handling:
  - input_defaults are only used for documentation output. The parser does not automatically apply defaults to parsed options; callers should fill in defaults after parsing if desired.

- Normalization:
  - Parsed options are converted to an IndiferentHash and keys are converted to symbols (`keys_to_sym!`), so consumers can access with either symbol or string keys (but tests expect symbol keys after consume).

- GOT_OPTIONS:
  - SOPT.GOT_OPTIONS accumulates parsed options across multiple consumes; useful for scripts that call consume more than once or want a global snapshot.

- Documentation parsing (setup):
  - SOPT.setup expects a particular structure: optional summary line, optional `$` synopsys line, description paragraphs, followed by option lines beginning with `-`.
  - It calls SOPT.parse on the options block and SOPT.consume to parse current ARGV.

- Error handling:
  - SOPT.require raises ParameterException (from the surrounding framework) if a required option is missing.

---

## Examples

Define options and parse ARGV:

```ruby
# declare from compact string and parse ARGV
SOPT.parse("-f--first* first arg:-s--silent Silent flag")
opts = SOPT.consume(ARGV)
# opts[:first]  => "value" (if provided)
# opts[:silent] => true/false
```

Define options from a help heredoc and auto-consume:

```ruby
SOPT.setup <<-EOF
My command summary

$ mycmd [options] args

This does interesting work

-f--first*  First input file
-s--silent  Run quietly
EOF

# SOPT.setup registers options and consumes ARGV
# Use SOPT.GOT_OPTIONS or result of consume to access parsed options
```

Quick inline parse+consume:

```ruby
SOPT.get("-f--first* first arg:-s--silent")
# Equivalent to SOPT.parse(...) followed by SOPT.consume(ARGV)
```

Require an option:

```ruby
opts = SOPT.consume(ARGV)
SOPT.require(opts, :first)  # raises ParameterException if :first missing
```

Produce usage:

```ruby
puts SOPT.doc   # assemble doc string from registered inputs and descriptions
SOPT.usage      # prints doc and exits
```

---

This covers the common usage patterns and API surface of SimpleOPT. Use SOPT.parse/register to declare options programmatically for small utilities; use SOPT.setup to derive declarations from a help/heredoc and auto-parse ARGV for typical script workflows.