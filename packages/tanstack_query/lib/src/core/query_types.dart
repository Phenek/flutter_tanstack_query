import 'types.dart';

/// Typedef for a function that returns initial data (used by `initialData`).
typedef InitialDataFn<T> = T? Function();

/// Typedef for a function that returns the `initialDataUpdatedAt` timestamp.
typedef InitialDataUpdatedAtFn = int? Function();

/// Typedef for placeholder data function: takes previous value and previous query (observer-only) and returns a value.
typedef PlaceholderDataFn<T> = T? Function(T? previousValue, dynamic previousQuery);

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

  /// Initial data to populate the cache with if no entry exists.
  /// Can be a value (`T`) or an `InitialDataFn<T>`.
  final Object? initialData;

  /// Timestamp (ms) or `InitialDataUpdatedAtFn` for when `initialData` was last updated.
  final Object? initialDataUpdatedAt;

  /// Placeholder data to show while a query is pending; not persisted to cache.
  /// Can be a value (`T`) or a `PlaceholderDataFn<T>` that receives `(previousValue, previousQuery)`.
  final Object? placeholderData;

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
    this.initialData,
    this.initialDataUpdatedAt,
    this.placeholderData,
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
    Object? initialData,
    Object? initialDataUpdatedAt,
    Object? placeholderData,
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
      initialData: initialData ?? this.initialData,
      initialDataUpdatedAt:
          initialDataUpdatedAt ?? this.initialDataUpdatedAt,
      placeholderData: placeholderData ?? this.placeholderData,
    );
  }

  /// Evaluate `initialData` safely and return a typed value or `null`.
  T? resolveInitialData() {
    try {
      if (initialData is InitialDataFn<T>) {
        return (initialData as InitialDataFn<T>)();
      }
      return initialData as T?;
    } catch (_) {
      return null;
    }
  }

  /// Evaluate `initialDataUpdatedAt` safely and return an `int?` timestamp.
  int? resolveInitialDataUpdatedAt() {
    try {
      if (initialDataUpdatedAt is InitialDataUpdatedAtFn) {
        return (initialDataUpdatedAt as InitialDataUpdatedAtFn)();
      }
      return initialDataUpdatedAt as int?;
    } catch (_) {
      return null;
    }
  }

  /// Evaluate `placeholderData` safely; returns typed value or `null`.
  T? resolvePlaceholderData(T? previousValue, dynamic previousQuery) {
    try {
      if (placeholderData is PlaceholderDataFn<T>) {
        return (placeholderData as PlaceholderDataFn<T>)(previousValue, previousQuery);
      }
      return placeholderData as T?;
    } catch (_) {
      return null;
    }
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

  /// Whether the cached value is considered stale (observer calculates this).
  bool isStale;

  /// Milliseconds since epoch when the data itself was last updated. Useful for
  /// determining staleness independent of cache timestamp (used by initialData).
  int? dataUpdatedAt;

  /// If true, this result is placeholder data and should not be persisted.
  bool isPlaceholderData;

  /// Optional refetch callback provided by observers so consumers can trigger
  /// a refetch directly from the result object.
  Future<QueryResult<T>> Function({bool? throwOnError})? refetch;

  QueryResult(this.key, this.status, this.data, this.error,
      {this.isFetching = false,
      this.isStale = false,
      this.dataUpdatedAt,
      this.isPlaceholderData = false,
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
