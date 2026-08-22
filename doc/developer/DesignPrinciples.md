# Design Principles

The handful of conventions that hold across `lib/scout`. Everything below is
observable in the source of this repo; nothing here is aspirational.

Everything below is backed by `tmp/rewrite_C/probe_11_design.rb`
(probe_11), which reproduces each claim from a clean `require`.

## Composition by annotation

Rather than defining wrapper classes, scout-essentials **annotates ordinary
Ruby objects**. `Path`, `Resource`, `Persist` and `NamedArray` are modules
that are `extend`ed into Strings, Arrays or other modules; the receiver keeps
its class and gains accessors:

```ruby
Path.setup('some/dir/file.txt')     # a String with path machinery
SampleInfo.setup('S003', organism: 'Human')   # a String with metadata
```

`AnnotatedObject`-backed metadata, `annotation_types`, `purge`, and the
`setup`/`annotate` round-trip are documented in
[Annotation System](AnnotationSystem.md).

This is *the* extension mechanism of the gem: when you need to attach data or
behaviour to a value that may arrive from outside your code, you define an
annotation module instead of a wrapper class.

## Modules, not classes

The public namespaces (`Path`, `Open`, `CMD`, `Persist`, `Misc`, `Log`,
`Resource`, `SOPT`, `IndiferentHash`, `TmpFile`, `Annotation`) are modules
whose methods are module-functions or class methods. Subclassing one of them
is not an option — `Persist` is a `Module`, so `class X < Persist` raises
`TypeError: superclass must be an instance of Class` (probe_11). The reuse
pattern is `extend` (`resource/path.rb`, `annotation/annotated_object.rb`).

## Options hashes over positional flags

Public methods take a trailing `options = {}` and read named keys with
defaults, rather than growing positional booleans:

```ruby
Open.sensible_write(path, content, :mode => 'w', :replicates => 3)
Persist.persist(name, :marshal, :check => [...], :update => true) { ... }
CMD.cmd('grep foo', :pipe => true, :in => input)
```

Consequences for callers: options are permissive (unknown keys are ignored),
they are normalised inside helpers (`IndiferentHash.process_options`,
`IndiferentHash.add_defaults`), and they compose when one helper forwards its
options to another. See [Path Resolution](PathResolution.md) and
[Persistence and Resources](PersistenceAndResources.md).

## Exception-borne control flow

Signals are ordinary exception objects derived from `Exception`, **not**
`StandardError` (`lib/scout/exceptions.rb`):

```ruby
class StopInsist  < Exception; end   # misc/insist.rb: stop retrying, re-raise last error
class DontClose    < Exception; end   # open.rb: keep the payload, skip closing
class DontPersist  < Exception; end   # persist.rb: do not delete a partial cache
class KeepLocked   < DontPersist; end # open/lock.rb: leave the lockfile alone
class KeepBar      < Exception; end   # log/progress/util.rb: keep the bar
```

(`lib/scout/exceptions.rb` also defines the *ordinary* half of the ladder —
`ScoutException < StandardError` with `ParameterException`,
`MissingParameterException` and `ResourceNotFound`; `Aborted`,
`ProcessFailed`, `TryAgain`, `ClosedStream` … — those are exactly the ones a
bare `rescue` *does* catch.)

The point is deliberate: a bare `rescue => e` (which rescues
`StandardError`) **does not intercept them** — probe_11 raises each in turn
inside `begin ... rescue => e` and shows the signal escapes the bare
`rescue`. A producer that wants the caller to keep the stream it was handed
raises `DontClose` (carrying the result in `.payload`), and `Open.open`'s
block form rescues it by name (`lib/scout/open.rb:66-67`) to return that
payload without closing; `Persist` likewise checks `DontPersist === e`
before deleting a half-written cache (`lib/scout/persist.rb:130`). Callers
must name the class explicitly.

Practical rules:

- in code that closes streams or removes temp files, `rescue DontClose`,
  `rescue DontPersist`, `rescue KeepLocked` by name;
- never convert a signal into `StandardError` (e.g. `raise e` inside a
  `rescue StandardError`) — you would swallow it for the outer caller;
- aborting a `CMD` pipe surfaces as `Aborted` (a `StandardError`) or as the
  `AbortedStream` **module** that is `extend`ed onto the stream object —
  these are what streaming consumers should rescue
  ([Streaming Model](StreamingModel.md); probe_11 shows
  `AbortedStream` is a Module, not a Class).

## Atomic writes

Anything that produces a file other users may read concurrently goes through
`Open.sensible_write(path, content, options)`:

- content is written to a temporary name generated next to the target
  (`TmpFile.tmp_for_file(path, :dir => Open.sensible_write_dir)`) and guarded
  by its own lockfile,
- the real file appears via `Open.mv` inside `Misc.insist`
  (`stream.rb:137-139`), then is touched,
- on abort or any other exception the temporary is removed and the target is
  removed if it appeared (`stream.rb:148-161`); the original exception is
  re-raised.

`Persist.persist` (`persist.rb:108`), the `Persist.save` drivers
(`persist/serialize.rb:105,119`) and `Resource#produce`
(`resource/produce.rb:97,106`) all funnel through it. See
[Persistence and Resources](PersistenceAndResources.md).

## Release semantics you must not assume

Cleanup is explicit, not automatic. `TmpFile.with_file` removes the temporary
file only when the block ends normally — there is no `ensure` around the
`yield`, so an exception leaves the file behind (probe_11; verified against
`lib/scout/tmpfile.rb:71-73`). Likewise stream closing depends on the signal classes
above, and progress bars rely on `Log::ProgressBar.remove_bar` being called.
When correctness matters, put the cleanup in an `ensure` or use
`Open.consume_stream`.

## Related

- [Architecture](Architecture.md) — module map and attribution of the Scout
  features that live in other repos.
- [Streaming Model](StreamingModel.md) — signal classes in the pipe pipeline.
