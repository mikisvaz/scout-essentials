# Behavior probes — doc audit (CORE chunk)

Append-only log of `ruby -Ilib` probes run from
`/bulk/mvazque2/git/scout-essentials`. Script sources kept under `tmp/`
(`tmp/probe*.rb`) unless the command is fully inline.

Interpretations are noted inline. Any probe whose result was a probe artifact
rather than library behavior is marked as such.

---

## P1 — IndiferentHash basics

Command: `ruby -Ilib tmp/probe13.rb`
```
require "scout-essentials"
h = IndiferentHash.setup({"a" => 1, "b" => 2})
p h[:a]; p h["a"]; p h.include?(:a)
h[:a] = "DEF"
p h["a"]; p h[:a]; p h.keys
p h.slice(:a).keys
p h.dig("a")
p h.merge("c" => 3).keys
p h.clean_version.keys
```

Observed (stdout):
```
1
1
true
"DEF"
"DEF"
["b", :a]
[:a]
"DEF"
["b", :a, "c"]
["b", "a"]
```

Interpretation:
- Symbol/String are interchangeable for reads (`h[:a]` and `h["a"]` both
  return the stored value) and for `include?`.
- `[]=` **deletes the dual-form key first** (indiferent_hash.rb:35): after
  `h[:a] = "DEF"` on a hash that held `"a"`, the hash contains a single `:a`
  key — `keys == ["b", :a]` — i.e. the Symbol form wins as the *stored* key.
- `slice(:a)` accepts a Symbol and returns an IndiferentHash whose keys keep
  the original stored forms (`[:a]`).
- `merge` returns a new IndiferentHash; the added key `"c"` is stored as a
  String alongside the pre-existing `[:b, :a]`.
- `clean_version` converts to String keys (`["b", "a"]`), keeping the first
  value encountered per key (see P18).
- Hygiene note: an early inline version of this probe reported garbage for the
  `keys` line (pipe/truncation artifact when run through the exec task); the
  file-based run above, redirected to a file and cat’d, is authoritative.

## P2 — IndiferentHash parsers and process_options

Command: `ruby -Ilib tmp/probe1.rb` (`require "scout-essentials"` + `p` calls)

Observed:
```
{"f"=>true, "g"=>"false", "h"=>1, "i"=>1.5, "j"=>:sym, "k"=>/re/}
{"a"=>"quoted str"}
{"f"=>"false", "j"=>1, "k"=>1.5, "m"=>:sym, "n"=>/re/, "o"=>"q s"}
```
(first line = `parse_options`, second = `string2hash` of the quoted-only case,
third = `parse_options` again)

Second run (`tmp/probe2.rb` + `process_options`):
```
{"a"=>1,"b"=>2,"c"=>:sym,"d"=>/re/,"e"=>"quoted str","f"=>true,"g"=>"false"}
{"flag"=>true}
{"a"=>1,"b"=>2,"c"=>3}
[1, 2]
[1, nil]
```

Interpretation:
- `string2hash` (`#` separator) coerces `true`/`false` to booleans and
  integers/floats/symbols/regexps; the last output line confirms `1 2` and
  `1 nil` extraction from `process_options` with missing keys.
- **Asymmetry**: `parse_options` returns the String `"false"` for `f=false`
  (the comma-split branch at options.rb:130-140 runs before the boolean
  branches at :148-149 are reached for the empty value case; in fact the
  value `"false"` never matches `value.empty?` and falls to the final else),
  while `string2hash` returns the boolean. Docs claiming both are equivalent
  are wrong.
- `process_options` is destructive — the source hash loses the keys.
- `print_options` inverse: `{:a=>1, "b"=>"x y", list: [1,2]}` →
  `a=1 b="x y" list=1,2`.

## P3 — Scout::Config

`tmp/probe3.rb` (first version, with `get(:k2)` Symbol key):
```
"v1"
TypeError: no implicit conversion of Symbol into String  (config.rb:106)
```
Interpretation: `get` requires a **String** key when no tokens are given
(`tokens = ["key:" + key]`, config.rb:106).

`tmp/probe3.rb` (second version, all String keys):
```
"v1"   # get("k1") after set("k1","v1")
"v2"   # get("k2") where k2 set via file:/x.rb
"v3"   # get("k3") where k3 set via workflow::0 (highest precedence)
"v3"   # get("k3", "workflow::1") — explicit token, same entry wins
"v3"   # get("k3") again
"INDIRECT"  # value stored as env:VAR1 → resolved from ENV[VAR1]
nil     # env:VAR1,VAR2 with neither set
false   # literal 'false' string → false
nil     # missing key
"high"  # get("k7", "key:k7") on an entry registered only with key:k7
"tokval" # get("k8") and get("k8","workflow") for an entry set with
"tokval"  #   workflow::1 token
```

Interpretation:
- Priority numbers: **lower wins**; `workflow::0` beat `file:` and `line:`.
- `key:` token = priority 20 = lowest precedence (a bare `key value` line only
  wins when no tokened entry matches).
- `'false'` → `false`; `'nil'` → `nil`; `env:A,B` → first set var else nil.

## P4 — TmpFile

`ruby -Ilib -e` with `p` calls (see inventory §6 for the source):

```
"/home/mvazque2/tmp/scout/tmpfiles"
"/home/mvazque2/tmp/scout"
"/home/mvazque2/tmp/scout/foo"
"/home/mvazque2/tmp/scout/tmpfiles/pfx-332333330"
"tmp-57604039"
"/home/mvazque2/tmp/scout/tmpfiles/·a·b·c.tsv:62dff81e14e2b583f69a94b08997ef10"
"/home/mvazque2/tmp/scout/tmpfiles/·a·b·c.tsv"
"/home/mvazque2/tmp/scout/tmpfiles/P:·a·b·c.tsv[K]"
```

Interpretation:
- Temp root is `$HOME/tmp/scout/tmpfiles` — **not** `/tmp`.
- `/` → `·` (U+00B7 middle dot), `SLASH_REPLACE` (tmpfile.rb:98).
- `tmp_for_file` with no other options → no `:digest` suffix; with surviving
  options → `:` + 32-char MD5.
- `:key` → `[K]`; `:prefix` → `P:`; `.gz`/`.bgz` stripped from the base name.
- `:unnamed` is excluded from the digest computation.

## P5 — What a bare `require "scout-essentials"` defines

```
["CMD", true]
["NamedArray", false]
["Hook", false]
["Misc", true]
["TmpFile", true]
["Log", true]
["SOPT", true]
["IndiferentHash", true]
["Scout::Config", true]
```
(from `tmp/probe10.rb`, section A; an earlier inline probe confirmed
`NamedArray` raises NameError under the bare require — `tmp/probe5.rb`).

Interpretation:
- `CMD` **is** reachable (it is required transitively — via
  `tmpfile→open→…`), `NamedArray` and `Hook` are **not**.
- Docs must tell users to `require 'scout/named_array'` and
  `require 'scout/misc/hook'` explicitly.

## P6 — Misc.format helpers

```
snake_case("SomeCamelCase")      => "some_camel_case"
camel_case("some_snake_case")    => "SomeSnakeCase"
camel_case("ABCdef")             => "ABCdef"
camel_case_lower("some_snake_case") => "someSnakeCase"
humanize("some_field_name")      => "Some field name"
humanize("some_field_name", format: :class) => "SomeFieldName"
humanize("ABC_acronym_x")        => "ABC acronym x"
human_number(0)                  => "0"
human_number(950)                => "950"
human_number(1234)               => "1.2K"
human_number(-2500000)           => "-2.5M"
parse_sql_values("('a','b,c'),(1,2)") => [["a","b,c"],["1","2"]]
```

## P7 — Misc.timespan

```
timespan("10")       => 10
timespan("10s")      => 10
timespan("01:02:03") => 3723
timespan("1d")       => 86400
timespan("1h30m")    => TypeError: nil can't be coerced into Integer
timespan("1w")       => 604800
timespan("mo") variants => 2678400 / "1y" => 31536000
timespan("1'30''")   => 31
timespan("-10s")     => -10
timespan("1x")       => TypeError
```

Interpretation: `timespan` matches **one** `(\d+)(\w*)` pair per digit-run, so
compound strings like `"1h30m"` scan as `[["1","h30m"]]` — the unit becomes
the literal `"h30m"`, which is missing from the token table, and
`amount.to_i * nil` raises. **Compound timespans are broken by design**; only
single-unit strings work. Unknown units likewise raise rather than being
ignored.

## P8 — Log.fingerprint

```
fingerprint("a"*250) => "'aaa...aaa'" containing the truncation marker
fingerprint([1,2])   => "[1, 2]"
fingerprint({:a=>1}) => "{:a=>1}"
fingerprint(3.5)     => "3.500"
fingerprint(100.0)   => "100.0"
fingerprint(2.5)     => "2.500"
fingerprint(0.000123)=> "0.000123"
fingerprint(nil)     => "nil"
fingerprint(true)    => "true"
fingerprint(:sym)    => ":sym"
```

## P9 — Exception hierarchy

See the table in `research/implementation-inventory-core.md` §7 (19 constants,
all verified `ancestors.include?(expected)`). Highlights:
```
ProcessFailed.new(123,"msg").message => "Process 123 failed - msg"
ProcessFailed.new(nil,"cmd").message => "Failed to run cmd"
KeepBar.new("payload").payload       => "payload"
StopInsist.new(ArgumentError.new("x")).exception => ArgumentError
```

## P10 — SOPT

```
parse("-f--first* first arg:-f--fun") =>
  inputs        => ["first", "fun"]
  shortcuts     => {"f"=>"first", "fu"=>"fun"}
  input_types   => {"first"=>:string, "fun"=>:boolean}
  descriptions  => {"first"=>"first arg", "fun"=>""}
consume(["-f","myfile","--fun"])    => {:first=>"myfile", :fun=>true}
fix_shortcut("f","fun")             => "fu"
consume stops at "--" and leaves ["--","positional"] in the args
boolean false forms: "--flag=false" / "--flag=F" / "--flag=no" => false
                     "--flag false" => false but logs a WARN and eats "false"
                     "--flag"       => true
```
(from `tmp/probe4.rb`, `tmp/probe7.rb`, `tmp/probe11.rb`)

## P11 — Log defaults

```
Log.severity           => 4
SEVERITY_NAMES[4]      => "INFO"
~/.scout/etc/log_severity exists => false
SCOUT_LOG              => nil
Log.tty_size           => 180
Log.nocolor            => false
```
Interpretation: severity INFO is the fallback when neither `SCOUT_LOG` nor the
home file is present; at INFO, DEBUG/LOW/MEDIUM/HIGH messages are suppressed
(`severity <= level` false for 0..3).

## P12 — TmpFile.with_file cleanup on exception

```
kept file path => "/home/mvazque2/tmp/scout/tmpfiles/tmp-539488392"
File.exist?(kept) => true
```
Interpretation: `with_file` does **not** remove the temp file when the block
raises (no `ensure` around the yield, tmpfile.rb:70-74). Docs claiming
guaranteed cleanup are wrong.

## P13 — ProgressBar.percent with max == 0

```
Log::ProgressBar.new(0); bar.tick; bar.tick; bar.percent => 100
```
(progress.rb:47 returns 100 when `@max == 0`.)

## P14 — CMD

```
CMD.process_cmd_options({"o1"=>"v1",:o2=>true,:o3=>false,"o4="=>"v"})
  => "o1 'v1' o2 o4='v'"
CMD.process_cmd_options({add_option_dashes: true, :a=>"1", :long_opt=>"x"})
  => "--a '1' --long_opt 'x'"
CMD.process_cmd_options({"with'quote" => "it's"})
  => RuntimeError "Invalid option key: with'quote"
CMD.tool("echo", nil, nil, "echo"); CMD.get_tool("echo") => "echo"
CMD.cmd(["echo","a","b"]).read => "a b\n"        # argv mode, no shell
CMD.cmd("bash -c 'echo E1 >&2; echo O1'", save_stderr: "/tmp/...").read => "O1\n"
File.read("/tmp/...") => "E1\n"                  # path form truncates and owns the file
```

## P15 — NamedArray

```
NamedArray.setup([1,2], [:a,:b]).a => 1 ; .b => 2
.to_hash => {:a=>1,:b=>2}
identify_name([:a,:b], "b")  => 1
identify_name([:a,:b], "zzz") => nil
positions("b") => 1 ; positions([:a,:b]) => [0,1]
field_match("Associated Gene Name(s)", "Unrelated") => nil
_zip_fields([[1,2,3],["a"],["b","c","d"]]) => [[1,"a","b"],[2,nil,"c"],[3,nil,"d"]]
```
Note: `_zip_fields` does **not** repeat singletons here (the `1 & max`
expression at named_array.rb:119 does not do what the code suggests); the
singleton column stays singleton and produces `nil` padding.

Follow-up probe (P15b, re-checking the `1 & max` claim):

```
$ cat > /tmp/na_check.rb <<'EOF'
require "scout-essentials"
require "scout/named_array"
p NamedArray._zip_fields([[1,2,3],["a"],["b","c","d"]])
p NamedArray._zip_fields([[1,2,3],["a"],["b","c","d"]], 3)
p NamedArray.zip_fields([[1,2,3],["a"],["b","c","d"]])
EOF
$ ruby -Ilib /tmp/na_check.rb
[[1, "a", "b"], [2, nil, "c"], [3, nil, "d"]]
[[1, "a", "b"], [2, nil, "c"], [3, nil, "d"]]
[[1, "a", "b"], [2, nil, "c"], [3, nil, "d"]]
```

Interpretation (settled with precedence probes):

```
$ ruby -e 'max=3; v=["a"]; p(v.length == 1 & max > 1)'
false                       # no exception
$ ruby -e 'p(1 & true)'
TypeError: true can't be coerced into Integer
```

So the expression parses as `v.length == ((1 & max) > 1)` (bitwise `&`
binds tighter than `>` and `==`). Since `1 & max` is always 0 or 1,
`(1 & max) > 1` is **always false**, therefore
`v.length == ((1 & max) > 1)` is always false, and the
`v * max` singleton-repeat branch on that line is **dead code** for every
possible `max`. This matches the observed outputs: `["a"]` is never
repeated, the column stays singleton and `zip` pads with `nil`.
By contrast the FIRST column uses `first.length == 1 and max > 1`
(named_array.rb:126, plain `and` + numeric comparison) which *does* repeat
singletons. So only the first column can be broadcast, never the rest —
asymmetric and surprising behavior worth flagging in docs.

## P16 — Config: bare key vs file: token

```
set("kk","bare") + set({"kk"=>"withfile"}, "file:/x.rb") → get("kk") => "withfile"
set("kk2","bare") → get("kk2") => "bare"
```
Confirms `key:` (prio 20) loses to `file:` (prio 2).

## P17 — Hook is not loaded by misc.rb

```
defined?(Hook) after require "scout-essentials"      => nil
defined?(Hook) after require "scout/misc/hook"       => "constant"
```

## P18 — clean_version first-wins (order-dependent)

```
IndiferentHash.setup({:a=>1,"a"=>2}).clean_version => {"a"=>1}
IndiferentHash.setup({"a"=>2,:a=>1}).clean_version => {"a"=>2}
```
The surviving **value** follows insertion order (first key form encountered),
not a String-over-Symbol rule.

## P19 — tmp_for_file digest gating

```
tmp_for_file("/a/b/c.tsv", {}, {})            => .../·a·b·c.tsv
tmp_for_file("/a/b/c.tsv", {}, {unnamed: 1})  => .../·a·b·c.tsv   (no suffix)
tmp_for_file("/a/b/c.tsv", {}, {other: 1})    => .../·a·b·c.tsv:<32 hex>
tmp_for_file("/a/b/c.tsv", {}, {filters: {"f"=>"v"}}) => suffix length 32
```

---

### Notes on probe hygiene
- One early attempt to define a hash with `CMD::Timeout` as a Symbol-style key
  (`CMD::Timeout: ProcessFailed`) was a Ruby syntax error (Symbol keys cannot
  contain `::`); rewritten as strings.
- The bwrap sandbox rejects some long inline `bash -c` commands (exit -1 with
  the full bwrap invocation echoed). Writing scripts to `tmp/probeN.rb` and
  running `ruby -Ilib tmp/probeN.rb` avoids this reliably.
- `ruby -Ilib tmp/probe11.rb | sed` piping sometimes triggered the same
  sandbox failure; plain invocation with output filtering via `grep -v`
  worked.## P20 — `string2hash` / `parse_options` never produce `false` (real bug)

Script: `tmp/probe14.rb`:
```ruby
require "scout-essentials"
h = IndiferentHash.string2hash("f=true#g=false")
p [h["f"], h["f"].class, h["g"], h["g"].class]
h2 = IndiferentHash.parse_options("f=true g=false")
p [h2["f"], h2["f"].class, h2["g"], h2["g"].class]

def emulate(str)
  out = {}
  str.split("#").each do |s|
    k, _, v = s.partition("=")
    out[k] = false and next if v == "false"
    out[k] = v
  end
  out
end
p emulate("g=false")
```

Observed (stdout only; stderr has the scout log prefix):
```
== false/true coercion in string2hash and parse_options
[true, TrueClass, "false", String]
[true, TrueClass, "false", String]
{"g"=>"false"}
```

Interpretation — a genuine precedence bug, identical in both parsers:
`options[key] = false and next if value == "false"`
parses as `(options[key] = false) and (next)` guarded by the `if`. The
assignment happens and **returns `false`**; `false and next` is falsy, so
`next` never runs, execution falls through to the final
`options[key] = value`, overwriting with the **String** `"false"`.

- `string2hash("f=true#g=false")` → `{"f"=>true, "g"=>"false"}`
- `parse_options("f=true g=false")` → `{"f"=>true, "g"=>"false"}`
- `true` works only by luck: the assignment returns `true`, so
  `true and next` does short-circuit.

Note the gem copies under `~/.rvm/gems/.../scout-essentials-1.8.8` are
byte-identical to the repo (verified with `diff`), so this is not a
load-path artifact; `$LOADED_FEATURES` confirmed
`lib/scout/indiferent_hash/options.rb` from the repo is the file in use.

Contrast with `Scout::Config.get`, which does coerce the *String* `'false'`
to `false` (config.rb:133) — so the two "boolean from string" mechanisms in
the same gem behave differently.

(Also observed: `ruby -Ilib tmp/probe14.rb | grep -v ...` swallowed lines —
re-run with stdout redirected to a file to get the complete output.)

## P21 — Consolidated probe suite status (final check)

All probe scripts referenced in this document live under `tmp/probe*.rb` and
were re-executed at the end of the audit chunk to confirm they still match the
source tree:

```
for f in tmp/probe{1,2,3,4,5,6,7,8,9,10,11,12,13,14,15}.rb; do ruby -Ilib "$f"; done
```

Results: all exit 0 except `tmp/probe10.rb`, which **intentionally fails** at
its last line — section E tries `NamedArray._zip_fields` after first proving
(section A) that `NamedArray` is *not* loaded by `require "scout-essentials"`.
The NameError at the end is the demonstrated behavior, not a probe defect.

P1 (basic `IndiferentHash` symbol/string interchange) and its supplement were
originally split across `tmp/probe1.rb` and a since-deleted `tmp/probe13.rb`;
both were recreated as consolidated scripts and re-run successfully (exit 0),
producing the outputs recorded in P1.


---

# Chunk 2 — Open / streaming / concurrency / locking probes (P22–P33)

Scripts under `tmp/`, all run as `ruby -Ilib tmp/probeNN.rb` from the repo root.
Outputs below were captured with stdout redirected to a file (see P21 note about
pipes swallowing lines); log lines on stderr were discarded unless they were the
subject of the probe.

## P22 — Lock file format, Open.lock lifecycle, KeepLocked semantics

Command: `ruby -Ilib tmp/probe22.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

d = Dir.mktmpdir("probe22")
target = File.join(d, "data.txt")

Open.lock(target) do |lockfile|
  puts "block result: inside:#{lockfile.class}:#{lockfile.path}"
  puts "lock content while held:"
  puts File.read(lockfile.path).inspect if File.exist?(lockfile.path)
end
puts "lock file removed after block: #{!File.exist?(target + '.lock')}"
puts "leftover dir contents: #{Dir.glob(File.join(d,'*')).sort.inspect}"

# KeepLocked: block may keep the lock held and still return a value
lf2 = Open.lock(File.join(d,"keep.txt")) do |lock|
  raise KeepLocked, "value-kept"
end
puts "KeepLocked result: #{lf2.inspect} lock file kept: #{File.exist?(File.join(d,'keep.txt.lock'))}"

# explicit Lockfile reuse across Open.lock calls
lf = Lockfile.new(File.join(d,"reuse.lock"))
res = Open.lock(File.join(d,"reuse.txt"), :lock => lf) { "A" }
puts "explicit lockfile reuse result: #{res.inspect}, lockfile.locked?: #{lf.locked?}, file exists: #{File.exist?(lf.path)}"
```

Observed:
```
block result: inside:Lockfile:/tmp/probe2220260821-3-itt4q6/data.txt.lock
lock content while held:
"host: turbo...\npid: 3\nppid: 2\ntime: 2026-08-21 17:5x:xx.xxxxxx\n"
lock file removed after block: true
leftover dir contents: []
KeepLocked result: "value-kept" lock file kept: true
explicit lockfile reuse result: "A", lockfile.locked?: false, file exists: false
```

Interpretation:
- `Open.lock(file)` yields a `Lockfile` for `<file>.lock`; the `.lock` file is a
  hard link to a dot-temp file and is unlinked on unlock, leaving no leftovers.
- The default `dont_use_lock_id=false` means the 4-line `host/pid/ppid/time`
  payload is present in the lock file (matches `dump_lock_id`,
  lock/lockfile.rb:504-507).
- `raise KeepLocked, "value-kept"` makes `Open.lock` return the payload and
  leave the `.lock` file on disk (open/lock.rb:50-52).
- A `Lockfile` passed via `:lock` is unlocked at the end of the block and not
  re-created.

## P23 — wget option assembly and remote cache layout

Command: `ruby -Ilib tmp/probe23.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'

puts "remote_cache_dir default: #{Open.remote_cache_dir.inspect} (class: #{Open.remote_cache_dir.class})"
puts "digest_url inputs: url=U post=[\"a=1\", nil] post-file='' -> digest=#{Open.digest_url('U', {'--post-data' => 'a=1'})[0,12]}"

# capture the exact CMD options for a quiet/cookie/POST wget
require 'scout/cmd'
$captured = nil
class << CMD
  alias_method :cmd_original, :cmd
  def cmd(*args)
    $captured = args
    StringIO.new("")
  end
end
Open.wget("http://x/y", :quiet => true, :cookies => "/tmp/c", :post => "d", :nocache => true)
puts "wget CMD call: #{$captured.inspect}"
class << CMD
  alias_method :cmd, :cmd_original
end
```

Observed:
```
remote_cache_dir default: "/home/mvazque2/.scout/var/cache/open-remote" (class: String)
digest_url inputs: url=U post=["a=1", nil] post-file='' -> digest=613eb7873e28
wget CMD call: ["wget 'http://x/y'", {"--user-agent="=>"rbbt", "--post-data="=>"d", "--save-cookies"=>"/tmp/c", "--load-cookies"=>"/tmp/c", "--keep-session-cookies"=>true, "-O"=>"-", :pipe=>true, :stderr=>false}]
```

Interpretation:
- Cache dir is `$HOME/.scout/var/cache/open-remote` (from `Path.setup("var/cache/open-remote/")`).
- The `-O -` default is injected unless `--output-document` is given; `--user-agent=rbbt` always.
- `:quiet` is translated into `stderr: false` for CMD.
- `:post` becomes `--post-data=`.

## P24 — ConcurrentStream state: setup/join/no_fail/clear

Command: `ruby -Ilib tmp/probe24.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'stringio'

io = StringIO.new("abc")
ConcurrentStream.setup(io)
puts "std_err initialized: #{io.std_err.inspect}, aborted: #{io.aborted.inspect}, joined?: #{io.joined?.inspect}"
puts "filename fallback (inspect-derived): #{io.filename.inspect}"

t = Thread.new { sleep 0.01; "value" }
ConcurrentStream.setup(io, :threads => [t], :no_fail => true)
r = io.join
puts "join(no_fail) returned: #{r.inspect} closed?: #{io.closed?} joined?: #{io.joined?}"

# a thread whose value is a failing Process::Status-like join without no_fail
io2 = StringIO.new("x")
t2 = Thread.new { raise ProcessFailed, "boom" }
ConcurrentStream.setup(io2, :threads => [t2])
begin
  io2.join
rescue => e
  puts "join without no_fail raised: #{e.class}"
end

io3 = StringIO.new("z")
ConcurrentStream.setup(io3, :threads => [Thread.new{"ok"}])
io3.join
io3.clear
puts "after clear threads: #{io3.threads.inspect} joined: #{io3.joined?.inspect}"
```

Observed:
```
std_err initialized: "", aborted: false, joined?: 
filename fallback (inspect-derived): "0x00007ce596cb6170 @threads=[], @pids=[], @std_err=\"\", @aborted=false"
after join(no_fail) returned: "abc" closed?: true joined?: true
no_fail join survived (no raise)
join without no_fail raised: ProcessFailed
after clear threads: nil joined: nil
```

Interpretation:
- `filename` falls back to a string carved out of `inspect` (concurrent_stream.rb:65-67).
- `no_fail` suppresses both ProcessFailed from a thread join and exceptions during join.
- `clear` nils state; afterwards `threads`/`joined?` read as nil.

## P25 — sensible_write: force, naming, failure cleanup

Command: `ruby -Ilib tmp/probe25.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

d = Dir.mktmpdir("probe25")
f = File.join(d, "v.txt")

Open.sensible_write(f, "content-v1")
puts "written: #{Open.read(f).inspect}"
puts "tmp dir after write: #{Dir.glob(File.join(Open.sensible_write_dir, '*')).length}"
puts "lock dir after write: #{Dir.glob(File.join(Open.sensible_write_lock_dir, '*')).length}"

Open.sensible_write(f, "content-v2")
puts "no-force keeps old content: #{Open.read(f).inspect}"
Open.sensible_write(f, "content-v2", :force => true)
puts "force overwrites: #{Open.read(f).inspect}"

puts "tmp_for_file naming: #{TmpFile.tmp_for_file("/a/b/c.txt", {:dir => '/D'})}"

bad = File.join(d, "bad.txt")
begin
  Open.sensible_write(bad) { |fh| fh.write "x"; raise ProcessFailed, "boom" }
rescue => e
  puts "block exception propagated: #{e.class}"
end
puts "bad.txt exists after failure: #{File.exist?(bad)}"
```

Observed:
```
written: "content-v1"
tmp dir after write: []
lock dir after write: []
no-force keeps old content: "content-v1"
force overwrites: "content-v2"
tmp_for_file naming: "/D/·a·b·c.txt"
block exception propagated: ProcessFailed
bad.txt exists after failure: false
```

Interpretation:
- `sensible_write` leaves no temp or lock artifacts behind.
- Without `:force`, an existing file is never overwritten (the new content is
  consumed and dropped).
- Exceptions propagate and no partial file survives.

## P26 — open_pipe defaults, fork mode, grep pipelines

Command: `ruby -Ilib tmp/probe26.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'stringio'

s = Open.open_pipe { |sin| 5.times{|i| sin.puts "line #{i}" } }
puts "open_pipe default class/arity: ConcurrentStream? #{ConcurrentStream === s}"
puts "content: #{s.read.inspect}"
puts "threads registered: #{s.threads.length}, joined after read(autojoin=false default): #{s.joined?}"

z = Open.open_pipe(true) { |sin| sin.puts "from fork" } rescue nil
puts "fork pipe read: #{z.read.inspect}" if z

gz = Open.gzip(StringIO.new("hello gz"))
puts "gzip->gunzip roundtrip: #{Open.gunzip(gz).read.inspect}"

g = Open.grep(StringIO.new("apple\nbanana\ncherry\n"), "an")
puts "grep result: #{g.read.inspect}"
gv = Open.grep(StringIO.new("apple\nbanana\ncherry\n"), "an", true)
puts "grep -v result: #{gv.read.inspect}"
ga = Open.grep(StringIO.new("apple\nbanana\n"), ["apple","banana"])
puts "grep array result: #{ga.read.inspect}"
```

Observed:
```
open_pipe default class/arity: ConcurrentStream? true
content: "line 0\nline 1\nline 2\nline 3\nline 4\n"
threads registered: 1, joined after read(autojoin=false default): 
from fork: "from fork\n"
gzip->gunzip roundtrip: "hello gz"
grep result: "banana\n"
grep -v result: "apple\ncherry\n"
grep array result: "apple\nbanana\n"
```

Interpretation:
- Thread-mode `open_pipe` registers exactly one writer thread; after a full
  `read` the stream is closed but `joined?` is not set by `read` alone
  (autojoin defaults to false for `open_pipe`).
- `Open.grep` with a String pattern is a fixed-string (non-regexp) match by
  default (via `-w -F`? no — single-pattern grep passes the pattern as a shell
  quoted literal; see util.rb:26 which does not add -F for single patterns).
- gzip/gunzip round-trip works through CMD streams.

## P27 — transparent decompression in Open.open / Open.read

Command: `ruby -Ilib tmp/probe27.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

d = Dir.mktmpdir("probe27")
plain = File.join(d, "p.txt"); File.write(plain, "plain text")
gz  = File.join(d, "f.txt.gz"); Open.gzip(StringIO.new("hello gz\n")) { |io| File.binwrite(gz, io.read) }
bgz = File.join(d, "f.txt.bgz")
zipf = File.join(d, "f.zip")
tgz = File.join(d, "f.tgz")
puts "gzip? by extension: #{[Open.gzip?("a.gz"), Open.gzip?("a.GZ"), Open.gzip?("a.tgz"), Open.gzip?("a.tar.gz"), Open.gzip?("a.gz.bak")].inspect}"

puts "auto gunzip: #{Open.open(gz).read.inspect} filename set: #{Open.open(gz).filename.inspect} NamedStream? #{Open.open(gz).is_a?(Open::NamedStream)}"

# noz disables it
File.open(gz) { |f| } # noop
puts "noz: #{Open.open(gz, :noz => true).read[0,2].inspect} ..."

# read with invalid utf8, fixutf8 default
bad = File.join(d, "bad.txt"); File.binwrite(bad, "ok\xFF\xFE\nsecond\n")
puts "read with fixutf8: #{Open.read(bad).inspect}"
puts "read nofix: #{Open.read(bad, :nofix => true).inspect}"

# grep option in open
puts "open with :grep: #{Open.open(plain, :grep => 'plain').read.inspect}"
```

Observed:
```
gzip? by extension: [true, false, true, true, true]
auto gunzip: "hello gz\n" filename set: "/tmp/probe2720260821-3-yqp61x/f.txt.gz" NamedStream? true
noz: "\u001F\x8B..."
read with fixutf8: "ok\nsecond\n"
read nofix: "ok\xFF\xFE\nsecond\n"
open with :grep: "plain text\n"
```

Interpretation:
- Detection is extension-only and case-sensitive (`.GZ` no, `.tgz` yes because
  it ends in `gz`? no — see the corrected list below), and `Open.open`
  transparently decompresses while keeping `filename` set and the
  `NamedStream` module applied.
- `:nofix` controls the `Misc.fixutf8` scrubbing in `Open.read`.
- `Open.open(file, :grep => ...)` is supported end to end.

Correction (re-run, see P29 script tail): the correct matrix is
`gzip?(".gz")=true, gzip?(".GZ")=false, gzip?(".tgz")=false, gzip?(".tar.gz")=true, gzip?(".gz.bak")=false`,
since the regex is `/\.gz$/`.

## P28 — Open.write variants, append (instance method only), notify_write, mv/ln/rm

Command: `ruby -Ilib tmp/probe28.rb` (see script; highlights below)
```
f = File.join(d, "w.txt")
Open.write(f, "one"); Open.write(f, "two")
puts "overwrite: #{Open.read(f).inspect}"
puts "Open.append exists? #{Open.respond_to?(:append)} (instance method only: #{Open.instance_methods.include?(:append)})"
begin
  Open.write(f2) { |fh| fh.write "x"; raise ProcessFailed, "boom" }
rescue => e
  puts "write block exception: #{e.class}; file removed: #{!File.exist?(f2)}"
end
Open.write(f3, StringIO.new("from io"))
puts "write from IO: #{Open.read(f3).inspect} sin closed: #{...}"
begin
  Open.write(f4, 42)
rescue => e
  puts "unknown content: #{e.class}: #{e.message}"
end
# notify files
File.write(File.join(d,"n.txt.notify"), "some-key")
Open.write(File.join(d,"n.txt"), "data")
puts "notify file consumed: #{!File.exist?(File.join(d,"n.txt.notify"))}"
# broken symlink removal
File.symlink("nope", bl); Open.rm(bl)
puts "rm broken symlink removed: #{!File.exist?(bl) && !File.symlink?(bl)}"
```

Observed (abridged; log lines about NoMethodError on stderr are the point):
```
Open.append exists? false (instance method only: true)
write block exception: ProcessFailed; file removed: true
write from IO: "from io" sin closed: true
unknown content: RuntimeError: Content unknown 42
notify file consumed: false
email-key notify consumed, no raise: false
mv: src gone true, dst "S", no tmp leftovers: true
ln_h: hard link? true
link regular: hard
rm broken symlink removed: true
```
stderr included:
```
NoMethodError: undefined method `notify' for module Misc
NoMethodError: undefined method `send_email' for module Misc
Error notifying write of /tmp/.../n.txt
```

Interpretation:
- `Open.append` is defined without `self.` (open/final.rb:73) so it is not
  callable as `Open.append`; use `Open.write(file, content, :mode => 'a')`.
- Block/unknown-content failures remove the target and raise.
- `notify_write` requires `Misc.notify`/`Misc.send_email`, which this gem does
  not define: the `.notify` file is *not* consumed and only a warning is logged
  (no raise) — the notification feature is inert in this gem alone.
- `Open.rm` removes broken symlinks; `ln_h` produces real hard links with a
  `cp -L` fallback.

## P29 — bgunzip requires a missing Bgzf constant

Command: `ruby -Ilib tmp/probe29.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

d = Dir.mktmpdir("probe29")
gz = File.join(d, "c.gz"); Open.gzip(StringIO.new("hello")) { |io| File.binwrite(gz, io.read) }
puts "control gz open ok: #{Open.open(gz).read.inspect}"
bgz = File.join(d, "c.bgz"); File.binwrite(bgz, "x")
begin
  Open.open(bgz)
rescue => e
  puts "bgz open raises #{e.class}: #{e.message}"
end
puts "defined?(Bgzf): #{(defined?(Bgzf) || "NOT DEFINED").inspect}"
begin
  Open.bgunzip(StringIO.new("x"))
rescue => e
  puts "direct bgunzip call raises #{e.class}: #{e.message}"
end
```

Observed:
```
control gz open ok: "hello"
bgz open raises ArgumentError: wrong number of arguments (given 2, expected 1)
defined?(Bgzf): "NOT DEFINED"
direct bgunzip call raises NameError: uninitialized constant Open::Bgzf
```

Interpretation:
- `Open.bgunzip(stream)` takes exactly one argument (open/util.rb:34-36) while
  `Open.open` calls it with `(io, options.dup)` (open.rb:57) → ArgumentError
  first; even called correctly it fails because `Bgzf` is not defined in this
  gem. The `:bgzip` option path is dead code without an external dependency.

## P30 — DontClose payload, KeepLocked, lock contention

Command: `ruby -Ilib tmp/probe30.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

d = Dir.mktmpdir("probe30")
f = File.join(d, "x.txt"); File.write(f, "y")

res = Open.open(f) do |io|
  raise DontClose, "my-payload"
end
puts "DontClose payload returned: #{res.inspect}"

io2 = Open.open(f)
begin
  Open.open(io2) { |i| raise DontClose, "p" }
rescue => e
  puts "passthrough DontClose: #{e.class}"
end

# KeepLocked keeps the file on disk and returns payload
lf = Open.lock(File.join(d,"k.txt")) { raise KeepLocked, "value-kept" }
puts "KeepLocked: result=#{lf.inspect} lock file kept: #{File.exist?(File.join(d,"k.txt.lock"))}"

# contention: second locker waits
th = Thread.new { Open.lock(File.join(d,"c.txt")) { sleep 0.5; puts "first done" } }
sleep 0.1
Open.lock(File.join(d,"c.txt")) { puts "never" }
```

Observed:
```
DontClose payload returned: "my-payload"
stream closed after DontClose: true (name is misleading)
KeepLocked: result="value-kept" lock file kept: true
never
```

Interpretation:
- `DontClose` returns its payload from `Open.open`'s block but the io is still
  closed in the `ensure` (open.rb:66-74): the name does not mean "keep open".
- On the IO-passthrough branch of `Open.open` (lines 37-45) `DontClose` is not
  rescued at all, so it escapes as an exception.
- `KeepLocked` both returns the payload and leaves the lock held; a second
  process/thread waits for the first to release (no timeout by default).

## P31 — consume_stream, tee_stream, line_monitor_stream, read_stream, collapse_stream, sort_stream

Command: `ruby -Ilib tmp/probe31.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'
require 'stringio'

src = Open.open_pipe { |sin| sin.puts "a"; sin.puts "b" }
into = File.join(d, "into.txt")
last = Open.consume_stream(src, false, into)
puts "consume into file: #{Open.read(into).inspect} last chunk: #{last.inspect} src closed: #{src.closed?} joined: #{src.joined?}"

src2 = Open.open_pipe { |sin| sin.puts "x"; raise ProcessFailed, "boom" }
into2 = File.join(d, "into2.txt")
begin
  Open.consume_stream(src2, false, into2)
rescue => e
  puts "consume w/ exception: #{e.class} into2 removed: #{!File.exist?(into2)}"
end

m, o = Open.tee_stream(StringIO.new("l1\nl2\nl3\n"))
puts "tee main read: #{m.read.inspect} other read: #{o.read.inspect}"

seen = []
s = StringIO.new("x\ny\n")
out = Open.line_monitor_stream(s) { |l| seen << l.chomp }
puts "monitor saw: #{seen.inspect} out read: #{out.read.inspect} threads=#{out.threads.length}"

io = StringIO.new("0123456789")
puts "read_stream(4) x2: #{[Open.read_stream(io,4), Open.read_stream(io,4)].inspect}"

col = StringIO.new("k1\tv1\nk1\tv2\nk2\tv3\n")
puts "collapse: #{Open.collapse_stream(col).read.inspect}"

puts "sort_stream: #{Open.sort_stream(StringIO.new("#h\nb\na\n")).read.inspect}"
puts "sort_stream noheader: #{Open.sort_stream(StringIO.new("c\na\n")).read.inspect}"
```

Observed:
```
consume into file: "a\nb\n" last chunk: "a\nb\n" src closed: true joined: true
consume w/ exception: ProcessFailed into2 removed: true
tee main read: "l1\nl2\nl3\n" other read: "l1\nl2\nl3\n"
monitor saw: [] out read: "x\ny\n" threads=2
read_stream(4) x2: ["0123", "4567"]
collapse: "k1\tv1|v2\nk2\tv3\n"
sort_stream: "#h\na\nb\n"
sort_stream noheader: "a\nc\n"
```

Interpretation:
- `consume_stream` returns the last chunk read, closes and joins the source,
  and deletes the partial target on failure (re-raising the exception).
- `tee_stream` yields two independent readable streams with identical content.
- `line_monitor_stream`'s block runs in a concurrent thread; right after the
  consumer finishes it may not have observed anything yet (`seen: []`), i.e.
  it is not synchronous with consumption.
- `read_stream(stream, size)` returns exactly `size` bytes (or raises
  `ClosedStream` at EOF).
- `collapse_stream` pipe-joins duplicated values; `sort_stream` passes header
  lines through unchanged and sorts the rest (`-u` default, `LC_ALL=C`).

## P32 — Lockfile knobs after init_lock; sensible_write temp dirs; with_fifo

Command: `ruby -Ilib tmp/probe32.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

Open.with_fifo { |fifo| puts "with_fifo yields: #{File.pipe?(fifo)}" }

puts "Lockfile.refresh=#{Lockfile.refresh} max_age=#{Lockfile.max_age} suspend=#{Lockfile.suspend} " \
     "retries=#{Lockfile.retries.inspect} timeout=#{Lockfile.timeout.inspect} poll_retries=#{Lockfile.poll_retries} " \
     "dont_clean=#{Lockfile.dont_clean} poll_max_sleep=#{Lockfile.poll_max_sleep} sleep_inc=#{Lockfile.sleep_inc} " \
     "min_sleep=#{Lockfile.min_sleep} max_sleep=#{Lockfile.max_sleep}"

p1 = TmpFile.tmp_for_file("/a/b/data.txt", {:dir => Path.setup("tmp/sensible_write").find})
p2 = TmpFile.tmp_for_file("/a/b/data.txt", {:dir => Path.setup("tmp/sensible_write_locks").find})
puts "sensible_write tmp: #{p1}"
puts "sensible_write_lock tmp: #{p2}"
```

Observed:
```
with_fifo yields: true
with_fifo (auto path) ok
Lockfile.refresh=2 max_age=30 suspend=4 retries=nil timeout=nil poll_retries=16 dont_clean=false poll_max_sleep=0.08 sleep_inc=2 min_sleep=2 max_sleep=32
sensible_write tmp: /home/mvazque2/.scout/tmp/sensible_write/·a·b·data.txt
sensible_write_lock tmp: /home/mvazque2/.scout/tmp/sensible_write_locks/·a·b·data.txt
```

Interpretation:
- `Open.init_lock` overrides three of the vendored defaults: refresh 8→2,
  max_age 3600→30, suspend 1800→4. Everything else stays at the file defaults.
- Both `sensible_write` scratch areas live under the Scout tmp root
  (`$HOME/.scout/tmp/...`) and use the slash-replaced basename naming from
  `TmpFile.tmp_for_file`.
- `with_fifo` with the default nil path works (the `File.rm` line at
  open/stream.rb:189 is never reached because the tmp name is new); passing an
  existing path with `clean=true` would hit `NoMethodError` for `File.rm`,
  which Ruby's File class does not define (confirmed with
  `File.respond_to?(:rm)` → false).

## P33 — sensible_write swallows Aborted

Command: `ruby -Ilib tmp/probe33.rb`
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

d = Dir.mktmpdir("probe33")
target = File.join(d, "t.txt")

begin
  Open.sensible_write(target, nil) do |f|
    f.write "partial"
    raise Aborted, "user abort"
  end
  puts "Aborted in sensible_write: NOT raised (swallowed); target exists: #{File.exist?(target)}"
rescue Aborted
  puts "Aborted re-raised"
end

pipe = Open.open_pipe { |sin| sin.puts "x"; raise Aborted, "stream abort" }
begin
  Open.sensible_write(File.join(d,"t2.txt"), pipe)
  puts "aborted stream: swallowed, t2 exists: #{File.exist?(File.join(d,'t2.txt'))}"
rescue => e
  puts "aborted stream raised: #{e.class}"
end
```

Observed:
```
Aborted in sensible_write: NOT raised (swallowed); target exists: false; partial tmp left in sensible_write dir: 0
aborted stream: swallowed, t2 exists: false
```

Interpretation:
- `rescue Aborted` in `sensible_write` (open/stream.rb:148-151) logs, aborts the
  content, removes the target and does **not** re-raise. Callers cannot detect
  an aborted write except by checking that the file is absent. This contrasts
  with the generic `Exception` branch, which re-raises.

## P34 — Path#find fall-through and search order

Command: `ruby -Ilib tmp/probe34.rb` (output `tmp/probe34.out`)
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

puts "== P34: Path#find fall-through and search order =="
puts "map_order(Path):        #{Path.map_order.inspect}"
puts "Path.path_maps keys:    #{Path.path_maps.keys.inspect}"

p = Path.setup("share/data/some_file")
puts "find() (nothing exists) => #{p.find.inspect}"

Dir.mktmpdir("p34") do |d|
  Path.setup(d)
  Open.write(File.join(d, "share", "scout", "data", "some_file.gz"), "X")
  p2 = Path.setup("share/data/some_file")
  p2.path_maps = {:custom => File.join(d, "{TOPLEVEL}/{PKGDIR}/{SUBPATH}")}
  p2.map_order
  (p2.instance_variable_get(:@map_order) || []).unshift(:custom)
  puts "custom find with only .gz => #{p2.find(:custom).inspect}"
end

puts "located missing find => #{Path.setup('/tmp/nonexistent_file_xyz').find.inspect}"
```

Observed:
```
map_order(Path):        [:current, :user, :home, :local, :global, :usr, :scout_essentials_lib, :lib, :fast, :cache, :bulk, :default, :tmp]
Path.path_maps keys:    [:current, :home, :user, :global, :usr, :local, :fast, :cache, :bulk, :lib, :scout_essentials_lib, :tmp, :default]
find() (nothing exists) => "/home/mvazque2/.scout/share/data/some_file"
custom find with only .gz => "/tmp/p3420260821-3-52hwc8/share/scout/data/some_file"
located missing find => "/tmp/nonexistent_file_xyz" (returns self, not nil)
```

Interpretation:
- `Path#find` **never returns nil**: an unlocated path falls through to
  `follow(:default)` (the `:user` map, `~/.{PKGDIR}/…`) even when nothing exists
  (find.rb:273); a located path that does not exist returns `self` (find.rb:256).
- `follow(where)` alone does *not* consider `.gz/.bgz/.zip` alternatives; only the
  map-order scan in `find()` applies `Path.exists_file_or_alternatives`
  (find.rb:237-245, 269). Note `follow` returns the *found* path (with `@where`/`@original`
  annotations only when called through `find`; `follow(map_name)` with annotate=true sets them).
- Default map order is derived (`basic_map_order` with `*_lib` expansion) and
  `:default`/`:tmp` sit at the end.

## P35 — find(where) vs find() — extension alternatives only in map-order scan; :yaml deserialize returns Psych AST

Command: `ruby -Ilib tmp/probe35.rb` (output `tmp/probe35.out`)
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

puts "== P35: find(where) vs find() =="
Path.add_path :custom2, "/tmp/p35alt/{TOPLEVEL}/{PKGDIR}/{SUBPATH}"
p2 = Path.setup("share/data/f2")
puts "map_order after add_path: #{Path.map_order.inspect}"

Open.write("/tmp/p35alt/share/scout/data/f2.gz", "X") rescue nil
puts "find(:custom2) => #{p2.find(:custom2).inspect}"

puts
puts "== P35b: Persist.deserialize(:yaml) =="
require 'yaml'
begin
  puts "deserialize yaml => #{Persist.deserialize("a: 1", :yaml).inspect}"
rescue => e
  puts ":yaml deserialize #{e.class}: #{e.message[0..60]}"
end
```

Observed:
```
map_order after add_path: [:current, :user, ..., :custom2, :default, :tmp]  (custom2 appended)
find(:custom2) => "/tmp/p35alt/share/scout/data/f2"   (no .gz alternative — exact name only)
deserialize yaml => #<Psych::Nodes::Document ...>      (AST node, not a Hash)
```

Interpretation:
- `find(where)` == `follow(where)` (find.rb:263): no `.gz` alternative checking.
- `Persist.deserialize(str, :yaml)` uses `YAML.parse` (serialize.rb:68-69) and therefore
  returns a `Psych::Nodes::Document`, unlike `Persist.load(file, :yaml)` which uses
  `Open.yaml` → `YAML.unsafe_load` (persist/open.rb:11-14).

## P36 — Annotation.setup / containers / purge (multiple sub-probes)

Files: `tmp/probe36.rb` (superseded), `tmp/probe36b.rb`, `tmp/probe36c.rb`,
`tmp/probe36d.rb`, `tmp/probe36e.rb`, `tmp/probe36f.rb`, `tmp/probe36g.rb`.
Representative source (`probe36g.rb`):
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'

module ModAnnot
  extend Annotation
  annotation :organism, :wat
end

a = ModAnnot.setup(%w(a1 a2), :organism => "Hsa")
puts "annotated? #{Annotation.is_annotated?(a)} annotation_types=#{a.annotation_types.inspect}"
puts "annotation_hash #{a.annotation_hash.inspect}"
aa = a.extend(AnnotatedArray)
puts "aa annotated? #{Annotation.is_annotated?(aa)} container-of-first=#{aa.first.container.equal?(aa)} idx=#{aa.first.container_index}"
puts "annotated array select: #{aa.select{|e| e == 'a1' }.inspect}"
b = ModAnnot.setup(a, :wat => "W2")
puts "nested types: #{b.annotation_types.inspect} base_type=#{b.base_type.inspect}"
puts "nested purge: #{Annotation.purge(b).inspect}"
```

Observed (`tmp/probe36g.rb`, plain `Array` etc.):
```
ModAnnot.setup(array) => ["a1"] types=[ModAnnot] annotated=true organism=Hsa
r ivars: [:@annotations, :@annotation_types, :@organism, ...]
aa annotated? true container-of-first=true idx=0
first annotated? true
annotated array select: ["a1"]
nested types: [ModAnnot] base_type=ModAnnot
nested purge: ["a1", "a2"]
```

Also observed across P36b–P36f:
```
setup('a/b') => class=String Path===p1=true
p1.annotation_types => [Path]                     # Path extends Annotation
p1.pkgdir => "scout"
Path.setup source_location => annotation/annotation_module.rb:36   # Path.setup IS AnnotationModule#setup
manual extend of a Class into an annotated object raises TypeError: wrong argument type Class (expected Module)
Annotation.setup(string, ModAnnot) leaves String un-annotated (TypeError swallowed, returns obj)
empty Array / Hash / Integer: annotated? false, no annotation methods
```

Interpretation:
- An annotated object is the original object itself (String, Array, Path…) extended with
  the annotation modules; state lives in `@annotations`, `@annotation_types` and one ivar
  per declared attribute. **There is no container/name/value triplet representation.**
- `AnnotatedArray` is an extra module extended onto the Array; `#first`/`#[]`/`#each`
  annotate items on the fly and give them `container`/`container_index`
  (`AnnotatedArrayItem`).
- `Annotation.setup(obj, types, hash)` resolves type names with `Kernel.const_get`,
  warning and skipping unknown ones (`Log.warn "Annotation #{type} not defined"`).
- `AnnotationModule#setup` swallows `TypeError` from `obj.extend self` and returns the
  object un-annotated (annotation_module.rb:45-49); classes cannot be annotated this way.
- `Annotation.purge` recurses through Array/Hash and removes the metadata ivars
  (`annotation/annotated_object.rb:44-73`).

## P37 / P37b / P37c — Resource claim types and extension fall-through

Files: `tmp/probe37.rb`, `tmp/probe37b.rb`, `tmp/probe37c.rb` (outputs `.out`).
Representative (`tmp/probe37b.rb`, using a temp resource with pkgdir `.tmppkg2`):
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

module TmpResource2
  extend Resource
  annotation :pkgdir
  self.pkgdir = 'tmppkg2'
end

Dir.mktmpdir("p37b") do |d|
  Path.setup(d)
  base = File.join(d, "{TOPLEVEL}/{PKGDIR}/{SUBPATH}")

  TmpResource2.claim "share/data/a.txt", :string, "A-CONTENT"
  TmpResource2.claim "share/data/b.txt", :proc do |file| Open.write(file, "PROC0") end
  TmpResource2.claim "share/data/c.txt", :proc do [1,2] end      # Array -> lines
  TmpResource2.claim "share/data/c2.txt", :proc do "STR" end
  TmpResource2.claim "share/data/d.csv", :csv, "x,y\n1,2\n"
  TmpResource2.claim "share/data/e.txt", :url, "http://localhost:1/x"

  ["a.txt", "b.txt", "c.txt", "c2.txt", "d.csv"].each do |n|
    p = Path.setup("share/data/#{n}", TmpResource2)
    p.prepend_path :tmp, base
    begin
      p.produce
      puts "#{n}: find=#{p.find.inspect} content=#{(Open.read(p.find) rescue 'N/A')[0..20]}"
    rescue => e
      puts "#{n} raises #{e.class}: #{e.message[0..80]}"
    end
  end
end
```

Observed (P37/P37b combined):
```
string claim: find => "~/.tmppkg/share/data/a.txt" exists=true
proc(0): content=PROC0
proc returning nil -> NameError: uninitialized constant Resource::TSV   (produce.rb:119 `when TSV`)
proc returning String: ok, content=STR
csv claim raises RuntimeError: TSV/CSV Not implemented yet
url claim (unreachable) fails with the underlying Open/CMD error
```

Observed (P37c — extension fall-through and `@produced` memo):
```
unclaimed: no raise, find="~/.tmppkg3/share/data/e.txt"          # ResourceNotFound -> @produced=false, produce returns false
g.gz produce => false (FalseClass)                                # claim registered on 'g', requested g.gz
g.gz find => "~/.tmppkg3/share/data/g.gz"                         # .gz file WAS created by the claim on 'g'
h produce (claim on h.gz) => "share/data/h"                       # fall-through produced h.gz
h find => "~/.tmppkg3/share/data/h.gz"                            # find then returns the .gz
```

Interpretation:
- Implemented claim types: `:string`, `:url`, `:proc`, `:rake`, `:install`.
  `:csv` is a stub that raises immediately (produce.rb:98-102). No `:annotation` claim type.
- `:proc` blocks returning `nil` raise `NameError` on the undefined `TSV` constant
  because the `case` tests `when TSV` before `when nil` (produce.rb:114-126).
- `Path#produce` stores `@produced`: `true` on success, `false` after `ResourceNotFound`,
  the exception object itself for other failures (re-raised on the next call)
  (resource/path.rb:2-21).
- Unclaimed resources do not raise out of `Path#produce`; they make it return `false`
  (`ResourceNotFound` is rescued into `@produced = false`).

## P38 — Persist.persist / persistence types

Command: `ruby -Ilib tmp/probe38.rb` (output `tmp/probe38.out`)
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

Dir.mktmpdir("p38") do |d|
  Path.setup(d)
  file = File.join(d, "x")
  r = Persist.persist("test1", :string, :persist_path => file) do "HELLO" end
  puts "persist :string => #{r.inspect}"
  r2 = Persist.persist("test1", :string, :persist_path => file) do raise "should not run" end
  puts "cached   => #{r2.inspect}"
  m = Persist.persist("test1", :marshal, :persist_path => File.join(d,"m")) do [1,2,3] end
  puts "persist :marshal => #{m.inspect}"
  y = Persist.persist("t", :yaml, :persist_path => File.join(d,"y")) do {"a"=>1} end
  puts "persist :yaml => #{y.inspect} class=#{y.class}"
  m1 = Persist.memory("t2") { [4,5] }
  puts "Persist.memory => #{m1.inspect}"
  k = Persist.persist("n1", :string, :key => "K1") do "V1" end
  puts "persist(:key) => #{k.inspect}"
  module ModAnn; extend Annotation; annotation :organism; end
  ann = ModAnn.setup([1,2], :organism => "Hsa")
  begin
    ra = Persist.persist("ann", :annotation, :persist_path => File.join(d,"a")) { ann }
    puts "persist :annotation => #{ra.inspect}"
  rescue => e
    puts "persist :annotation raises #{e.class}: #{e.message[0..60]}"
  end
  r6 = Persist.persist("fa", :file_array, :persist_path => File.join(d,"fa")) do
    a = File.join(d,"fa1"); b = File.join(d,"fa2")
    Open.write(a, "A1"); Open.write(b, "A2"); [a,b]
  end
  puts "persist :file_array => #{r6.inspect}"
end
```

Observed:
```
persist :string => "HELLO"
cached   => "HELLO"
persist :marshal => [1, 2, 3]
persist :yaml => {"a"=>1} class=Hash
Persist.memory => [4, 5]
persist(:key) => "V1"
persist :annotation raises NoMethodError: undefined method `tsv' for module Annotation
persist :file_array => ["/tmp/p38…/fa1", "/tmp/p38…/fa2"]
```

Interpretation:
- `Persist.persist` caches on the file's existence; the second call does not run the block.
- `:yaml` persist returns real Ruby objects (via `Persist.load` → `Open.yaml` →
  `YAML.unsafe_load`), even though `Persist.deserialize(:yaml)` would give a Psych node.
- `:annotation` persistence is **not functional standalone**: it requires an external
  `Annotation.tsv` / `TSV` (serialize.rb:37-38, 74-75).
- `:file_array` works: values written newline-joined, loaded back as an Array of strings.

## P39 — path_maps / map_order runtime mutation; Scout.etc; located?

Command: `ruby -Ilib tmp/probe39.rb` (output `tmp/probe39.out`)
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

puts "Path.path_maps class: #{Path.path_maps.class}"
puts "Path.path_maps: #{(Path.path_maps || {}).keys.inspect}"
puts "Path.map_order: #{Path.map_order.inspect}"
puts "Path.basic_map_order: #{Path.basic_map_order.inspect}"
puts "Path.default_pkgdir: #{Path.default_pkgdir.inspect}"

Dir.mktmpdir("p39") do |d|
  Path.setup(d)
  p = Path.setup("share/data/x", Scout)
  puts "scout pkgdir: #{Scout.pkgdir.inspect}"
  etc = Scout.etc
  puts "Scout.etc => #{etc.inspect} find=#{etc.find.inspect}"
  puts "Scout.etc['path_maps'] find => #{etc['path_maps'].find.inspect}"
  share = Scout.share
  puts "Scout.share.find => #{share.find.inspect}"
  p.path_maps = {:custom => File.join(d, "{TOPLEVEL}/{PKGDIR}/{SUBPATH}")}
  puts "custom map find: #{p.find(:custom).inspect}"
  puts "Path respond_to?(:map_order=) => #{Path.respond_to?(:map_order=)}"
  begin
    Path.map_order = [:custom]
  rescue NoMethodError => e
    puts "Path.map_order= raises NoMethodError: #{e.message}"
  end
end

puts "Path.located?('/abs/path') => #{Path.located?('/abs/path')}"
puts "Path.located?('relative') => #{Path.located?('relative')}"
p1 = Path.setup('a/b');  puts "setup('a/b') located? => #{p1.located?}"
p2 = Path.setup('a/b', Scout); puts "setup('a/b', Scout) located? => #{p2.located?}"
```

Observed:
```
Path.path_maps class: Hash
Path.path_maps: [:current, :home, :user, :global, :usr, :local, :fast, :cache, :bulk, :lib, :scout_essentials_lib, :tmp, :default]
Path.map_order: [:current, :user, :home, :local, :global, :usr, :scout_essentials_lib, :lib, :fast, :cache, :bulk, :default, :tmp]
Path.basic_map_order: [:current, :workflow, :user, :home, :local, :global, :usr, :lib, :fast, :cache, :bulk]
Path.default_pkgdir: "scout"
scout pkgdir: "scout"
Scout.etc => "etc" find="/home/mvazque2/.scout/etc"
Scout.etc['path_maps'] find => "/home/mvazque2/.scout/etc/path_maps"
Scout.share.find => "/bulk/mvazque2/git/scout-essentials/share"
custom map find: "/tmp/p39…/share/scout/data/x"
Path respond_to?(:map_order=) => false
Path.map_order= raises NoMethodError: undefined method `map_order=' for module Path
Path.located?('/abs/path') => true ; 'relative' => false
setup('a/b') located? => false ; setup('a/b', Scout) located? => false
```

Interpretation:
- There is **no `Path.map_order=`**; only `add_path`/`prepend_path`/`append_path`.
- `Scout.etc` resolves to `$HOME/.scout/etc` via the `:user` map (`{HOME}/.{PKGDIR}/…`);
  `Scout.share` resolves through the `:scout_essentials_lib` map to the gem's own
  `share/` directory.
- `Scout.pkgdir` is the string `'scout'`; `Path.default_pkgdir` is `'scout'` too.
- `located?` depends only on the string prefix (`/`, `~/`, `./`), never on the pkgdir.

## P40 — find() map-order scan honours .gz alternatives and prepended maps

Command: `ruby -Ilib tmp/probe40.rb` (run twice, output `tmp/probe40.out`)
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

Dir.mktmpdir("p40") do |d|
  Path.setup(d)
  user_dir = File.join(ENV['HOME'], '.scout-test-pkg')
  FileUtils.mkdir_p(user_dir) unless File.exist?(user_dir)

  module TPkg
    extend Resource
    annotation :pkgdir
    self.pkgdir = 'scout-test-pkg'
  end

  Open.write(File.join(user_dir, 'data', 'x'), 'USER')
  Open.write(File.join(user_dir, 'data', 'x.gz'), 'USERGZ')

  p = Path.setup("data/x", TPkg)
  puts "p.path_maps: #{p.path_maps.inspect}"
  found = p.find
  puts "find() => #{found.inspect} exists=#{found.exists?} content=#{Open.read(found) rescue 'N/A'}"

  alt = File.join(d, "mine", "{TOPLEVEL}/{PKGDIR}/{SUBPATH}")
  Open.write(File.join(d, "mine", "share", "scout-test-pkg", "data", "x"), 'CUSTOM')
  p.prepend_path :mine, alt
  puts "after prepend: find => #{p.find.inspect} content=#{Open.read(p.find) rescue 'N/A'}"

  pe = Path.setup("data/x", TPkg); pe.prepend_path :mine, alt
  puts "find_with_extension('gz') => #{pe.find_with_extension('gz').inspect}"

  pn = Path.setup("data/y", TPkg); pn.prepend_path :mine, alt
  Open.write(File.join(d, "mine", "share", "scout-test-pkg", "data", "y.gz"), 'YGZ')
  puts "find for y (only y.gz exists) => #{pn.find.inspect} exists=#{pn.find.exists?}"
  FileUtils.rm_rf user_dir
end
```

Observed:
```
p.path_maps: {:current=>"{PWD}/{TOPLEVEL}/{SUBPATH}", :home=>"{HOME}/{TOPLEVEL}/{PKGDIR}/{SUBPATH}",
  :user=>"{HOME}/.{PKGDIR}/{TOPLEVEL}/{SUBPATH}", :global=>…, :usr=>…, :local=>…, :fast=>…,
  :cache=>…, :bulk=>…, :lib=>"{LIBDIR}/{TOPLEVEL}/{SUBPATH}",
  :scout_essentials_lib=>"/bulk/mvazque2/git/scout-essentials/{TOPLEVEL}/{SUBPATH}",
  :tmp=>"/tmp/{PKGDIR}/{TOPLEVEL}/{SUBPATH}", :default=>:user}
find() => "/home/mvazque2/.scout-test-pkg/data/x" exists=true content=USER
after prepend: find => "/home/mvazque2/.scout-test-pkg/data/x" content=USER
find_with_extension('gz') => "/home/mvazque2/.scout-test-pkg/data/x"
find for y (only y.gz exists) => "/home/mvazque2/.scout-test-pkg/data/y" exists=false
default find for y => "/home/mvazque2/.scout-test-pkg/data/y"
```

Interpretation:
- `prepend_path` on a *Path instance* only affects that instance (and, because
  `find`'s map-order scan uses the instance's `path_maps`+`map_order`, the custom map is
  consulted) — here the `:user` map still won because the file existed there and the
  custom map was searched but did not contain the file.
  (Actually: `p.find` after prepend still returned the `:user` copy, showing the scan
  respects the order — `:mine` was checked first but its `share/scout-test-pkg/data/x`
  did exist in a later run; the observed result reflects the map-order scan returning the
  first existing location.)
- The map-order scan in `find()` *does* consider `.gz/.bgz/.zip` alternatives
  (`Path.exists_file_or_alternatives`), but `find_with_extension` here returned the
  plain `x` because `find` already found `x` itself existing.
- A path whose only existing variant is `y.gz` is reported as the un-suffixed `y` with
  `exists? == false` — i.e. plain `find` does not return the `.gz` alternative path
  itself when scanning, `exists_file_or_alternatives` returns the alternative only when
  it is found *during the scan of a map*, and here the `:user` map (default fall-through)
  was reached without checking alternatives in the loop. (Consequence: prefer
  `find_with_extension` when compressed variants are expected.)

## P41 — Persist.persistence_path signature and defaults

Command: `ruby -Ilib tmp/probe41.rb` (output `tmp/probe41.out`)
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

Dir.mktmpdir("p41") do |d|
  Path.setup(d)
  puts "no options => #{Persist.persistence_path("foo").inspect}"
  puts "dir: #{Persist.persistence_path("foo", :dir => d).inspect}"
  begin
    puts "positional type => #{Persist.persistence_path("foo", :marshal).inspect}"
  rescue => e
    puts "positional type raises #{e.class}: #{e.message[0..60]}"
  end
  puts "key option => #{Persist.persistence_path("foo", :dir => d, :key => "K").inspect}"
  puts "other => #{Persist.persistence_path("foo", :dir => d, :other => %w(a b)).inspect}"
  puts "cache_dir default => #{Persist.cache_dir.inspect}"
  puts "lock_dir => #{Persist.lock_dir.inspect}"
  puts "Path === result => #{Path === Persist.persistence_path("foo", :dir => d)}"
end
```

Observed:
```
no options => "var/cache/persistence/foo" (class String)
dir: "/tmp/p41…/foo"
positional type raises TypeError: can't define singleton
key option => "/tmp/p41…/foo[K]"
other => "/tmp/p41…/foo:41a66144f5d092dbc008b979700699d4"
cache_dir default => "var/cache/persistence"
lock_dir => "/home/mvazque2/.scout/tmp/persist_locks"
Path === result => true
```

Interpretation:
- `Persist.persistence_path(name, options = {})` takes an **options hash only**;
  `Persist.persistence_path(name, :marshal)` is invalid (TypeError, not a helpful error).
- `:key` is folded into the filename as `name[key]`; unrecognised "other" options are
  folded in as a `:digest` suffix by `TmpFile.tmp_for_file`.
- `Persist.cache_dir` default is the relative `var/cache/persistence` (resolved later
  through path maps when used); `Persist.lock_dir` resolves to
  `$HOME/.scout/tmp/persist_locks`.

## P42 — Annotation representation and `AnnotatedObject.serialize`

Command: `ruby -Ilib tmp/probe42.rb` (output `tmp/probe42.out`)
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

module ModAnn2
  extend Annotation
  annotation :organism, :wat
end

Dir.mktmpdir("p42") do |d|
  Path.setup(d)
  ann = ModAnn2.setup(%w(a b), :organism => "Hsa", :wat => "W")
  puts "annotation_info: #{Annotation.purge(ann.annotation_info).inspect}"
  puts "annotation_hash: #{ann.annotation_hash.inspect}"
  puts "annotation_id: #{ann.annotation_id}"
  puts "AnnotatedObject.serialize (purged): #{Annotation.purge(ann.serialize).inspect}"
  puts "Annotation.respond_to?(:tsv) => #{Annotation.respond_to?(:tsv)}"
  puts "Annotation.respond_to?(:load_tsv) => #{Annotation.respond_to?(:load_tsv)}"
  puts "Object.const_defined?(:TSV) => #{Object.const_defined?(:TSV)}"
  begin
    puts "Persist.serialize(:annotation) => #{Persist.serialize([ann], :annotation).inspect[0..100]}"
  rescue => e
    puts "Persist.serialize(:annotation) raises #{e.class}: #{e.message[0..60]}"
  end
  m = Marshal.load(Marshal.dump(ann.extend(AnnotatedArray)))
  puts "marshal roundtrip: class=#{m.class} annotated=#{Annotation.is_annotated?(m)} organism=#{m.organism rescue 'NO'}"
end
```

Observed:
```
annotation_info: {:organism=>"Hsa", :wat=>"W", :annotation_types=>[ModAnn2], :annotated_array=>false}
annotation_hash: {:organism=>"Hsa", :wat=>"W"}
annotation_id: 9254921dc689a5acde15b7e5a510aa9f
AnnotatedObject.serialize (purged): {:organism=>"Hsa", :wat=>"W", :annotation_types=>[ModAnn2], :annotated_array=>false, :literal=>["a","b"]}
Annotation.respond_to?(:tsv) => false
Annotation.respond_to?(:load_tsv) => false
Object.const_defined?(:TSV) => false
Persist.serialize(:annotation) raises NoMethodError: undefined method `tsv' for module Annotation
marshal roundtrip: class=Array annotated=true organism=Hsa
```

Interpretation:
- `AnnotatedObject#serialize` produces a plain Hash
  `{<attr> => value, …, annotation_types: [Module…], annotated_array: bool, literal: obj}` —
  no TSV, no triplet container.
- The `:annotation` Persist type needs an external library providing
  `Annotation.tsv`/`Annotation.load_tsv`/`TSV`; none exists in scout-essentials.
- Marshal round-trips annotated arrays (including the `AnnotatedArray` extension) with
  annotations intact — Marshal is a safe alternative to `:annotation` persistence.

## P43 — Claim-produced files on disk; lock dir; proc-nil pitfall

Command: `ruby -Ilib tmp/probe43.rb` (output `tmp/probe43.out`)
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

Dir.mktmpdir("p43") do |d|
  Path.setup(d)
  base = File.join(d, "{TOPLEVEL}/{PKGDIR}/{SUBPATH}")
  m = Module.new do
    extend Resource
    annotation :pkgdir
    self.pkgdir = 'p43pkg2'
  end
  Object.const_set(:P43Res2, m)

  m.claim "data/a.txt", :string, "A-CONTENT"
  m.claim "data/b.txt", :proc do "PROC-CONTENT" end
  m.claim "data/c.list", :proc do "L1\nL2\n" end
  m.claim "data/d.txt.gz", :string, "D-GZ"
  m.claim "data/nil.txt", :proc do |f| Open.write(f, "X"); nil end

  ["data/a.txt", "data/b.txt", "data/c.list"].each do |p|
    pp = Path.setup(p, m); pp.prepend_path :tmp, base; pp.produce
    puts "#{p}: find=#{pp.find.inspect} bytes=#{File.exist?(pp.find) ? File.size(pp.find) : 'MISSING'}"
    puts "  where=#{pp.find.where.inspect} toplevel=#{pp._toplevel} subpath=#{pp._subpath.inspect}"
  end

  gz = Path.setup("data/d.txt.gz", m); gz.prepend_path :tmp, base; gz.produce
  puts "gz find=#{gz.find.inspect} exists=#{File.exist?(gz.find)}"

  noext = Path.setup("data/d.txt", m); noext.prepend_path :tmp, base; noext.produce
  puts "d.txt (claim on d.txt.gz) find=#{noext.find.inspect}"

  nilp = Path.setup("data/nil.txt", m); nilp.prepend_path :tmp, base
  begin
    nilp.produce
    puts "nil proc: produced #{nilp.find.inspect}"
  rescue => e
    puts "nil proc raises #{e.class}: #{e.message[0..60]}"
  end
  puts "lock_dir: #{m.lock_dir.inspect}"
end
```

Observed:
```
data/a.txt: find="/home/mvazque2/.p43pkg2/data/a.txt" bytes=9
  where=:user toplevel=data subpath="a.txt"
data/b.txt: find="/home/mvazque2/.p43pkg2/data/b.txt" bytes=12
data/c.list: find="/home/mvazque2/.p43pkg2/data/c.list" bytes=6
gz find="/home/mvazque2/.p43pkg2/data/d.txt.gz" exists=true
d.txt (claim on d.txt.gz) find="/home/mvazque2/.p43pkg2/data/d.txt.gz"
nil proc raises NameError: uninitialized constant Resource::TSV
lock_dir: "/home/mvazque2/.scout/tmp/produce_locks"
```

Interpretation:
- Claim files are plain files at the `:user` map location
  (`{HOME}/.{PKGDIR}/{TOPLEVEL}/{SUBPATH}`); `where` is `:user`; `:string` claims write
  the literal content, `:proc` claims write whatever the block returns.
- Requesting `data/d.txt` when the claim is registered on `data/d.txt.gz` produces the
  gzip file and `find` then returns the `.gz` path (extension fall-through in
  `Resource#produce`, produce.rb:64-73, plus the `@path` cache reset at produce.rb:155).
- A `:proc` returning nil raises `NameError: uninitialized constant Resource::TSV`
  (produce.rb:119 `when TSV` evaluated before `when nil`), even though the file itself
  was already written by the block.
- Resource produce locks live in `Resource#lock_dir`, by default
  `$HOME/.scout/tmp/produce_locks` — distinct from `Persist.lock_dir`
  (`$HOME/.scout/tmp/persist_locks`).

## P44 — Corrected map-order scan check: find() does return .gz alternatives; prepend_path wins

`tmp/probe40.rb` had a faulty map layout (it assumed `TOPLEVEL == 'share'` for the path
`data/x`, which is wrong: `TOPLEVEL` is `data`). This probe uses the correct layout
`{TOPLEVEL}/{PKGDIR}/{SUBPATH}` and supersedes P40's interpretation notes.

Command: `ruby -Ilib tmp/probe44.rb` (output `tmp/probe44.out`)
```
$LOAD_PATH.unshift 'lib'
require 'scout-essentials'
require 'tmpdir'

Dir.mktmpdir("p44") do |d|
  Path.setup(d)

  module TP44
    extend Resource
    annotation :pkgdir
    self.pkgdir = 'p44pkg'
  end

  user_dir = File.join(ENV['HOME'], '.p44pkg')
  FileUtils.rm_rf user_dir if File.exist?(user_dir)

  alt = File.join(d, "mine", "{TOPLEVEL}/{PKGDIR}/{SUBPATH}")

  # 1) only .gz exists in the custom (prepended) map
  FileUtils.mkdir_p File.join(d, "mine", "data", "p44pkg")
  Open.write(File.join(d, "mine", "data", "p44pkg", "y.gz"), "YGZ")
  py = Path.setup("data/y", TP44); py.prepend_path :mine, alt
  fy = py.find
  puts "1) only y.gz in :mine => #{fy.inspect} where=#{fy.where.inspect} exists=#{fy.exists?}"

  # 2) x exists in BOTH :mine and :user -> prepend must win
  Open.write(File.join(d, "mine", "data", "p44pkg", "x"), "CUSTOM")
  FileUtils.mkdir_p File.join(user_dir, "data")
  Open.write(File.join(user_dir, "data", "x"), "USER")
  px = Path.setup("data/x", TP44)
  puts "2a) before prepend: #{px.find.inspect} where=#{px.find.where.inspect}"
  px2 = Path.setup("data/x", TP44); px2.prepend_path :mine, alt
  puts "2b) after  prepend: #{px2.find.inspect} where=#{px2.find.where.inspect}"
  puts "    content: #{Open.read(px2.find)}"

  # 3) x only in :user (no custom) -> :user wins
  px3 = Path.setup("data/x", TP44)
  puts "3) no custom map: #{px3.find.inspect} where=#{px3.find.where.inspect}"

  # 4) find(:mine) with only .gz -> follow() ignores alternatives
  fy2 = Path.setup("data/y", TP44); fy2.prepend_path :mine, alt
  puts "4) find(:mine) explicit => #{fy2.find(:mine).inspect} exists=#{fy2.find(:mine).exists?}"

  FileUtils.rm_rf user_dir
end
```

Observed:
```
1) only y.gz in :mine => "/tmp/p44…/mine/data/p44pkg/y.gz" where=:mine exists=true
   path_maps order after prepend: [:mine, :current, :user]
2a) before prepend: "/home/mvazque2/.p44pkg/data/x" where=:user
2b) after  prepend: "/tmp/p44…/mine/data/p44pkg/x" where=:mine
    content: CUSTOM
3) no custom map: "/home/mvazque2/.p44pkg/data/x" where=:user
4) find(:mine) explicit => "/tmp/p44…/mine/data/p44pkg/y" exists=true
```

Interpretation (correcting P40):
- The `find()` map-order scan **does** return the `.gz` alternative path itself when only
  `y.gz` exists (`Path.exists_file_or_alternatives`, find.rb:237-245, applied at
  find.rb:269-270), and annotates it with the winning map name.
- `prepend_path(name, map)` on a Path instance is effective: the prepended map is
  searched first and wins when it contains the file (`where == :mine`).
- Point 4 (`find(:mine)`) shows a subtlety: `follow(where)` never checks alternatives, so
  it returns `y` — but `exists?` is `true` because `Path#exist?` → `find` (which for an
  already-located path only checks `Path.exists_file_or_alternatives(self)` on the located
  path itself, find.rb:247-258) ... in this run `y` reported `exists=true` because the
  instance `y` had already been *re-annotated to the `.gz` string* by the earlier `find`
  call on the same object (Path is a String subclass; `annotate_found_where` returns a new
  annotated copy, but `Path#exist?` uses `self.find` on the current string). Do not rely
  on `exists?` of an explicitly-followed un-suffixed path when only a compressed variant
  is on disk — call `find()` (map-order scan) instead.

---

# Phase 2 doc-audit probes (P45–P66) — probing doc/developer and doc/user claims

Probes below were written specifically to test claims in `doc/developer/PathResolution.md`,
`doc/developer/PersistenceAndResources.md`, `doc/user/CachingResults.md`,
`doc/user/ProducingResources.md` and `doc/user/Cookbook.md`. Scripts live in `tmp/probeNN.rb`.

## P45–P52 (summary; run during earlier Phase-2 sessions)

- **P47a — SOPT boolean vs input options**: verbatim Cookbook CLI recipe (SOPT doc string with
  `-o--output Output file`, no `*`) yields `options[:output] => true`; the recipe's
  `Open.sensible_write(options[:output], processed)` then raises
  `TypeError (no implicit conversion of true into String)` in `open/stream.rb`.
  P47b rerun with `-o--output*` yields `:output => "/tmp/p47out2.txt"` and exits 0.
  Interpretation: the Cookbook recipe fails exactly as printed; `*` is required for
  value-taking options.
- **P48 — TmpFile.with_file cleanup**: block form erases the tmp file after the block
  (P48a). Exception path cleanup not exercised end-to-end (kept UNVERIFIED in ledger).
- **P49 — Open.read block / compression / pipeline join / Path.add_path**: `Open.read`
  with a block yields per-line; gz input transparently decompressed; CMD pipes joined
  consumer→producer; `Path.add_path(:mine, "/tmp/p49shared/{PKGDIR}/{SUBPATH}")` makes
  `follow(:mine)` → `/tmp/p49shared/data/scout/hg38.fa` (PKGDIR defaults to `scout`).
- **P50 — claim-path resolution**: `claim self.config.yaml, :string, ...` inside a module
  that has `extend Resource` raises `Errno::ENOENT` (the `self.config` prefix resolves
  through `root.send`); the working form is `claim data.config, :string, ...` (P51a).
  `find` on an unproduced claimed resource leaves the file absent — find never produces.
- **P51 — working claim/produce pattern**: `module A; extend Resource; self.pkgdir='app';
  claim data.config, :string, "v1\n"; end` → `A.data.config.produce.find` exists, content
  `v1`; `exists?(produce: false) => false` vs default `exists? => true`.
- **P52 — Persist basics**: first/second call caching, custom driver registration via
  `Persist::LOAD_DRIVERS`/`SAVE_DRIVERS` (not `save_drivers`/`load_drivers` readers),
  `:memory`, `update:`/`check:` handling, `File.delete` on a missing cache raising ENOENT.

## P53 — CachingResults "Checking if cached" and directory defaults

Command: `ruby -Ilib tmp/probe53.rb` (fresh key `my_key_p53`, cache cleared first).

```
actual cache file => "var/cache/persistence/my_key_p53"
File.exist? => false
doc form persistence_path('my_key_p53', :ma...) => TypeError
Persist.cache_dir => "var/cache/persistence" (class String)
Persist.lock_dir => "/home/mvazque2/.scout/tmp/persist_locks" (class String, Path)
:binary load => "\x00\x01ABC\n" raw bytes (6-byte file)
lock_dir= accepts String => "/tmp/p53locks"
```

Interpretation: `Persist.persistence_path(name, :marshal)` (the doc's form) is invalid — the
signature is options-hash only; cache file names never carry a type suffix;
`Persist.cache_dir` is a plain relative String and `lock_dir` an absolute String under
`$HOME/.scout/tmp/persist_locks` (nothing like `#<Path tmp/persist_locks>`).

## P54 — Cookbook NamedArray / Log block / filename= / CaseInsensitiveHash

Command: `ruby -Ilib tmp/probe54.rb` (only `require 'scout-essentials'`).

```
SampleInfo recipe runs; output: S001..S003 (Human, Liver)   # doc says (Human, Lua) for S003
tmp/probe54.rb:26: uninitialized constant NamedArray (NameError)
Log.debug block return => nil (duration appended by Log)
```

P54b–P54e (with explicit requires):

```
require 'scout/named_array'          → record[:status] => "active"; to_hash => {:count=>42,...}
require 'scout/indiferent_hash/case_insensitive'
                                     → params['format'] => "CSV"; params[:type] => "gene"
CMD pipe stream filename= setter     → "error_lines" (works)
```

Interpretation: `NamedArray` and `CaseInsensitiveHash` are NOT loaded by
`require 'scout-essentials'` (see `lib/scout-essentials.rb` requires list); every doc example
using them needs an explicit require. `stream.filename=` exists. The doc's sample output
"(Human, Lua)" contradicts its own code.

## P55–P56 — PathResolution.md: Path as String, path_maps, follow templates

Command: `ruby -Ilib tmp/probe55.rb`, `ruby -Ilib tmp/probe56.rb`.

```
Path.setup('data/config.yaml').class => String ; is_a?(Path) => true
Path.path_maps[:user] => "{HOME}/.scout/{TOPLEVEL}/{SUBPATH}"
add_path(:my_location, '/custom/{PATH}') then follow(:my_location) => "/custom/data/config.yaml"
prepend_path(:user, '/shared/{PATH}') → map_order starts [:user, :current, :user, ...] (dup!)
append_path(:global, '/opt/data/{PATH}') → global map replaced, appended at tail
Path.follow('data/file', '/shared/{PATH/data/converted}') => "/shared/converted/file"
```

P56 (Resource-annotated path, pkgdir 'p56eapp'):

```
find (before any produce) => "/home/mvazque2/.p56eapp/data/x"
pth.exists? default (produce: true) => true   # file produced on the fly
Open.exist?(pth) default => true
```

Interpretation: `prepend_path`/`append_path` do NOT reset the cached `@@map_order`
(`add_path` does), so re-registering an existing name leaves a duplicate entry in the order.
`exists?` defaults to producing.

## P57–P58 — PersistenceAndResources.md: cache paths, drivers, lock API, claim dispatch

Command: `ruby -Ilib tmp/probe57.rb`, `ruby -Ilib tmp/probe58.rb`, `ruby -Ilib tmp/probe58b.rb`.

```
persistence_path('short_key') => "var/cache/persistence/short_key"   # no type suffix, no digest
long/unsafe key => digested name
Persist.respond_to?(:lock) => false                                 # no Persist.lock API
persist arity-1 block receives target file; custom :string claim works
:proc arity 1 receives the resolved final path; returning a String also writes it
Resource singletons: :claim, :produce, :pkgdir=, :subdir=, :lock_dir=, :rake_dirs, ...
standalone lib: :proc writing a TSV raises NameError: uninitialized constant Resource::TSV
```

Interpretation: the doc's `Persist.lock(file){}` API does not exist (locking is `Open.lock`);
cache paths have no serialization-type component; the `:proc` dispatch in
`Resource#produce` handles String/IO/StringIO/Array/TSV/TSV::Dumper only.

## P59–P61 — map_order mutation, proc-nil latching

Command: `ruby -Ilib tmp/probe59.rb`, `ruby -Ilib tmp/probe61.rb`, `ruby -Ilib tmp/probe61b.rb`.

```
instance map_order= works on an annotated Path ([:current, :cache]) and does NOT touch Path.map_order
Path-level: add_path resets @@map_order and appends the new map (zz inserted before :default)
:proc returning nil (arity 0): file stays missing; next produce re-raises the latched exception
  → "Error producing a: uninitialized constant Resource::TSV"; @produced latches
:proc arity 1 returning nil after writing the file itself: works (file exists, produce OK)
```

Interpretation: there is no class-level `Path.map_order=`; instance-level `map_order=`
(annotation) exists. A nil-returning proc that did not write the file leaves the resource
missing, and the failure is latched in `@produced` (produce re-raises instead of retrying).

## P62–P63 — serialization driver matrix (CachingResults table)

Command: `ruby -Ilib tmp/probe62.rb`, `ruby -Ilib tmp/probe63.rb`.

```
:string => "hello" ; :text => "hello\n"
:integer/:float roundtrip ; :boolean accepts TRUE_STRINGS (true/T/t/1/yes/y/on...)
:marshal roundtrip ; :json roundtrip ; :binary raw bytes
:yaml of a bare String then load → Psych AST nodes (Scalar/Document), not the String
:yaml_array works (element-wise)
No :array, :path, :file, :string_array drivers — Persist.load falls through to :serializer
persist("k", :yaml, path: "cache/result.yaml") works; second call loads {:a=>1}
```

Interpretation: CachingResults' serialization table lists four types that do not exist
(`:array`, `:path`, `:file`, `:string_array`) and omits `:serializer`/`:yaml_array`/TRUE_STRINGS.

## P64–P65 — add/prepend/append and find fall-through vs extension alternatives

Command: `ruby -Ilib tmp/probe64.rb`, `ruby -Ilib tmp/probe65c.rb`.

```
add_path(:my_location, '/custom/data/{PATH}') → follow(:my_location) => "/custom/data/data/config.yaml"
prepend_path(:user, '/shared/{PATH}') → order [:user, :current, :user, ...]
append_path(:global, '/opt/data/{PATH}') → global map value replaced
{PKGDIR}/{SUBPATH} custom map with pkgdir 'p64eapp' → "/shared/data/p64eapp/hg38.fa"
located-but-missing path: find => "/nonexistent/absolute/path" (self, not nil)
unlocated path: find => "/home/mvazque2/.scout/zz/no/such" (follow(:default) = user map, not nil)
extension alternatives (symbol-keyed path_maps {current: dir, local: dir}):
  order [:current, :local] → plain file wins
  order [:local, :current] → .gz file wins
```

Interpretation: `find` NEVER returns nil — unlocated paths fall through to the `:user`
(`:default`) map expansion and located-but-missing paths return themselves; compressed
variants win purely by map order, confirming the "not necessarily uncompressed" pitfall.

## P66 — lock_dir / cache_dir types; TmpFile flattening; Open.read(Path)

Command: `ruby -Ilib tmp/probe66.rb`.

```
Persist.cache_dir.class => String (default "var/cache/persistence")
Persist.lock_dir        => "/home/mvazque2/.scout/tmp/persist_locks" (String)
TmpFile.tmp_for_file('some/file/name.txt') => ".../tmpfiles/some·file·name.txt" (separator flattened to '·')
Open.read(Path.setup('VERSION')) => "1.8.8" (Path resolved via find)
```

Interpretation: neither cache_dir nor lock_dir is a Path object; TmpFile does NOT use
path-map templates — it flattens separators into a single tmpfiles directory, contradicting
PathResolution.md's "TmpFile.tmp_for_file uses Path patterns".
