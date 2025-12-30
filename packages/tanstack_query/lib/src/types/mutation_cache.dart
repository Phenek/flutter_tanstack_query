/// Configuration callbacks for mutation lifecycle events such as
/// `onMutate`, `onSuccess`, and `onError`.
class MutationCacheConfig {
  /// Called when a mutation fails with an error.
  final dynamic Function(dynamic error)? onError;

  /// Called when a mutation succeeds with the returned data.
  final dynamic Function(dynamic data)? onSuccess;

  /// Called just before a mutation is executed (useful for optimistic updates).
  final dynamic Function()? onMutate;

  MutationCacheConfig({this.onError, this.onSuccess, this.onMutate});
}

/// Simple holder for mutation cache configuration and callbacks.
class MutationCache {
  /// The configuration that contains callbacks invoked during mutation
  /// lifecycle events.
  final MutationCacheConfig config;

  MutationCache({required this.config});
}
