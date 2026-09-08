# Lock liveness is PID-namespace-blind

**Status:** Non-normative investigation artifact. May be outdated.

**Origin:** promoted from the Cortex claim
`claims/persist_lock_theft_across_agents.md` (investigation of
2026-09-08, after concurrent agents observed `StolenLockError` storms).

## The mechanism

Every lock liveness check in scout-essentials reduces to
`Process.kill(0, pid)` (`Lockfile#alive?`,
`lib/scout/open/lock/lockfile.rb:379-387`):

```ruby
def alive? pid
  pid = Integer("#{ pid }")
  Process.kill 0, pid       # ESRCH ⇒ dead, anything else ⇒ alive
rescue Errno::ESRCH
  false
end
```

`Process.kill` resolves pids in the **PID namespace of the calling
process**. In the normal case — all processes on one host — a recorded
pid either belongs to a live process (signal permitted/delivered ⇒ alive)
or does not (ESRCH ⇒ dead), and the check is correct.

In a PID namespace (bubblewrap/sandboxed agents, containers) the caller
sees only its own namespace. A lock recorded by a *host* process carries
a pid that simply does not exist in the caller's namespace, so
`Process.kill 0, <host pid>` raises `Errno::ESRCH` and the holder is
reported **dead while it is alive**. Verified from inside a bwrap
sandbox (host pid 3151964 recorded in a live
`var·cache·ask·….persist.lock`): `Process.kill(0, 3151964)` →
`Errno::ESRCH`, while `Process.kill(0, <namespace pid 2>)` succeeds.

Two consumers act on that verdict:

1. **`Lockfile#sweep`** (`lib/scout/open/lock/lockfile.rb:341-376`) runs
   on every `Open.lock` in the directory of the lock target and removes
   `.*lck` temp files whose embedded pid it believes dead. In a
   directory shared across namespaces (e.g. `~/.scout/tmp/persist_locks`)
   a sandboxed caller can therefore delete the lock bookkeeping of live
   host holders.
2. **`scout system clean`** (scout-gear `scout_commands/system/clean`) —
   not in this repository, but it iterates `Scout.lock_info` over the
   same `tmp/persist_locks` directory and unlinks any lock whose pid
   `Misc.pid_alive?` reports dead, with the same namespace blindness.
   The scout-gear implementation additionally has an inverted condition
   in its persists/sensiblewrites sections (unlinks when the pid **is**
   alive), which makes it more aggressive still.

The victim observes this as `Lockfile::StolenLockError` raised by the
refresher thread of every live holder at once (`new_refresher`,
`lib/scout/open/lock/lockfile.rb:414-433`) — matching the reported
"all agents hit simultaneously" signature.

## Inferred rule

> Do not share `Persist.lock_dir` / produce / sensible_write lock
> directories across PID namespaces. Under bwrap or containers, pin
> `HOME` (and the `tmp` path map) per sandbox, so each namespace sweeps
> only its own locks.

A more robust library-side fix would treat `/proc/<pid>` unreadable —
or more generally "pid outside my namespace" — as *alive*, at the cost
of keeping genuinely orphaned locks when the last namespace dies.

## Regression test idea (not implemented)

Holder takes a `Persist` lock; a child in a PID namespace runs the
sweep; the holder must not receive `StolenLockError`.
