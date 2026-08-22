# Configuration

`Scout::Config` is the registry behind every option the Scout stack reads:
it is a flat `key -> [tokens, value]` store with one rule — **among the
entries whose token matches the caller's lookup context, the entry with the
LOWEST priority number wins**.

Source: `lib/scout/config.rb` (183 lines, whole file), plus
`lib/scout/resource/scout.rb` for `Scout.etc` (`Path.setup("etc")` — see
[PathResolution.md](PathResolution.md)).

## The token priority table

`Scout::Config.token_priority(token)` (`lib/scout/config.rb:38-67`) splits a
token on `::` and returns `[token, priority]`:

| token | priority | who sets it |
|---|---|---|
| `line:<file>:<line>` | 1 | derived from the caller of `Config.get` |
| `file:<file>` | 2 | derived from the caller of `Config.get` |
| `task:<name>` | 3 | passed by higher layers (e.g. a workflow task) |
| `workflow:<name>` | 4 | passed by higher layers |
| anything else | 10 | free-form custom tokens |
| `key:` / `key:<name>` | 20 | the key itself; LOWEST priority |
| `token::N` | N | explicit numeric suffix always wins over the defaults |

Verified by `tmp/rewrite_D/probe_11_token_probe.rb`:

```text
workflow:x   => ["workflow:x", 4]
task:x       => ["task:x", 3]
file:x       => ["file:x", 2]
line:x       => ["line:x", 1]
key:zz       => ["key:zz", 20]
other:x      => ["other:x", 10]
explicit ::5 => ["workflow:x", 5]
```

Lower number = higher precedence, because `Config.get` picks
`priorities.sort_by{|p,v| p}.first` (`lib/scout/config.rb:132`). The `key:`
token (20) is deliberately the weakest, so any context entry can override a
plain value.

## A worked example

A common misreading is "workflow overrides task". The numbers say the
opposite — `line` (1) outranks `workflow` (4). `tmp/rewrite_D/probe_13_get_internals.rb`
stacks all four tokens on one key and shows the chain end-to-end:

```ruby
def fresh(k); Scout::Config::CACHE.delete(k); end

k='q1'; fresh k
Scout::Config.set({k=>'wfv'},'workflow:W')
Scout::Config.set({k=>'taskv'},'task:T')
Scout::Config.set({k=>'filev'},'file:F')
Scout::Config.set({k=>'linev'},'line:L')
Scout::Config.get(k,'workflow:W','task:T','file:F','line:L')
# => "linev"   (line=1 wins)

k='q2'; fresh k
Scout::Config.set({k=>'wfv'},'workflow:W')
Scout::Config.set({k=>'taskv'},'task:T')
Scout::Config.set({k=>'filev'},'file:F')
Scout::Config.get(k,'workflow:W','task:T','file:F')
# => "filev"   (file=2 wins)

k='q3'; fresh k
Scout::Config.set({k=>'wfv'},'workflow:W')
Scout::Config.set({k=>'taskv'},'task:T')
Scout::Config.get(k,'workflow:W','task:T')
# => "taskv"   (task=3 wins)
```

Within one priority bucket the LAST `set` wins (`priorities[prio].unshift`,
`lib/scout/config.rb:83`; verified `probe_13` `two task entries => "second"`).

Explicit suffixes punch through the table, both ways — `::1` promotes an
entry above every default token, `::30` buries it below `key:` (probe_13,
cases `q6`/`q7`). Note the suffix is per-entry, not per-key: it re-prices one
`set` call, it does not change the token for later calls.

### Implicit caller tokens

Every `Config.get` appends `file:<caller>` and `line:<caller>:<n>` derived
from `caller` (`lib/scout/config.rb:119-127`), after filtering out frames
matching the legacy rbbt regexes (see *Legacy internals* below). Entries set
with those tokens match without being named in the call (verified
`probe_12`, `matched by implicit caller file token => "v"`).

## `etc/config` files

`Scout.etc.config` is `Path.setup("etc").config` — typically
`$HOME/.scout/etc/config`. Lines are `key value token...`, `#` comments,
whitespace-separated (`load_file`, `lib/scout/config.rb:15-25`):

```text
# comment
key value token
```

`load_config` walks `Path.setup("etc").config.find_all.reverse`
(`lib/scout/config.rb:27-31`). `find_all` returns paths in `map_order`
(`current, user, home, local, global, usr, lib, fast, cache, bulk, ...`), so
the **reverse** order loads the *most specific* file (e.g. `$PWD/etc/config`)
**first** and `$HOME/.scout/etc/config` last. Two files setting the same key
with the same (implicit `key:`) token were tested by
`tmp/rewrite_D/probe_23_findall_order.rb`:

```text
map_order    => [:current, :user, :home, ...]
find_all     => [/tmp/.../etc/config, /home/.../.scout/etc/config]
loaded order => find_all.reverse  (HOME first, CWD last)
CACHE['shared'] => [key-token fromHOME, key-token fromCWD]
get('shared')   => "fromCWD-currentmap"
```

The `current` map wins even though it was loaded last, because `add_entry`
**appends** and `match` `unshift`s each matching value, so the last-loaded
entry lands at the *front* of the priority bucket and `get` takes
`priorities.sort_by.first`. In short: **later-loaded (more specific) files
win ties**.

`Config.set({key => value}, *tokens)` is the programmatic equivalent; with
one key it auto-adds the `key:<name>` token (`add_entry`,
`lib/scout/config.rb:11-19`).

## `Config.get` value post-processing

`Config.get(key, *tokens)` (`lib/scout/config.rb:94-155`) does four things
after resolving the winner:

1. **`'false'` becomes `false`** — the ONLY string-to-object coercion.
   Verified in `tmp/rewrite_D/probe_10_env.rb`: `'false'` → `false`
   (FalseClass), but `'TRUE'`, `'0'` and `'42'` all stay Strings.
2. **`'nil'` becomes `nil`** (probe_10).
3. **`env:VAR[,VAR2]`** in the resolved value is replaced by the first set
   environment variable, and `get` returns `nil` if none is set (probe_10,
   `'from-env'`).
4. Every `get` appends `[key, value, tokens]` to `GOT_KEYS` — an audit trail
   of what was asked and answered (probe_10). `with_config` snapshots and
   restores it.

Options hash as last argument:

- `:default => v` — used when no entry matches.
- `:env => 'VAR1,VAR2'` — first set env var becomes the default (probe_10).

A `Symbol` key raises `TypeError` — the cache is keyed by `key.to_s`, but
`CACHE[key.to_s]` is called after `match` has already used the raw key;
`Config.get(:symbol)` raises `TypeError: no implicit conversion of Symbol
into String` (probe_10). Use String keys.

## `with_config` and `process_config`

`with_config { ... }` (`lib/scout/config.rb:157-166`) dups every `CACHE`
bucket and `GOT_KEYS`, yields, and restores both in an `ensure`. Anything
`set` inside the block is rolled back — including sets made by code you
call (probe_10: `inside => "inside"`, `after => "outside"`). It is the
mechanism that keeps config changes from leaking out of a sub-operation.

`Config.process_config(config)` (`lib/scout/config.rb:168-180`) interprets
a CLI `--config` argument, in this order:

1. existing file path → `load_file`
2. name of an existing `Scout.etc.config_profile[config]` file → `load_file`
3. otherwise a `"key value token..."` string. The `::N` suffix is mandatory
   in the stored token: any token without one gets `prio = "0"`, i.e. the
   token is re-emitted as `token::0`.

Verified by `tmp/rewrite_D/probe_17b.rb` / `probe_17c.rb`. The subtle part
of case 3 is that the stored token keeps the suffix, so `process_config
"k3 cli workflow::0"` stores the token `workflow::0`, whose *name* is the
bare string `workflow` at priority 0 (stronger than `task`=3,
`file`=2, `line`=1, `key:`=20), and it does **not** match a call like
`get('k3', 'workflow:W')`, because the token *names* differ
(`workflow::0` vs `workflow:W`). Quoting a concrete outcome:

```text
CACHE[k3]                       => [[["workflow::0", "key:k3"], "cli"]]
token_priority('workflow::0')   => ["workflow", 0]
get(k3)                         => "cli"     (via the implicit key: token)
get(k3, 'workflow')             => "cli"     (prio 0 beats key:=20)
get(k3, 'workflow:W')           => nil       (token name mismatch)
```

So a CLI `-config "key val workflow::0"` overrides anything except entries
carrying an explicit smaller `::N` — but only for lookups that pass the bare
`workflow` token.

## Environment variables read by the gem

Verified by grep over `lib/` and, where noted, executed probes
(`tmp/rewrite_D/probe_10_env.rb` covers the `env:`/`:env` machinery; the
rest are read directly from source):

| variable | read by | effect |
|---|---|---|
| `SCOUT_LOG` | `lib/scout/log.rb:35` | sets default log severity |
| `SCOUT_LOG_INSIST` | `lib/scout/misc/insist.rb:35` | logs each insist retry exception |
| `SCOUT_NOCOLOR` | `lib/scout/log/color.rb:137` (also `misc/format.rb:28`) | disables colors / unicode seconds glyph |
| `SCOUT_NO_PROGRESS` | `lib/scout/log/progress.rb:11` | disables progress bars |
| `SCOUT_ORIGINAL_STACK` | `lib/scout/log.rb:261,319` | keeps original exception backtrace |
| `SCOUT_DEBUG_PID` | `lib/scout/log.rb:178` | prefixes messages with the pid |

All are tested with `== 'true'` (except `SCOUT_LOG`, a severity name), so
any other value is false.

`Config.get` itself reads no env var unless `:env` is given or the value is
an `env:` string.

## Legacy internals

The caller-token filter in `Config.get` (`lib/scout/config.rb:119-127`)
still names `rbbt/...` files in its regexes. That is a leftover from the
upstream project this gem was extracted from; the effect here is only that
frames whose path matches those patterns are skipped when deriving
`file:`/`line:` tokens. Nothing else in `scout-essentials` depends on it
(marked INTERNAL in the audit matrix).

## Thread-safety

There is no mutex anywhere in `lib/scout/config.rb` (`Scout::Config` has no
`Mutex` ivar; verified `tmp/rewrite_D/probe_09_threads_fork.rb`). `CACHE`
and `GOT_KEYS` are plain shared structures and `add_entry` does
read-modify-write (`CACHE[key] ||= []; CACHE[key] << ...`). Concurrent
`set`/`get` from threads is therefore unprotected; the gem's own processes
are fork-based, not thread-based (see
[LockingAndConcurrency.md](LockingAndConcurrency.md)).

## Related pages

- [Architecture.md](Architecture.md) — where config sits in the layering.
- [CommandLineOptions.md](../user/CommandLineOptions.md) — the user-facing
  side of `process_config`.
- [PathResolution.md](PathResolution.md) — `Scout.etc`, `find_all` order,
  `etc/config` search path.
- [CachingResults.md](../user/CachingResults.md) — what reads `Config.get`.
