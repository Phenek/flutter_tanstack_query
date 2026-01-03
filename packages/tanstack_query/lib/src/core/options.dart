/// Default options applied to queries (enabled, staleTime, refetch policy).
class QueryDefaultOptions {
  final bool enabled;
  final double? staleTime;
  final bool refetchOnRestart;
  final bool refetchOnReconnect;

  const QueryDefaultOptions(
      {this.enabled = true,
      this.staleTime = 0,
      this.refetchOnRestart = true,
      this.refetchOnReconnect = true});
}

/// Default options placeholder for mutations.
class MutationDefaultOptions {
  const MutationDefaultOptions();
}

/// Container for default query and mutation options.
class DefaultOptions {
  final QueryDefaultOptions queries;
  final MutationDefaultOptions mutations;

  const DefaultOptions(
      {this.queries = const QueryDefaultOptions(),
      this.mutations = const MutationDefaultOptions()});
}
