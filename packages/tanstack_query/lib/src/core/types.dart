import 'dart:async';

/// Status values for queries.
enum QueryStatus {
  /// The query is scheduled or currently fetching.
  pending,

  /// The query completed with an error.
  error,

  /// The query completed successfully.
  success
}

/// Status values for mutations.
enum MutationStatus {
  /// The mutation has not started yet.
  idle,

  /// The mutation is in progress.
  pending,

  /// The mutation finished with an error.
  error,

  /// The mutation finished successfully.
  success
}

/// Simple wrapper to track whether a `Future` has completed or failed. Used by
/// the cache to detect running or errored fetches.
class TrackedFuture<T> implements Future<T> {
  final Future<T> _future;
  bool _isCompleted = false;
  bool _hasError = false;
  T? _result;
  Object? _error;

  TrackedFuture(Future<T> future) : _future = future {
    _future.then((value) {
      _isCompleted = true;
      _result = value;
    }).catchError((e) {
      _isCompleted = true;
      _hasError = true;
      _error = e;
    });
  }

  /// `true` if the underlying future has completed.
  bool get isCompleted => _isCompleted;

  /// `true` if the underlying future completed with an error.
  bool get hasError => _hasError;

  /// The successful result, if available.
  T? get result => _result;

  /// The error thrown by the underlying future, if any.
  Object? get error => _error;

  @override
  Future<S> then<S>(FutureOr<S> Function(T value) onValue,
      {Function? onError}) {
    return _future.then(onValue, onError: onError);
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    return _future.catchError(onError, test: test);
  }

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) {
    return _future.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) {
    return _future.whenComplete(action);
  }

  @override
  Stream<T> asStream() {
    return _future.asStream();
  }
}
