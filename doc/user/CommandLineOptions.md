# Command-Line Options

`SOPT` is scout-essentials' option parser: a small registry of inputs,
shortcuts and descriptions plus a **destructive** consumer that edits
`ARGV` in place. It is deliberately minimal — no subcommands, no coercion
beyond booleans, no config-file layer.

## Declaring inputs

Options are declared as a single string. Each entry is one line:

```
-[short]--[long][*] description
```

```ruby
require 'scout-essentials'

SOPT.parse <<~OPT
  -o--organism* Organism code
  -t--tissue*   Tissue of origin
  -d--dry-run   Do not write anything
OPT
```

The `*` suffix is the **only** type marker: it marks the option as taking a
string value. Without it the option is a boolean (`lib/scout/simple_opt/parse.rb:53`).
It does **not** mean "required".

`SOPT.setup(str)` parses the same grammar from a fuller usage document —
summary, synopsis (a line starting with `$`), description and options — and
then immediately calls `SOPT.consume`, so it both registers and consumes
`ARGV` in one step (`lib/scout/simple_opt/setup.rb`).

The registry lives in module-level accessors (`simple_opt/accessor.rb`):
`inputs`, `input_types`, `input_shortcuts`, `shortcuts`, `input_descriptions`,
`input_defaults`.

## Consuming the command line

```ruby
options = SOPT.consume          # defaults to ARGV, which it MUTATES
```

`SOPT.consume(args = ARGV)` walks `args` left to right and **deletes**
every token it recognises:

- a matching `--long` or `-s` is removed and, if the input takes a value,
  the following token (or `=value`) is removed with it;
- unknown flags and free-standing words are left alone;
- `--` stops the whole loop: everything after it is left in `args`.

```ruby
# probe_02 (tmp/rewrite_C/probe_02_sopt.rb)
argv = ['-o', 'Human', '--tissue', 'Liver', 'positional', '-d']
SOPT.consume(argv)
# => {:organism=>"Human", :tissue=>"Liver", :"dry-run"=>true}
# argv is now ["positional"]

argv = ['-d', '--', '--not-an-option', '-x']
# => {:"dry-run"=>true}; argv unchanged from "--" onwards
```

Because the array is edited in place, `SOPT.consume` is how a program
separates its own options from the positional arguments it will still read.

### Boolean parsing

Booleans are true unless the value is one of `F`, `false`, `FALSE`, `no`
(`simple_opt/get.rb:45`):

- `--dry-run=false`, `--dry-run=F` → `false`
- `--dry-run` → `true`
- `--dry-run false` → `false`, and Ruby logs a warning telling you to use
  `=` instead — this convenience swallows the next token, so use `=`.

A word that merely *follows* a boolean flag and is not one of those four is
**not** eaten: `['--dry-run', 'stray']` leaves `"stray"` in `ARGV`
(probe_02).

## State and reuse

`SOPT.consume` writes two things:

- the return value (an `IndiferentHash` with symbol keys), which is also
  stashed as `@@current_options`; `SOPT.current_options = hash` lets you
  seed it;
- `SOPT::GOT_OPTIONS`, a module-level hash that is **merged into, never
  reset**. Every `consume` call accumulates there, which is how
  sub-commands that each declare their own inputs still end up with a
  global picture of what was given (probe_02: two separate `consume` calls
  on disjoint inputs both appear in `GOT_OPTIONS`).

`SOPT.get(opt_str)` is just `parse` followed by `consume(ARGV)`.

### `SOPT.require` — the only enforcement

Nothing about a declared option is required. If you want to fail on a
missing option, call it yourself:

```ruby
SOPT.require(options, :organism, :tissue)
# raises ParameterException: Parameter 'tissue' not given
```

`ParameterException < ScoutException < StandardError` (probe_02), so plain
`rescue` works. There is **no** variant that extracts a subset of the
options — `SOPT.get` always parses a fresh string and consumes the whole
`ARGV`.

## Help text

`SOPT.doc` renders a man-page-style document:

```text
myprog(1) -- <summary>
=========================

## SYNOPSYS

myprog [--organism=<string>] [--tissue=<string>] [--dry-run[=false]]

## OPTIONS

-o,--organism=<string>   Organism code
...
```

The header really is `## SYNOPSYS` — the misspelling is in the source
(`simple_opt/doc.rb:112`) and callers grep for it; do not "fix" it in your
matching code. `SOPT.usage` prints the doc and calls `exit 0` (probe_07 traps
`SystemExit` and reports status 0).

`SOPT.input_doc` (used by `doc`) is also the public way to format an
explicit option list, and `SOPT.input_array_doc` formats
`[[name, type, description, default, options], ...]` arrays — that is the
form `Workflow`-level code uses to pass shortcut choices through.

## Shortcuts and `fix_shortcut`

Every declared long name automatically gets a short form: the first letter
of the long name, if it is free (`simple_opt/doc.rb:33`,
`fix_shortcut(name[0], name)`). When it is taken, `SOPT.fix_shortcut`
searches for a free one:

1. an existing shortcut already bound to that exact long name is reused;
2. if the long name contains `-` or `_`, the initials of its parts
   (`--max-cpu` → `-m` if free, else the accumulated initials);
3. if it contains digits, the first letter plus the number;
4. otherwise it walks forward through the letters.

If no shortcut can be found, `fix_shortcut` returns `nil` and the option
simply has no short form. **Collisions are silent**: declaring `-a--alpha`
and `-a--also` yields `{"a"=>"alpha", "al"=>"also"}` — the second entry
gets a longer shortcut rather than an error (probe_02). Live probe
(`tmp/rewrite_C/probe_07_sopt_extra.rb`): registering `t` while `-t` is
bound to `tissue` yields `"th" => "threshold"`; `another_one` gets the
initials `"ao"`; `alpha2` gets `"a2"`.

`SOPT.delete_inputs(['organism'])` removes an input from `inputs`,
`input_shortcuts`, `shortcuts`, `input_types`, `input_defaults` and
`input_descriptions` (`simple_opt/accessor.rb:39`). `input_shortcuts` is the
reverse map `{'organism'=>'o'}` (probe_07).

`SOPT.reset` clears **only** `shortcuts` and the internal `all` registry;
`inputs` and the other per-input tables survive (probe_02). Call
`SOPT.delete_inputs(SOPT.inputs.dup)` if you actually want an empty slate.

## Quirks to design around

- Repeating the same boolean flag just re-sets it to `true`; string
  options keep the last value (the hash is overwritten).
- `--opt=value` and `--opt value` are equivalent; `--opt=` (empty value)
  yields `""`.
- `-x` unknown: left in `ARGV`, ignored.
- `--` is not removed from `ARGV` either; it only stops scanning.
- Options are keyed by their **long** name, symbolised. Shortcuts never
  appear in the result.
- `SOPT.consume` returns the current options *and* keeps them in
  `GOT_OPTIONS`; the two objects are not the same object, and `GOT_OPTIONS`
  is the one that survives later `SOPT.reset` calls.

## Where to go next

- [StartHere](../StartHere.md)
- [Logging and Progress](LoggingAndProgress.md) — `Log.warn` used by the
  boolean heuristic.
- [Architecture](../developer/Architecture.md) — which repos own the
  higher-level CLI layers (attribution table).
