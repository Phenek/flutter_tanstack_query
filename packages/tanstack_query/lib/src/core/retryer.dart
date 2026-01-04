import 'dart:async';

class CancelledError implements Exception {
  final bool silent;
  final bool revert;
  CancelledError({this.silent = false, this.revert = false});

  @override
  String toString() => 'CancelledError';
}

class Retryer<T> {
  final Future<T> Function() fn;
  final dynamic retry; // bool | int | Function(int, dynamic) -> bool
  final dynamic retryDelay; // int | Function(int, dynamic) -> int

  final void Function(int failureCount, dynamic error)? onFail;

  bool _cancelled = false;
  String _status = 'pending';
  Future<T>? _promise;
  Timer? _timer;
  int _failureCount = 0;

  Retryer({required this.fn, this.retry = 0, this.retryDelay = 1000, this.onFail});

  String status() => _status;

  int get failureCount => _failureCount;

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

  void continueRetry() {
    // No-op for this simple implementation
  }
}
