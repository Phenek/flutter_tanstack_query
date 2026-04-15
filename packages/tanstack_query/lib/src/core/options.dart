/// Default options applied to queries (enabled, staleTime, refetch policy).
class QueryDefaultOptions {
  final bool enabled;
  final double? staleTime;
  final dynamic retry; // bool | int | Function
  final dynamic retryDelay; // int | Function
  final bool retryOnMount;
  final bool refetchOnMount;
  final int gcTime;
  final bool refetchOnWindowFocus;
  final bool refetchOnReconnect;

  const QueryDefaultOptions(
      {this.enabled = true,
      this.staleTime = 0,
      this.retry = 3,
      this.retryDelay = 1000,
      this.retryOnMount = true,
      this.refetchOnMount = true,
      this.gcTime = 5 * 60 * 1000,
      this.refetchOnWindowFocus = true,
      this.refetchOnReconnect = true});
}

/// Default options placeholder for mutations.
class MutationDefaultOptions {
  /// Default GC time (ms) for mutations. Defaults to 5 minutes, matching
  /// React Query's behaviour. Use 0 for immediate eviction on unmount,
  /// a positive value for a custom delay, or a negative value to disable GC.
  final int gcTime;

  /// Default retry settings for mutations. Defaults to no retries (0).
  final dynamic retry;
  final dynamic retryDelay;

  const MutationDefaultOptions(
      {this.gcTime = 5 * 60 * 1000, this.retry = 0, this.retryDelay = 1000});
}

/// Container for default query and mutation options.
class DefaultOptions {
  final QueryDefaultOptions queries;
  final MutationDefaultOptions mutations;

  /// Creates a [DefaultOptions] with optional [queries] and [mutations] defaults.
  const DefaultOptions(
      {this.queries = const QueryDefaultOptions(),
      this.mutations = const MutationDefaultOptions()});
}
