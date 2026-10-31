---
id: TimeoutManager
title: TimeoutManager
---

The `timeoutManager` is the single seam through which the library creates timers.

Flutter TanStack Query uses timers for garbage collection (`gcTime`) and retry delays, and will use
them for `staleTime` and `refetchInterval`. Routing them all through one manager means a test can
drive the clock instead of waiting out a real five-minute timer, and an app with thousands of cache
entries can coalesce them.

By default it uses Dart's own `Timer`, through `DefaultTimeoutProvider`.

Its available methods are:

- [`timeoutManager.setTimeoutProvider`](#timeoutmanagersettimeoutprovider)
  - [`TimeoutProvider`](#timeoutprovider)
- `timeoutManager.setTimeout`
- `timeoutManager.clearTimeout`
- `timeoutManager.setInterval`
- `timeoutManager.clearInterval`
- `timeoutManager.reset`

## `timeoutManager.setTimeoutProvider`

Sets a custom implementation of the timer functions, called a `TimeoutProvider`.

```dart
timeoutManager.setTimeoutProvider(MyProvider());
addTearDown(timeoutManager.reset);
```

Unlike the JavaScript version, timers already handed out keep their own `cancel()`, so switching
provider cannot cancel an unrelated timer.

### `TimeoutProvider`

```dart
abstract class TimeoutProvider {
  Timer setTimeout(TimeoutCallback callback, int delay);
  void clearTimeout(Timer? timeoutId);
  Timer setInterval(TimeoutCallback callback, int delay);
  void clearInterval(Timer? intervalId);
}
```

`delay` is in milliseconds. A `Timer` *is* the timer id — Dart timers carry their own `cancel()` —
so `clearTimeout` and `clearInterval` exist to mirror the JavaScript surface and to let a custom
provider track what it handed out.

A provider that records the timers it was asked for, and lets the test fire them, is enough to test
anything time-based:

```dart
class RecordingTimeoutProvider implements TimeoutProvider {
  final List<int> timeouts = [];
  final List<void Function()> _pending = [];

  void fireAll() {
    final callbacks = List.of(_pending)..forEach((c) => c());
    _pending.clear();
  }

  // The real clock never drives these timers, and a live timer would trip the
  // test binding's "timer still pending" invariant.
  Timer _inertHandle() => Timer(Duration.zero, () {})..cancel();

  @override
  Timer setTimeout(TimeoutCallback callback, int delay) {
    timeouts.add(delay);
    _pending.add(callback);
    return _inertHandle();
  }

  // ... setInterval, clearTimeout, clearInterval
}
```

## `timeoutManager.reset`

Restores `DefaultTimeoutProvider`.
