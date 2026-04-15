import 'dart:async';
import 'focus_manager.dart';
import 'online_manager.dart';

/// Exception thrown when a query or mutation is cancelled.
class CancelledError implements Exception {
  /// Whether the cancellation should be silent (suppress error reporting).
  final bool silent;

  /// Whether the cancelled operation should revert any optimistic updates.
  final bool revert;

  /// Creates a [CancelledError].
  ///
  /// Set [silent] to `true` to suppress error reporting.
  /// Set [revert] to `true` to undo any optimistic updates.
  CancelledError({this.silent = false, this.revert = false});

  @override
  String toString() => 'CancelledError';
}

class Retryer<T> {
  final Future<T> Function() fn;
  final dynamic retry; // bool | int | Function(int, dynamic) -> bool
  final dynamic retryDelay; // int | Function(int, dynamic) -> int

  final void Function(int failureCount, dynamic error)? onFail;
  final void Function()? onPause;
  final void Function()? onContinue;

  bool _cancelled = false;
  String _status = 'pending';
  Future<T>? _promise;
  Timer? _timer;
  int _failureCount = 0;

  /// Completer resolved by [continueRetry] to wake a paused retry loop.
  Completer<void>? _pauseCompleter;

  Retryer({
    required this.fn,
    this.retry = 0,
    this.retryDelay = 1000,
    this.onFail,
    this.onPause,
    this.onContinue,
  });

  String status() => _status;

  int get failureCount => _failureCount;

  /// Returns `true` when the app is focused and online — mirroring React's
  /// `canContinue` check inside the retryer loop.
  bool _canContinue() {
    return focusManager.isFocused() &&
        onlineManager.isOnline();
  }

  /// Suspends the retry loop until [continueRetry] is called or
  /// [_canContinue] is true. Mirrors React's `pause()` promise.
  Future<void> _pause() {
    _pauseCompleter = Completer<void>();
    onPause?.call();
    return _pauseCompleter!.future.then((_) {
      _pauseCompleter = null;
      if (!_cancelled) onContinue?.call();
    });
  }

  Future<void> _delay(int ms) {
    final c = Completer<void>();
    _timer = Timer(Duration(milliseconds: ms), () {
      _timer = null;
      c.complete();
    });
    return c.future;
  }

  Future<T> start() {
    if (_promise != null) return _promise as Future<T>;

    final completer = Completer<T>();
    _promise = completer.future;

    Future<void> attempt() async {
      if (_cancelled) {
        completer.completeError(CancelledError());
        _status = 'rejected';
        return;
      }

      try {
        final r = await fn();
        if (!_cancelled) {
          _status = 'fulfilled';
          completer.complete(r);
        } else {
          completer.completeError(CancelledError());
          _status = 'rejected';
        }
      } catch (e) {
        if (_cancelled) {
          completer.completeError(CancelledError());
          _status = 'rejected';
          return;
        }

        // Increase failure count and notify
        _failureCount += 1;
        onFail?.call(_failureCount, e);

        // Determine whether to retry
        var shouldRetry = false;
        if (retry is bool) {
          shouldRetry = retry == true;
        } else if (retry is int) {
          shouldRetry = _failureCount <= (retry as int);
        } else if (retry is Function) {
          try {
            shouldRetry = (retry as Function)(_failureCount, e) == true;
          } catch (_) {
            shouldRetry = false;
          }
        }

        if (shouldRetry && !_cancelled) {
          // determine delay
          int delayMs = 0;
          if (retryDelay is int) {
            delayMs = retryDelay as int;
          } else if (retryDelay is Function) {
            try {
              final val = (retryDelay as Function)(_failureCount, e);
              delayMs = val is int ? val : 0;
            } catch (_) {
              delayMs = 0;
            }
          }

          if (delayMs > 0) {
            await _delay(delayMs);
            if (_cancelled) {
              completer.completeError(CancelledError());
              _status = 'rejected';
              return;
            }
          }

          // ── Pause if the app is offline or unfocused, mirroring React's
          // canContinue / pause() pattern in the retryer.
          if (!_cancelled && !_canContinue()) {
            await _pause();
            if (_cancelled) {
              completer.completeError(CancelledError());
              _status = 'rejected';
              return;
            }
          }

          await attempt();
        } else {
          _status = 'rejected';
          completer.completeError(e);
        }
      }
    }

    attempt();

    return _promise as Future<T>;
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Wakes a paused retry that is waiting in [_pause]. Mirrors React's
  /// `retryer.continue()` / `continueRetry()` public API.
  void continueRetry() {
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }
  }
}
