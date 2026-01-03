import 'types.dart';

/// Represents the current state of a mutation operation.
class MutationState<T> {
  /// The current mutation result data, or `null` if unavailable.
  final T? data;

  /// Current status of the mutation (idle, pending, error, success).
  final MutationStatus status;

  /// Error object when the mutation failed, if any.
  final Object? error;

  MutationState(this.data, this.status, this.error);

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
  final Function(P) mutate;

  /// The latest mutation data, if available.
  final T? data;

  /// Current mutation status.
  final MutationStatus status;

  /// The error from the last mutation, if any.
  final Object? error;

  MutationResult(this.mutate, this.data, this.status, this.error);

  /// Whether the mutation is currently idle.
  bool get isIdle => status == MutationStatus.idle;

  /// Whether the mutation is in progress.
  bool get isPending => status == MutationStatus.pending;

  /// Whether the last mutation finished with an error.
  bool get isError => status == MutationStatus.error;

  /// Whether the last mutation finished successfully.
  bool get isSuccess => status == MutationStatus.success;
}
