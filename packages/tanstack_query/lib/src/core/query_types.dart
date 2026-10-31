import 'types.dart';

// Forward declaration — implemented in infinite_query_behavior.dart.
// Using an `abstract` base here avoids a circular import: query_types ← query_observer ← infinite_query_behavior.
abstract class QueryBehavior<T> {
  const QueryBehavior();
  void onFetch(dynamic context, dynamic query);
}

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

  @override
  bool operator ==(Object other) =>
      other is FetchMeta && other.fetchMore == fetchMore;

  @override
  int get hashCode => fetchMore.hashCode;
}

/// Metadata for fetching more pages.
class FetchMore {
  final FetchDirection direction;

  const FetchMore({required this.direction});

  @override
  bool operator ==(Object other) =>
      other is FetchMore && other.direction == direction;

  @override
  int get hashCode => direction.hashCode;
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

  /// Controls identity stability of the data written to the cache.
  ///
  /// Accepts the same shapes as in JavaScript: `false` to store the new data
  /// untouched, or a `T Function(T? previous, T next)` to merge it yourself.
  /// `null` (the default) means [replaceEqualDeep] — a refetch that brings back
  /// the same payload keeps the previous instance, so observers compare equal
  /// and nothing rebuilds.
  final Object? structuralSharing;

  /// Optional fetch behavior hook. Implementations replace the default [queryFn]
  /// with a custom async closure before [Query] creates its [Retryer].
  /// `InfiniteQueryObserver` injects [InfiniteQueryBehavior] here (mirroring
  /// React's `InfiniteQueryObserver.setOptions({ behavior: infiniteQueryBehavior() })`).
  final QueryBehavior<T>? behavior;

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
    this.structuralSharing,
    this.behavior,
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
    Object? structuralSharing,
    QueryBehavior<T>? behavior,
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
      structuralSharing: structuralSharing ?? this.structuralSharing,
      behavior: behavior ?? this.behavior,
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

/// Options an observer adds on top of the ones the [Query] itself needs.
///
/// Port of `QueryObserverOptions` in `types.ts`. The split matters: a [Query]
/// caches what the `queryFn` returned (`TQueryFnData`), while an observer may
/// expose something derived from it (`TData`). Two observers on the same key can
/// therefore select different shapes out of one cached payload, and one network
/// call.
class QueryObserverOptions<TQueryFnData, TData>
    extends QueryOptions<TQueryFnData> {
  /// Transforms the cached data into what this observer exposes.
  ///
  /// It runs on every result, so it must be cheap and pure. The transformed
  /// value goes through `structuralSharing`, so returning a freshly built record
  /// or list does not by itself cause a rebuild.
  ///
  /// The function is memoized on its own identity, like in React Query: an
  /// inline closure rebuilt on every widget build re-runs the selection, while a
  /// top-level function or a tear-off does not.
  final TData Function(TQueryFnData data)? select;

  QueryObserverOptions({
    required super.queryKey,
    required super.queryFn,
    this.select,
    super.staleTime,
    super.enabled,
    super.retry,
    super.retryDelay,
    super.retryOnMount,
    super.refetchOnMount,
    super.refetchOnWindowFocus,
    super.refetchOnReconnect,
    super.gcTime,
    super.initialData,
    super.initialDataUpdatedAt,
    super.placeholderData,
    super.structuralSharing,
    super.behavior,
  });
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
    super.structuralSharing,
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
  final int? dataUpdatedAt;

  /// The error object if the query failed, or `null`.
  final Object? error;

  /// The number of times the query has failed in its current fetch cycle.
  final int failureCount;

  /// The last failure reason, or `null` if none.
  final Object? failureReason;

  /// Whether the query is in the error state.
  bool get isError => status == QueryStatus.error;

  /// Whether the query is currently fetching.
  final bool isFetching;

  /// Whether the query is in the pending/loading state.
  bool get isPending => status == QueryStatus.pending;

  /// Whether this result is placeholder data and should not be persisted.
  final bool isPlaceholderData;

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

  /// Field-by-field equality, the port of React Query's
  /// `shallowEqualObjects(nextResult, prevResult)` guard: an observer that
  /// recomputes an identical result must not notify its listeners.
  ///
  /// Like the JS version this compares [data] by `==`, so a fresh object that
  /// merely *looks* the same still counts as a change. `structuralSharing`
  /// keeps the previous instance when the data is deeply equal.
  @override
  bool operator ==(Object other) {
    if (other is! QueryResult<T> || other.runtimeType != runtimeType) {
      return false;
    }
    return other.key == key &&
        other.status == status &&
        other.data == data &&
        other.error == error &&
        other.isFetching == isFetching &&
        other.isStale == isStale &&
        other.dataUpdatedAt == dataUpdatedAt &&
        other.isPlaceholderData == isPlaceholderData &&
        other.failureCount == failureCount &&
        other.failureReason == failureReason &&
        other.fetchMeta == fetchMeta &&
        other.refetch == refetch;
  }

  @override
  int get hashCode => Object.hash(key, status, data, error, isFetching, isStale,
      dataUpdatedAt, isPlaceholderData, failureCount, failureReason, fetchMeta);
}

/// Result type returned by [useInfiniteQuery], with helper `fetchNextPage` and
/// `isFetchingNextPage` flag.
class InfiniteQueryResult<T> extends QueryResult<List<T>> {
  final bool isFetchingNextPage;
  final bool isFetchingPreviousPage;
  final bool isFetchNextPageError;
  final bool isFetchPreviousPageError;
  final bool isRefetching;
  final bool isRefetchError;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final Function? fetchNextPage;
  final Function? fetchPreviousPage;

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

  /// Extends [QueryResult]'s field-by-field equality with the infinite-only
  /// fields.
  ///
  /// Without it the `shallowEqualObjects(nextResult, prevResult)` guard in
  /// `QueryObserver.updateResult()` would compare only the shared fields, and a
  /// change confined to e.g. `hasNextPage` or `isFetchingNextPage` would be
  /// swallowed. `fetchNextPage` / `fetchPreviousPage` are compared too: they are
  /// tear-offs of the observer's own methods, so they stay equal across passes.
  @override
  bool operator ==(Object other) =>
      super == other &&
      other is InfiniteQueryResult<T> &&
      other.isFetchingNextPage == isFetchingNextPage &&
      other.isFetchingPreviousPage == isFetchingPreviousPage &&
      other.isFetchNextPageError == isFetchNextPageError &&
      other.isFetchPreviousPageError == isFetchPreviousPageError &&
      other.isRefetching == isRefetching &&
      other.isRefetchError == isRefetchError &&
      other.hasNextPage == hasNextPage &&
      other.hasPreviousPage == hasPreviousPage &&
      other.fetchNextPage == fetchNextPage &&
      other.fetchPreviousPage == fetchPreviousPage;

  @override
  int get hashCode => Object.hash(
      super.hashCode,
      isFetchingNextPage,
      isFetchingPreviousPage,
      isFetchNextPageError,
      isFetchPreviousPageError,
      isRefetching,
      isRefetchError,
      hasNextPage,
      hasPreviousPage);

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
