import 'types.dart';

class QueryOptions<T> {
  /// Function that performs the query and returns the data as a `Future<T>`.
  final Future<T> Function() queryFn;

  /// Key uniquely identifying this query.
  final List<Object> queryKey;

  /// Staleness duration (in milliseconds) for the cached data.
  final double? staleTime;

  /// Whether the query is enabled.
  final bool? enabled;

  /// Retry options: can be `bool` (true = infinite, false = none), `int` (max attempts),
  /// or a function `(failureCount, error) => bool` that returns whether to retry.
  final dynamic retry;

  /// Retry delay in milliseconds or a function `(attempt, error) => int`.
  final dynamic retryDelay;

  /// Whether the query should be retried on mount when it contains an error.
  final bool? retryOnMount;

  /// Whether the query should refetch on app restart.
  final bool? refetchOnRestart;

  /// Whether the query should refetch on reconnect.
  final bool? refetchOnReconnect;

  /// Garbage collection time (milliseconds) after which unused queries are removed.
  final int? gcTime;

  QueryOptions({
    required this.queryFn,
    required this.queryKey,
    this.staleTime,
    this.enabled,
    this.retry,
    this.retryDelay,
    this.retryOnMount,
    this.refetchOnRestart,
    this.refetchOnReconnect,
    this.gcTime,
  });

  QueryOptions<T> copyWith({
    Future<T> Function()? queryFn,
    List<Object>? queryKey,
    double? staleTime,
    bool? enabled,
    dynamic retry,
    dynamic retryDelay,
    bool? retryOnMount,
    bool? refetchOnRestart,
    bool? refetchOnReconnect,
    int? gcTime,
  }) {
    return QueryOptions<T>(
      queryFn: queryFn ?? this.queryFn,
      queryKey: queryKey ?? this.queryKey,
      staleTime: staleTime ?? this.staleTime,
      enabled: enabled ?? this.enabled,
      retry: retry ?? this.retry,
      retryDelay: retryDelay ?? this.retryDelay,
      retryOnMount: retryOnMount ?? this.retryOnMount,
      refetchOnRestart: refetchOnRestart ?? this.refetchOnRestart,
      refetchOnReconnect: refetchOnReconnect ?? this.refetchOnReconnect,
      gcTime: gcTime ?? this.gcTime,
    );
  }
}

/// Represents the current state of a query, including `status`, optional
/// `data`, `error` and whether a fetch is ongoing.
class QueryResult<T> {
  String key;
  QueryStatus status;
  T? data;

  /// Whether the query is currently fetching (background refetches etc).
  bool isFetching;
  Object? error;

  /// The number of times the query has failed in its current fetch cycle.
  /// Incremented each time a retry attempt fails and reset to 0 on success.
  int failureCount;

  /// The last failure reason (if any). Reset to `null` on success.
  Object? failureReason;

  /// Whether the cached value is considered stale.
  bool isStale;

  /// Optional refetch callback provided by observers so consumers can trigger
  /// a refetch directly from the result object.
  Future<QueryResult<T>> Function({bool? throwOnError})? refetch;

  QueryResult(this.key, this.status, this.data, this.error,
      {this.isFetching = false,
      this.isStale = false,
      this.refetch,
      this.failureCount = 0,
      this.failureReason});

  bool get isError => status == QueryStatus.error;
  bool get isSuccess => status == QueryStatus.success;
  bool get isPending => status == QueryStatus.pending;
}

/// Result type returned by [useInfiniteQuery], with helper `fetchNextPage` and
/// `isFetchingNextPage` flag.
class InfiniteQueryResult<T> extends QueryResult<List<T>> {
  bool isFetchingNextPage;
  Function? fetchNextPage;

  InfiniteQueryResult({
    required String key,
    required QueryStatus status,
    required List<T> data,
    required bool isFetching,
    required Object? error,
    required this.isFetchingNextPage,
    this.fetchNextPage,
  }) : super(key, status, data, error, isFetching: isFetching);

  InfiniteQueryResult<T> copyWith({
    String? key,
    List<T>? data,
    QueryStatus? status,
    bool? isFetching,
    Object? error,
    bool? isFetchingNextPage,
    Function? fetchNextPage,
  }) {
    return InfiniteQueryResult<T>(
      key: key ?? this.key,
      data: data ?? this.data!,
      status: status ?? this.status,
      isFetching: isFetching ?? this.isFetching,
      error: error ?? this.error,
      isFetchingNextPage: isFetchingNextPage ?? this.isFetchingNextPage,
      fetchNextPage: fetchNextPage ?? this.fetchNextPage,
    );
  }
}
