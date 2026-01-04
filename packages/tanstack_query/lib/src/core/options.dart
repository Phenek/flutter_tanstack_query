/// Default options applied to queries (enabled, staleTime, refetch policy).
class QueryDefaultOptions {
  final bool enabled;
  final double? staleTime;
  final int retry;
  final int retryDelay;
  final int gcTime;
  final bool refetchOnRestart;
  final bool refetchOnReconnect;

  const QueryDefaultOptions(
      {this.enabled = true,
      this.staleTime = 0,
      this.retry = 0,
      this.retryDelay = 1000,
      this.gcTime = 5 * 60 * 1000,
      this.refetchOnRestart = true,
      this.refetchOnReconnect = true});
}

/// Default options placeholder for mutations.
class MutationDefaultOptions {
  /// Default GC time (ms) for mutations. Defaults to 0 to disable GC by default.
  final int gcTime;

  const MutationDefaultOptions({this.gcTime = 0});
}

/// Container for default query and mutation options.
class DefaultOptions {
  final QueryDefaultOptions queries;
  final MutationDefaultOptions mutations;

  const DefaultOptions(
      {this.queries = const QueryDefaultOptions(),
      this.mutations = const MutationDefaultOptions()});
}
