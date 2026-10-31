import 'dart:async';

/// A callback the manager may defer to a later tick.
typedef NotifyCallback = void Function();

/// Wraps the invocation of a single callback. Replaceable so a framework can
/// run notifications inside its own scope (React Query wraps them in
/// `React.act` while testing).
typedef NotifyFunction = void Function(NotifyCallback callback);

/// Wraps the invocation of a whole flushed queue.
typedef BatchNotifyFunction = void Function(NotifyCallback callback);

/// Decides *when* a scheduled callback runs.
typedef ScheduleFunction = void Function(NotifyCallback callback);

/// Defers to the end of the current microtask queue.
///
/// React Query schedules with `setTimeout(cb, 0)`, a macrotask. Flutter is
/// deliberately different here: a microtask runs *before* the next frame, so a
/// query state change is painted in that frame instead of lagging one behind,
/// which is also the timing the hooks had with their former `Future.microtask`.
///
/// Like the JS version this is not routed through [timeoutManager] —
/// notifications are not application timers, and a fake clock must not hold
/// them back.
void defaultScheduler(NotifyCallback callback) => scheduleMicrotask(callback);

/// Defers to the next event-loop tick, matching React Query's
/// `systemSetTimeoutZero` exactly. Pass it to [NotifyManager.setScheduler] to
/// get the JS timing.
void systemTimerZero(NotifyCallback callback) => Timer.run(callback);

/// Coalesces notifications so one fetch produces one rebuild.
///
/// Port of `notifyManager.ts`. Without it every step of a fetch (pending,
/// success, each observer of the same key) pushed its own notification, so a
/// single `invalidateQueries` over N observers rebuilt N times in an order that
/// depended on microtask scheduling.
///
/// [batch] is re-entrant through a transaction counter, and **returns the value
/// of its callback** — `fetchQuery`, `refetchQueries` and `invalidateQueries`
/// all have to hand a `Future` back out of a batch.
class NotifyManager {
  List<NotifyCallback> _queue = <NotifyCallback>[];
  int _transactions = 0;

  NotifyFunction _notifyFn = (callback) => callback();
  BatchNotifyFunction _batchNotifyFn = (callback) => callback();
  ScheduleFunction _scheduleFn = defaultScheduler;

  /// Runs [callback] now, holding every notification it triggers until the
  /// outermost batch ends.
  T batch<T>(T Function() callback) {
    T result;
    _transactions++;
    try {
      result = callback();
    } finally {
      _transactions--;
      if (_transactions == 0) _flush();
    }
    return result;
  }

  /// Wraps [callback] so every call to it is batched. Hooks subscribe through
  /// this, which is what keeps one fetch down to one rebuild.
  void Function(T) batchCalls<T>(void Function(T) callback) {
    return (T arg) => schedule(() => callback(arg));
  }

  /// Queues [callback] when inside a batch, defers it to the next tick otherwise.
  void schedule(NotifyCallback callback) {
    if (_transactions > 0) {
      _queue.add(callback);
    } else {
      _scheduleFn(() => _notifyFn(callback));
    }
  }

  void _flush() {
    final queued = _queue;
    _queue = <NotifyCallback>[];
    if (queued.isEmpty) return;
    _scheduleFn(() {
      _batchNotifyFn(() {
        for (final callback in queued) {
          _notifyFn(callback);
        }
      });
    });
  }

  /// Overrides how a single notification is invoked.
  void setNotifyFunction(NotifyFunction fn) => _notifyFn = fn;

  /// Overrides how a flushed queue is invoked.
  void setBatchNotifyFunction(BatchNotifyFunction fn) => _batchNotifyFn = fn;

  /// Overrides when scheduled notifications run. Pass a synchronous function to
  /// flush notifications inline, which is what tests want.
  void setScheduler(ScheduleFunction fn) => _scheduleFn = fn;

  /// Restores the default scheduler and notify functions.
  void reset() {
    _queue = <NotifyCallback>[];
    _transactions = 0;
    _notifyFn = (callback) => callback();
    _batchNotifyFn = (callback) => callback();
    _scheduleFn = defaultScheduler;
  }
}

/// The manager every cache, observer and hook notifies through.
final NotifyManager notifyManager = NotifyManager();
