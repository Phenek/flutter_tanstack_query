import 'package:tanstack_query/tanstack_query.dart';

/// Represents the current state of a mutation operation.
class MutationState<T> {
  /// The current mutation result data, or `null` if unavailable.
  final T? data;

  /// Current status of the mutation (idle, pending, error, success).
  final MutationStatus status;

  /// Error object when the mutation failed, if any.
  final Object? error;

  /// The number of times the mutation has failed in its current lifecycle.
  final int failureCount;

  /// The last failure reason (if any).
  final Object? failureReason;

  MutationState(this.data, this.status, this.error, {this.failureCount = 0, this.failureReason});

  /// Whether the mutation is currently idle.
  bool get isIdle => status == MutationStatus.idle;

  /// Whether the mutation is currently in progress.
  bool get isPending => status == MutationStatus.pending;

  /// Whether the last mutation finished with an error.
  bool get isError => status == MutationStatus.error;

  /// Whether the last mutation finished successfully.
  bool get isSuccess => status == MutationStatus.success;
}

/// The value returned by [useMutation], containing the `mutate` callback and
/// current mutation state (`status`, `data`, `error`).
class MutationResult<T, P> {
  /// Function to trigger the mutation.
  final void Function(P) mutate;

  /// Async version of `mutate` that returns a `Future<T>`.
  final Future<T> Function(P, [MutateOptions<T>?]) mutateAsync;

  /// Reset the mutation state.
  final void Function() reset;

  /// Internal supplier to get the latest observer result when accessed.
  final MutationObserverResult<T, P> Function() _getCurrent;

  MutationResult(this.mutate, this.mutateAsync, this.reset, this._getCurrent);

  T? get data => _getCurrent().data;
  MutationStatus get status => _getCurrent().status;
  Object? get error => _getCurrent().error;
  int get failureCount => _getCurrent().failureCount;
  Object? get failureReason => _getCurrent().failureReason;

  /// Whether the mutation is currently idle.
  bool get isIdle => status == MutationStatus.idle;

  /// Whether the mutation is in progress.
  bool get isPending => status == MutationStatus.pending;

  /// Whether the last mutation finished with an error.
  bool get isError => status == MutationStatus.error;

  /// Whether the last mutation finished successfully.
  bool get isSuccess => status == MutationStatus.success;
}
