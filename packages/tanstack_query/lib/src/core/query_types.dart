import 'types.dart';

/// Typedef for a function that returns initial data (used by `initialData`).
typedef InitialDataFn<T> = T? Function();

/// Typedef for a function that returns the `initialDataUpdatedAt` timestamp.
typedef InitialDataUpdatedAtFn = int? Function();

/// Typedef for placeholder data function: takes previous value and previous query (observer-only) and returns a value.
typedef PlaceholderDataFn<T> = T? Function(
    T? previousValue, dynamic previousQuery);

/// Direction for infinite pagination fetches.
enum FetchDirection {
  forward,
  backward,
}

/// Metadata passed to a fetch to indicate pagination behavior.
class FetchMeta {
  final FetchMore? fetchMore;

  const FetchMeta({this.fetchMore});
}

/// Metadata for fetching more pages.
class FetchMore {
  final FetchDirection direction;

  const FetchMore({required this.direction});
}

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

  /// Whether the query should refetch when the observer mounts/subscribes.
  final bool? refetchOnMount;

  /// Whether the query should refetch on window/app focus.
  final bool? refetchOnWindowFocus;

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
    this.refetchOnMount,
    this.refetchOnWindowFocus,
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
    bool? refetchOnMount,
    bool? refetchOnWindowFocus,
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
      refetchOnMount: refetchOnMount ?? this.refetchOnMount,
      refetchOnWindowFocus: refetchOnWindowFocus ?? this.refetchOnWindowFocus,
      refetchOnReconnect: refetchOnReconnect ?? this.refetchOnReconnect,
      gcTime: gcTime ?? this.gcTime,
      initialData: initialData ?? this.initialData,
      initialDataUpdatedAt: initialDataUpdatedAt ?? this.initialDataUpdatedAt,
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
        return (placeholderData as PlaceholderDataFn<T>)(
            previousValue, previousQuery);
      }
      return placeholderData as T?;
    } catch (_) {
      return null;
    }
  }
}

/// Options specific to infinite queries.
///
/// Note: This extends the general `QueryOptions` so shared options such as
/// `retry`, `retryDelay` and `retryOnMount` are available for infinite
/// queries as well. The `queryFn` for infinite queries receives a `pageParam`.
class InfiniteQueryOptions<T> extends QueryOptions<List<T>> {
  /// The page-aware query function. Receives the page parameter and returns
  /// the page data or `null`.
  final Future<T?> Function(int pageParam) pageQueryFn;

  final int initialPageParam;
  final int? Function(T lastResult)? getNextPageParam;
  final int? Function(T firstResult)? getPreviousPageParam;

  InfiniteQueryOptions({
    required super.queryKey,
    required Future<T?> Function(int pageParam) queryFn,
    required this.initialPageParam,
    this.getNextPageParam,
    this.getPreviousPageParam,
    super.staleTime,
    super.enabled,
    super.refetchOnWindowFocus,
    super.refetchOnReconnect,
    super.refetchOnMount,
    super.gcTime,
    super.retry,
    super.retryOnMount,
    super.retryDelay,
    dynamic super.initialData,
    dynamic super.initialDataUpdatedAt,
    dynamic super.placeholderData,
  })  : pageQueryFn = queryFn,
        super(
          queryFn: () async {
            final value = await queryFn(initialPageParam);
            if (value == null) return <T>[];
            return <T>[value as T];
          },
        );

  /// Evaluate initial data for infinite queries as a list of pages.
  List<T>? resolveInitialPages() {
    try {
      if (initialData is InitialDataFn<List<T>>) {
        return (initialData as InitialDataFn<List<T>>)();
      }
      return initialData as List<T>?;
    } catch (_) {
      return null;
    }
  }

  /// Evaluate placeholder data for infinite queries as a list of pages.
  List<T>? resolvePlaceholderPages(
      List<T>? previousValue, dynamic previousQuery) {
    try {
      if (placeholderData is PlaceholderDataFn<List<T>>) {
        return (placeholderData as PlaceholderDataFn<List<T>>)(
            previousValue, previousQuery);
      }
      return placeholderData as List<T>?;
    } catch (_) {
      return null;
    }
  }
}

/// Represents the current state of a query, including `status`, optional
/// `data`, `error` and whether a fetch is ongoing.
class QueryResult<T> {
  /// The data returned by the query, or `null` if not available.
  final T? data;

  /// Milliseconds since epoch when the data was last updated.
  int? dataUpdatedAt;

  /// The error object if the query failed, or `null`.
  final Object? error;

  /// The number of times the query has failed in its current fetch cycle.
  int failureCount;

  /// The last failure reason, or `null` if none.
  Object? failureReason;

  /// Whether the query is in the error state.
  bool get isError => status == QueryStatus.error;

  /// Whether the query is currently fetching.
  final bool isFetching;

  /// Whether the query is in the pending/loading state.
  bool get isPending => status == QueryStatus.pending;

  /// Whether this result is placeholder data and should not be persisted.
  bool isPlaceholderData;

  /// Whether the cached value is considered stale.
  final bool isStale;

  /// Whether the query is in the success state.
  bool get isSuccess => status == QueryStatus.success;

  /// Optional refetch callback to trigger a refetch.
  final Future<QueryResult<T>> Function({bool? throwOnError})? refetch;

  /// The current status of the query.
  final QueryStatus status;

  /// Metadata describing the fetch that produced this result.
  final FetchMeta? fetchMeta;

  /// The key uniquely identifying this query.
  final String key;

  QueryResult(
    this.key,
    this.status,
    this.data,
    this.error, {
    this.isFetching = false,
    this.isStale = false,
    this.dataUpdatedAt,
    this.isPlaceholderData = false,
    this.refetch,
    this.failureCount = 0,
    this.failureReason,
    this.fetchMeta,
  });
}

/// Result type returned by [useInfiniteQuery], with helper `fetchNextPage` and
/// `isFetchingNextPage` flag.
class InfiniteQueryResult<T> extends QueryResult<List<T>> {
  bool isFetchingNextPage;
  bool isFetchingPreviousPage;
  bool isFetchNextPageError;
  bool isFetchPreviousPageError;
  bool isRefetching;
  bool isRefetchError;
  bool hasNextPage;
  bool hasPreviousPage;
  Function? fetchNextPage;
  Function? fetchPreviousPage;

  InfiniteQueryResult({
    required String key,
    required QueryStatus status,
    required List<T> data,
    required bool isFetching,
    required Object? error,
    required this.isFetchingNextPage,
    this.fetchNextPage,
    this.isFetchingPreviousPage = false,
    this.isFetchNextPageError = false,
    this.isFetchPreviousPageError = false,
    this.isRefetching = false,
    this.isRefetchError = false,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
    this.fetchPreviousPage,
    bool isStale = false,
    int? dataUpdatedAt,
    bool isPlaceholderData = false,
    int failureCount = 0,
    Object? failureReason,
    Future<QueryResult<List<T>>> Function({bool? throwOnError})? refetch,
    FetchMeta? fetchMeta,
  }) : super(key, status, data, error,
            isFetching: isFetching,
            isStale: isStale,
            dataUpdatedAt: dataUpdatedAt,
            isPlaceholderData: isPlaceholderData,
            failureCount: failureCount,
            failureReason: failureReason,
            refetch: refetch,
            fetchMeta: fetchMeta);

  InfiniteQueryResult<T> copyWith({
    String? key,
    List<T>? data,
    QueryStatus? status,
    bool? isFetching,
    Object? error,
    bool? isFetchingNextPage,
    Function? fetchNextPage,
    bool? isFetchingPreviousPage,
    bool? isFetchNextPageError,
    bool? isFetchPreviousPageError,
    bool? isRefetching,
    bool? isRefetchError,
    bool? hasNextPage,
    bool? hasPreviousPage,
    Function? fetchPreviousPage,
    bool? isStale,
    int? dataUpdatedAt,
    bool? isPlaceholderData,
    int? failureCount,
    Object? failureReason,
    Future<QueryResult<List<T>>> Function({bool? throwOnError})? refetch,
    FetchMeta? fetchMeta,
  }) {
    return InfiniteQueryResult<T>(
      key: key ?? this.key,
      data: data ?? this.data!,
      status: status ?? this.status,
      isFetching: isFetching ?? this.isFetching,
      error: error ?? this.error,
      isFetchingNextPage: isFetchingNextPage ?? this.isFetchingNextPage,
      fetchNextPage: fetchNextPage ?? this.fetchNextPage,
      isFetchingPreviousPage:
          isFetchingPreviousPage ?? this.isFetchingPreviousPage,
      isFetchNextPageError: isFetchNextPageError ?? this.isFetchNextPageError,
      isFetchPreviousPageError:
          isFetchPreviousPageError ?? this.isFetchPreviousPageError,
      isRefetching: isRefetching ?? this.isRefetching,
      isRefetchError: isRefetchError ?? this.isRefetchError,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      hasPreviousPage: hasPreviousPage ?? this.hasPreviousPage,
      fetchPreviousPage: fetchPreviousPage ?? this.fetchPreviousPage,
      isStale: isStale ?? this.isStale,
      dataUpdatedAt: dataUpdatedAt ?? this.dataUpdatedAt,
      isPlaceholderData: isPlaceholderData ?? this.isPlaceholderData,
      failureCount: failureCount ?? this.failureCount,
      failureReason: failureReason ?? this.failureReason,
      refetch: refetch ?? this.refetch,
      fetchMeta: fetchMeta ?? this.fetchMeta,
    );
  }
}

bool hasNextPage<T>(
  InfiniteQueryOptions<T> options,
  List<T>? data,
) {
  if (options.getNextPageParam == null) return false;
  if (data == null || data.isEmpty) return false;
  return options.getNextPageParam!(data.last) != null;
}

bool hasPreviousPage<T>(
  InfiniteQueryOptions<T> options,
  List<T>? data,
) {
  if (options.getPreviousPageParam == null) return false;
  if (data == null || data.isEmpty) return false;
  return options.getPreviousPageParam!(data.first) != null;
}
