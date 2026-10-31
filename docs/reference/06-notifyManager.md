---
id: NotifyManager
title: NotifyManager
---

The `notifyManager` handles scheduling and batching callbacks in Flutter TanStack Query.

Without it, every step of a fetch notifies on its own: a pending state, then a settled state, then
each observer sharing the key. A single `invalidateQueries` over N observers rebuilt N times, in an
order that depended on microtask scheduling. The manager coalesces all of that into one flush.

It exposes the following methods:

- [batch](#notifymanagerbatch)
- [batchCalls](#notifymanagerbatchcalls)
- [schedule](#notifymanagerschedule)
- [setNotifyFunction](#notifymanagersetnotifyfunction)
- [setBatchNotifyFunction](#notifymanagersetbatchnotifyfunction)
- [setScheduler](#notifymanagersetscheduler)
- [reset](#notifymanagerreset)

## `notifyManager.batch`

`batch` holds every notification scheduled inside the passed callback until the outermost batch
ends. It is re-entrant — a nested batch does not flush — and it **returns the value of its
callback**, so an imperative method can hand a `Future` back out of a batch:

```dart
Future<void> invalidateAndRefetch() {
  return notifyManager.batch(() {
    // ... mark queries stale, collect their refetches
    return Future.wait(futures);
  });
}
```

The transaction counter unwinds in a `finally`, so a throwing callback still flushes.

## `notifyManager.batchCalls`

Wraps a callback so every call to it is batched. This is how the hooks subscribe to their observer,
and what keeps one fetch down to one rebuild:

```dart
final unsubscribe = observer.subscribe(
  notifyManager.batchCalls<QueryResult<T>>((result) => state.value = result),
);
```

## `notifyManager.schedule`

Queues a callback when inside a batch, and defers it to the end of the current microtask queue
otherwise. It is never synchronous.

## `notifyManager.setNotifyFunction`

Overrides how a single notification is invoked — useful to wrap notifications in a test scope.

## `notifyManager.setBatchNotifyFunction`

Overrides how a whole flushed queue is invoked.

## `notifyManager.setScheduler`

Overrides *when* scheduled notifications run.

The default is `defaultScheduler`, which uses `scheduleMicrotask`. This is a deliberate divergence
from React Query, which schedules with `setTimeout(cb, 0)`, a macrotask: in Flutter a microtask runs
**before** the next frame, so a query state change is painted in that frame instead of lagging one
behind. Pass `systemTimerZero` to get the JavaScript timing, or a synchronous function to flush
notifications inline in tests:

```dart
notifyManager.setScheduler((callback) => callback());
```

## `notifyManager.reset`

Restores the default scheduler and notify functions. Call it in a test `tearDown`.
