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
  final int retry;
  final int retryDelay;

  bool _cancelled = false;
  String _status = 'pending';
  Future<T>? _promise;
  Timer? _timer;

  Retryer({required this.fn, this.retry = 0, this.retryDelay = 1000});

  String status() => _status;

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

    Future<void> attempt(int triesLeft) async {
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
        if (triesLeft > 0 && !_cancelled) {
          await _delay(retryDelay);
          if (_cancelled) {
            completer.completeError(CancelledError());
            _status = 'rejected';
            return;
          }
          await attempt(triesLeft - 1);
        } else {
          _status = 'rejected';
          completer.completeError(e);
        }
      }
    }

    attempt(retry);

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
