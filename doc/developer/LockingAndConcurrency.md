# Locking and Concurrency

How the Scout stack serialises access to files: a vendored `Lockfile`
implementation, three distinct lock namespaces, and the process/thread model
the locks are meant to protect.

## The vendored Lockfile

`lib/scout/open/lock/lockfile.rb` is Ara T. Howard's `lockfile` library,
version **2.1.8**, vendored and modified, and guarded so a second load is a
no-op:

```ruby
unless defined?(Lockfile)
  ... (whole class)
end
```

`Open.init_lock` (called when the file is loaded) overrides the library
defaults, so the effective settings here are **not** the upstream ones
:

| setting | library default | effective here |
|---|---|---|
| `max_age` | 3600 | **30** |
| `refresh` | 8 | **2** |
| `suspend` | 16 | **4** |
| `Lockfile.version` | 2.1.8 | 2.1.8 |

So a lock older than 30 s is considered stale and may be stolen, the holder
re-touches (`FileUtils.touch`) the lock file every 2 s, and a waiter between
attempts sleeps 4 s.

## What a lock looks like on disk

Acquiring `<file>` creates `<file>.lock` and a hidden sibling. The payload
written into the lock is four lines :

```text
/tmp/…/data.txt.lock contents:
  host: turbo
  pid: 6
  ppid: 3
  time: 2026-08-22 00:58:55.751779
```

(`dump_lock_id`, `lib/scout/open/lock/lockfile.rb:504-507`: `host`, `pid`,
`ppid`, `time`).

The `.lock` sibling is created by `tmpnam`/`create_tmplock` as a dot-prefixed
temporary file in the same directory and then **hard-linked** to
`<file>.lock`; the temp name embeds the pid, which is how the sweep can
recognise locks left behind by dead processes and remove them. Once the
original temp name is unlinked, `nlink` on the surviving `.lock` is 1.

## `Open.lock` and `LockInterrupted`

```ruby
Open.lock(file, options = {}) { ... }       # block form: unlock after
Open.lock(file, true, options)              # legacy 2nd arg = unlock
Open.lock(file, false, options = {})        # do not unlock afterwards
```

`options[:lock]` accepts a `Lockfile` instance (reuse an existing lock), a
`Path`/`String` (an alternative lock file location), or `false` (no locking
at all, and no unlock). Without a block the lock is acquired and the
`Lockfile` object returned. If another holder releases the lock while we are
waiting, `Open.lock` raises `LockInterrupted` (< `TryAgain`, so it is a
`StandardError`) — callers retry the whole operation rather than proceeding
unlock-guarded.

Unlock failures are caught and logged (`Exception unlocking: <path>`), never
raised over the block's own result.

## The three lock namespaces

Each subsystem locks in its own directory so the names never collide
:

| who | directory | name shape |
|---|---|---|
| `Persist` | `Persist.lock_dir` = `tmp/persist_locks`.find → `$HOME/.scout/tmp/persist_locks` | `<persistence_path>.persist` suffix |
| `Resource#lock_dir` | `$HOME/.scout/tmp/produce_locks` | `TmpFile` digest of the resource path |
| `Open.sensible_write` | `$HOME/.scout/tmp/sensible_write_locks` | digest of the output path |

The three directories, with an example of each lock file name:

```text
Persist.lock_dir                => $HOME/.scout/tmp/persist_locks
persist lock file               => .../persist_locks/<key>.persist
Resource#lock_dir               => $HOME/.scout/tmp/produce_locks
produce lock file               => .../produce_locks/<flattened·produce·path>
sensible_write lock dir         => $HOME/.scout/tmp/sensible_write_locks
```

(The `·flattened·` component is `TmpFile.tmp_for_file` output: each `/`
in the produce path is flattened to `·` so the lock file name stays a
single path component.)

(See [PersistenceAndResources.md](PersistenceAndResources.md) for how
`persist` uses its lock, and [StreamingModel.md](StreamingModel.md) for
`sensible_write`.)

## KeepLocked — streaming persistence

`Persist.persist(..., :persist_type/:type)` can return a stream that must
stay locked while the consumer reads it. Raising `KeepLocked.new(res)` from
inside the persist block leaves the lock held; the caller gets the stream
back:

```ruby
res = Persist.persist("my-key", :text, :persist => false) do
  raise KeepLocked.new("payload")
end
res                       # => "payload"
File.exist?(lock_path)    # => true   (lock still held)
```

`KeepLocked < DontPersist < Exception` — it is deliberately outside
`StandardError` so that generic `rescue =>` blocks do not swallow it.

## The fork/thread model

- **Fork.** `CMD.cmd(:pipe => true)` returns an `IO` whose writer is a forked
  child; `Open.open_pipe` in fork mode reuses the same machinery, and
  `ScoutRake.run` forks per task. Child pids are registered on the
  `ConcurrentStream` (`stream.pids`) and reaped by `abort_pids`/`join`.
- **Threads.** Stream consumers are ordinary Ruby threads, registered with
  `stream.threads`. `ConcurrentStream.join` runs the registered `@callback`
  chain exactly once (`join_callback`) and then joins the threads.
- **Cross-process.** That is what the locks above are for.

## Thread-safety caveats

- `Log::LAST` is a shared top-level `String` — a write from one thread is
  visible to the next with no synchronisation.
- `Scout::Config` holds **no mutex**; concurrent `set`/`get`/`with_config`
  is not atomic. See [Configuration.md](Configuration.md).
- `Persist` likewise has no lock on its class-level state.
- `ConcurrentStream` callbacks fire at `join`, in registration order, once
  each; they are not protected against being added from two threads at once.
- `Open.wait`'s `LAST_TIME` hash (see [RemoteData.md](../user/RemoteData.md))
  is unsynchronised shared state.

If you need real parallel writers on the same key, take the relevant lock
namespace yourself, or serialise at the call site.

## Related pages

- [ErrorHandling.md](ErrorHandling.md) — `LockInterrupted`, `KeepLocked` and
  the other control-flow exceptions.
- [PersistenceAndResources.md](PersistenceAndResources.md) — what the
  persist lock actually guards.
- [StreamingModel.md](StreamingModel.md) — `sensible_write`, forked pipes and
  `ConcurrentStream`.
