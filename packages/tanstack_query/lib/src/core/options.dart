/// Default options applied to queries (enabled, staleTime, refetch policy).
class QueryDefaultOptions {
  final bool enabled;
  final double? staleTime;

  /// Retry policy for every query: `bool`, `int` or
  /// `(failureCount, error) => bool`.
  ///
  /// `null` means "not configured", and the retryer then uses 3 — the same
  /// split as in JavaScript, where the `3` lives in `createRetryer`. It is what
  /// lets [QueryClient.fetchQuery] fall back to `retry: false` only when
  /// nothing else configured it.
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
      this.retry,
      this.retryDelay = 1000,
      this.retryOnMount = true,
      this.refetchOnMount = true,
      this.gcTime = 5 * 60 * 1000,
      this.refetchOnWindowFocus = true,
      this.refetchOnReconnect = true});
}

/// Nullable counterpart of [QueryDefaultOptions]: every field left `null` means
/// "not configured", so [QueryClient.setQueryDefaults] can tell an explicit
/// default apart from an absent one when merging several key defaults.
class QueryDefaults {
  final bool? enabled;
  final double? staleTime;
  final dynamic retry; // bool | int | Function
  final dynamic retryDelay; // int | Function
  final bool? retryOnMount;
  final bool? refetchOnMount;
  final int? gcTime;
  final bool? refetchOnWindowFocus;
  final bool? refetchOnReconnect;

  const QueryDefaults({
    this.enabled,
    this.staleTime,
    this.retry,
    this.retryDelay,
    this.retryOnMount,
    this.refetchOnMount,
    this.gcTime,
    this.refetchOnWindowFocus,
    this.refetchOnReconnect,
  });

  /// Field-by-field merge; [other] wins where it sets a value.
  QueryDefaults merge(QueryDefaults other) => QueryDefaults(
        enabled: other.enabled ?? enabled,
        staleTime: other.staleTime ?? staleTime,
        retry: other.retry ?? retry,
        retryDelay: other.retryDelay ?? retryDelay,
        retryOnMount: other.retryOnMount ?? retryOnMount,
        refetchOnMount: other.refetchOnMount ?? refetchOnMount,
        gcTime: other.gcTime ?? gcTime,
        refetchOnWindowFocus: other.refetchOnWindowFocus ?? refetchOnWindowFocus,
        refetchOnReconnect: other.refetchOnReconnect ?? refetchOnReconnect,
      );
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
