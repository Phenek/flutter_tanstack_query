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

  /// Retry options
  final int? retry;
  final int? retryDelay;

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
    this.refetchOnRestart,
    this.refetchOnReconnect,
    this.gcTime,
  });

  QueryOptions<T> copyWith({
    Future<T> Function()? queryFn,
    List<Object>? queryKey,
    double? staleTime,
    bool? enabled,
    int? retry,
    int? retryDelay,
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

  QueryResult(this.key, this.status, this.data, this.error,
      {this.isFetching = false});

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
