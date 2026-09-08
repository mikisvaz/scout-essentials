# Error Handling

Everything that can be raised by `scout-essentials`, and the two very
different jobs exceptions do in this codebase: real failures vs.
control-flow signals. Source: `lib/scout/exceptions.rb` (78 lines, whole
file), `lib/scout/cmd.rb:22-31` (`CMD::Timeout`),
`lib/scout/concurrent_stream.rb:2-8` (`AbortedStream` module),
`lib/scout/open/stream.rb` (`sensible_write`).

## The taxonomy

```text
ScoutDeprecated                  parent=StandardError
ScoutException                   parent=StandardError
FieldNotFoundError               parent=StandardError
TryAgain                         parent=StandardError
StopInsist                       parent=Exception        <- NOT StandardError
Aborted                          parent=StandardError
ParameterException               parent=ScoutException
MissingParameterException        parent=ParameterException
ProcessFailed                    parent=StandardError
ConcurrentStreamProcessFailed    parent=ProcessFailed
OpenURLError                     parent=StandardError
DontClose                        parent=Exception        <- NOT StandardError
DontPersist                      parent=Exception        <- NOT StandardError
KeepLocked                       parent=DontPersist      <- NOT StandardError
KeepBar                          parent=Exception        <- NOT StandardError
LockInterrupted                  parent=TryAgain
ClosedStream                     parent=StandardError
ResourceNotFound                 parent=ScoutException
CMD::Timeout                     parent=ProcessFailed
```

Plus one non-class member: `AbortedStream` is a **module**
(`lib/scout/concurrent_stream.rb:2-8`) that gets extended onto a stream;
`AbortedStream#exception` carries the original upstream exception. It is
not in the raise/catch taxonomy at all.

## Two families, and why it matters

Failures derive from `StandardError` and behave normally. Control-flow
signals derive straight from `Exception`, so a bare `rescue =>` (which
means `rescue StandardError`) will **not** see them:

```ruby
raise DontClose.new("payload")
# rescue =>      -> does NOT catch
# rescue Exception -> catches
```

The rescue behaviour follows directly from the superclass — each of
them extends `Exception`, not `StandardError`:

```text
DontClose  caught by 'rescue =>' => NOT caught; needs 'rescue Exception'
KeepLocked caught by 'rescue =>' => NOT caught; needs 'rescue Exception'
KeepBar    caught by 'rescue =>' => NOT caught; needs 'rescue Exception'
DontPersist caught by 'rescue =>' => NOT caught; needs 'rescue Exception'
```

`Aborted` and `TryAgain`/`LockInterrupted` ARE `StandardError`, so they
travel through ordinary `rescue =>` handlers — which is exactly what the
`Aborted` protocol relies on (below).

Each signal has a payload slot, and `StopInsist` carries the inner
exception it wants re-raised (`StopInsist#exception`,
`lib/scout/exceptions.rb:10-15`).

## ProcessFailed family

`ProcessFailed.new(pid, msg)` builds its own message
(`lib/scout/exceptions.rb:22-37`):

```text
ProcessFailed.new(1234,'custom msg').message => "Process 1234 failed - custom msg"
ProcessFailed.new(nil,'custom msg').message   => "Failed to run custom msg"
```

`pid` and `msg` are exposed as accessors.

`ConcurrentStreamProcessFailed < ProcessFailed`
(`lib/scout/exceptions.rb:40-47`) takes `(pid, msg, concurrent_stream)` and
exposes `concurrent_stream`; note the constructor has a real quirk — it
reads `@concurrent_stream` (still `nil`) instead of assigning the argument,
so the accessor always stays `nil`. The message is whatever `msg` was
passed at the raise site (`lib/scout/concurrent_stream.rb:113`); it is
raised from `ConcurrentStream#join_threads` when a thread's value is a
`Process::Status` that did not succeed (unless `no_fail`).

`CMD::Timeout < ProcessFailed` (`lib/scout/cmd.rb:22-31`) adds `command`
and `timeout` readers and composes the message through `super`:

```text
CMD::Timeout message => "Process 12 failed - command 'sleep 3 ' exceeded timeout of 0.1 seconds"
  command => "sleep 3 " timeout => 0.1
```

## The Aborted protocol

`Aborted` means "this stream is dead, stop consuming it". It is a
`StandardError`, so it propagates through normal rescues;
`Open.sensible_write` has a dedicated `rescue Aborted` arm
(`lib/scout/open/stream.rb:150-154`) that:

1. logs `Aborted sensible_write -- <path>`,
2. calls `content.abort` if the content responds to it,
3. **deletes the partial output** (`Open.rm path if File.exist? path`).

For the generic arm (`rescue Exception`, `lib/scout/open/stream.rb:155-163`)
the same cleanup happens, plus one extra move: when the content is an
`AbortedStream` carrying an `exception`, **that original exception is what
gets re-raised**, not the `Exception` raised in this frame:

```ruby
exception = (AbortedStream === content and content.exception) ? content.exception : $!
```

So the caller of `sensible_write` sees the root cause that made the
producer abort, rather than a secondary wrapper (`exists after Aborted
=> false`).

The `ensure` always removes the temp file and unlocks a held
`Lockfile` (`lib/scout/open/stream.rb:165-171`).

## `Misc.insist` and the retry loop

`Misc.insist` (`lib/scout/misc/insist.rb`) retries the block while the
code inside raises `TryAgain`; `StopInsist` and `Aborted` break out.

```ruby
tries = 0
Misc.insist do
  tries += 1
  raise TryAgain unless tries == 3
  :ok
end
# => :ok, after 3 tries

Misc.insist do
  raise StopInsist.new(ArgumentError.new("inner"))
end
# => raises ArgumentError (the inner exception is recovered)

Misc.insist do
  raise Aborted
end
# => raises Aborted, no retry
```

`LockInterrupted < TryAgain` is the bridge between the two worlds: when
`Open.lock` fails to acquire, it raises `LockInterrupted`
(`lib/scout/open/lock.rb:43`), which an outer `Misc.insist` treats as
"try again".

## `canfail` / `no_fail` semantics

- `Persist.persist(..., :canfail => true)` — exceptions from the block are
  caught; the persist file is removed and `nil` is returned
  (`lib/scout/persist.rb:63-100`; `persist canfail => nil`, `file removed: true`).
- `ConcurrentStream` `no_fail: true` — a non-success
  `Process::Status` from a joined thread is logged at low level instead of
  raising `ConcurrentStreamProcessFailed`
  (`lib/scout/concurrent_stream.rb:113`).
- `CMD`'s `no_fail` similarly suppresses both `ProcessFailed` from a thread
  join and exceptions during join.

The distinction matters when composing: a `no_fail` stream that dies
produces no exception at join time, so downstream persistence will
happily write empty output unless the producer itself is aborted.

## Cleanup guarantees, and their real limits

`Open.sensible_write` is the model of a real guarantee: temp file + lock +
`ensure` that removes both. But cleanup is not uniform across the gem:

- **`TmpFile.with_file` leaks the temp file when the block raises** — there
  is no `ensure` around the `yield` (`lib/scout/tmpfile.rb:34-48`); the
  created tmp file is still present after the block raises `RuntimeError`.
  Wrap your own `begin/ensure` around `with_file` if the block can fail.
- `Open.sensible_write` deletes the *target* on failure but only the
  *temp* file, never other files written by a streaming producer.
- `Misc.insist` retries without undoing side effects already produced by
  earlier attempts.

## Related pages

- [StreamingModel.md](StreamingModel.md) — where `Aborted` is raised,
  consumed, and swallowed.
- [LockingAndConcurrency.md](LockingAndConcurrency.md) — `KeepLocked`,
  `LockInterrupted`, and the lock lifecycle.
- [PersistenceAndResources.md](PersistenceAndResources.md) — `DontPersist`,
  `canfail`.
- [LoggingAndProgress.md](../user/LoggingAndProgress.md) — `KeepBar` and
  progress-bar lifecycle.
