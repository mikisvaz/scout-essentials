# Remote Data

Fetching remote files over HTTP(S)/FTP/SSH, the URL cache that backs
`Open.wget`, and the rsync helpers used to move directories between hosts.
Source: `lib/scout/open/remote.rb`, `lib/scout/open/sync.rb`,
`lib/scout/resource/sync.rb`.

Executed examples run against a throwaway local `python3 -m http.server`
serving real URLs.

For the local side of `Open` see [WorkingWithFiles.md](WorkingWithFiles.md);
for `Resource` itself see [ProducingResources.md](ProducingResources.md).

## Recognising remote paths

```ruby
Open.remote?('http://a')   # => true
Open.remote?('https://a')  # => true
Open.remote?('ssh://a:x')  # => true
Open.remote?('ftp://a')    # => true
Open.remote?('/local')     # => false
Open.ssh?('ssh://a:x')     # => true
Open.ssh?('http://a')      # => false
```

Both are pure regexes (`/^(?:https?|ftp|ssh):\/\//` and `/^ssh:\/\//`). A
path without a scheme is never remote.

## `Open.ssh` — reading over SSH

`Open.ssh('ssh://server:path')` parses server and path from the URI. When
the server is exactly `localhost` it bypasses SSH entirely and calls
`Open.open(file)` on the bare path — handy for tests. Otherwise it returns a
pipe from `CMD.cmd("ssh '<server>' cat '<file>'", :pipe => true, :autojoin
=> true)`, i.e. a `ConcurrentStream`, not a String.

## `Open.wget` and the URL cache

`Open.wget(url, options)` is the main entry point for HTTP/FTP. It has a
**permanent file cache** keyed by a digest of the request, and the default
behaviour is to serve from that cache without touching the network.

### Cache location and key

```ruby
Open.remote_cache_dir            # $HOME/.scout/var/cache/open-remote
Open.remote_cache_dir = dir      # override (e.g. a tmpdir)
Open.cache_file(url, options)    # <cache_dir>/<digest>
```

The digest (`Open.digest_url`) covers the URL, the `--post-data` value and
the **sorted lines** of `--post-file`. Different post-data therefore gets a
different cache entry (three URLs/options => three distinct cache paths).

### No TTL, no expiry

There is no timestamp check and no maximum age. Once a URL is cached, a
later `Open.wget` of the same URL/options returns the cached bytes even if
the server has changed: the file can be edited on
the server three times (`HELLO` → `FIRST` → `SECOND` → `THIRD`) while the
second `Open.wget` still reported the old cached content.

### Forcing a refresh

```ruby
Open.wget(url, :nocache => 'update')  # re-fetch, write cache, read cache
Open.wget(url, :force  => true)       # skip the cache check entirely
Open.remove_from_cache(url, options)  # delete the cache entry
```

**Exactly `'update'`** re-fetches and re-writes the cache, then *reads it
back*: after `Open.wget(url, :nocache => 'update')` the returned file
is the cache file again, not the raw pipe). Any other truthy `nocache`
value takes the other branch and returns the raw wget pipe **without**
touching the cache. `:force` only bypasses the initial `in_cache?` lookup,
so a `:force` fetch without `nocache` still ends by writing and re-opening
the cache.

Other `wget` passthroughs: `--user-agent=` (defaults to `rbbt`),
`:post` → `--post-data=`, `:cookies => file` → `--save-cookies`,
`--load-cookies`, `--keep-session-cookies`, plus any literal wget flag.
`:nice` / `:nice_key` route through `Open.wait` (below). Network errors are
wrapped in `OpenURLError` with the message
`Error reading remote url: <url>. <cause>`.

## `Open.download` and `Open.scp`

`Open.download(url, file)` runs `wget '<url>' -O '<file>'` via
`CMD.cmd_log`; on failure it removes the partial output file and re-raises
the original error: downloading a live URL writes the current
server bytes (no cache involved).

`Open.scp(source_file, target_file, target:, source:)` first creates the
remote parent directory with `ssh <target> mkdir -p ...`, then runs
`scp -r`. Both keyword arguments are optional and only prefix the paths with
`host:` when they are not already prefixed.

## `Open.rsync` and `Open.sync`

`Open.rsync(source, target, options)` shells out to
`rsync -avztHP --copy-unsafe-links --omit-dir-times` with:

- `:excludes` — defaults to `%w(.save .crap .source tmp filecache
  open-remote)`; a String is split on commas unless it already contains
  `--exclude`.
- `:files` — a list of relative filenames written to a temp file and passed
  as `--files-from=`.
- `:hard_link` — adds `--link-dest '<source>'` (local sources only).
- `:test` — adds `-nv` (dry run).
- `:delete` — appends `&& rm -Rf <source>` when no `:files`, or removes the
  listed files and empties their directories afterwards.
- `:source` / `:target` — turn one side into `server:'path'` URIs, creating
  the remote directory with `ssh <server> mkdir -p` when needed.
- `:print => true` — return the command string instead of running it.
- `:other` — a String or Array appended verbatim.

Trailing-slash semantics follow rsync: if either side is a directory (or ends
in `/`), both get a trailing `/`, which copies *contents* rather than the
directory itself. A local-to-local sync of the identical path logs a warning
and returns.

`Open.sync(...)` is a literal alias: `Open.sync` and `Open.rsync` are the
same implementation forwarded with Ruby's `...` (same owner). Use
either name — they are interchangeable.

## `Resource.sync(path, map, options)`

`Resource.sync` copies a `Resource` path into a mapped location:
`resource.identify(path).find(map)` is the target, and each existing file or
globbed match is synced with `Open.sync(source, target, options)`. The
resource is resolved from `:resource`, from the path's `pkgdir` when it is
already a `Path` over a `Resource`, or from `Resource.default_resource`.
`map` defaults to `'user'`. All `Open.rsync` options pass through.

## `Open.wait` — client-side rate limiting

```ruby
Open.wait(lag, key = nil)
```

A tiny rate limiter backed by the module-level `LAST_TIME` hash. If the
last call *for that key* was less than `lag` seconds ago, it sleeps the
remainder. `Open.wget` uses it via `:nice` / `:nice_key`. Two
`Open.wait(0.3, :k)` calls in a row took 0.3 s wall clock.

Note the process-local `LAST_TIME` map is shared mutable state with no
mutex; see [LockingAndConcurrency.md](../developer/LockingAndConcurrency.md).

## Where this is used

- [CachingResults.md](CachingResults.md) — the other caching layers
  (`Persist`) and how they differ from this URL cache.
- [WorkingWithFiles.md](WorkingWithFiles.md) — `Open.open` dispatching to
  `wget`/`ssh` when a path looks remote.
