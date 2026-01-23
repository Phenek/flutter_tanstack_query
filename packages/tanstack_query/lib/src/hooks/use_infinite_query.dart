import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';
import '../core/infinite_query_observer.dart';

/// Hook for paginated/infinite queries.
///
/// [queryFn] receives the page index and should return the page data. The
/// returned [InfiniteQueryResult] exposes `fetchNextPage`, `isFetchingNextPage`,
/// and accumulated `data` pages.
///
/// Parameters:
/// - [queryKey]: Unique key for the list of pages.
/// - [queryFn]: Function that receives a page index and returns the page data.
/// - [initialPageParam]: The initial page index to start fetching from.
/// - [getNextPageParam]: Optional function to compute the next page index
///   given the last page's result.
/// - [getPreviousPageParam]: Optional function to compute the previous page
///   index given the first page's result.
/// - [gcTime]: Garbage-collection time in milliseconds for this query's cache entry.
/// - [enabled]: Whether the query is enabled.
/// - [initialData]: T | () => T — initial value that is persisted to cache if
///   provided and the cache is empty. It is considered stale by default
///   unless `initialDataUpdatedAt` is set.
/// - [initialDataUpdatedAt]: int (ms) | () => int | null — timestamp for when
///   the initialData was last updated; used together with staleTime to
///   determine if a refetch is required on mount.
/// - [placeholderData]: T | (previousValue, previousQuery) => T — observer-only
///   placeholder shown while the query is pending; not persisted to cache.
/// - [refetchOnMount]: When `true`, refetch when the observer mounts/subscribes.
/// - [refetchOnReconnect]: When `true`, refetch query on reconnect.
/// - [refetchOnWindowFocus]: When `true`, refetch query on window/app focus.
/// - [retry]: Controls retry behavior;
///   `false`, `true`, an `int`, or a function `(failureCount, error) => bool`.
/// - [retryOnMount]: If `false`, a query that currently has an error will not
///   attempt to retry when mounted.
/// - [retryDelay]: Milliseconds between retries, or a function
///   `(attempt, error) => int` returning the delay in ms.
/// - [staleTime]: Staleness duration (milliseconds) for cached pages.
/// - [enabled], [refetchOnWindowFocus], [refetchOnReconnect], [refetchOnMount]: same semantics as
///   [useQuery].

/// Hook for paginated/infinite queries.
///
/// This implementation now delegates the core behavior to
/// `InfiniteQueryObserver` (mirroring the TS architecture) and simply
/// subscribes to the observer for state updates.
InfiniteQueryResult<T> useInfiniteQuery<T>({
  required List<Object> queryKey,
  required Future<T?> Function(int pageParam) queryFn,
  bool? enabled,
  required int initialPageParam,
  int? Function(T lastResult)? getNextPageParam,
  double? staleTime,
  bool? refetchOnWindowFocus,
  bool? refetchOnReconnect,
  bool? refetchOnMount,
  int? gcTime,
  dynamic retry,
  bool? retryOnMount,
  dynamic retryDelay,
  Object? initialData,
  Object? initialDataUpdatedAt,
  Object? placeholderData,
  int? Function(T firstResult)? getPreviousPageParam,
}) {
  final queryClient = useQueryClient();
  final cacheKey = queryKeyToCacheKey(queryKey);

  final options = useMemoized(
      () => InfiniteQueryOptions<T>(
            queryKey: queryKey,
            queryFn: queryFn,
            initialPageParam: initialPageParam,
            getNextPageParam: getNextPageParam,
            getPreviousPageParam: getPreviousPageParam,
            staleTime: staleTime,
            enabled: enabled,
            refetchOnWindowFocus: refetchOnWindowFocus,
            refetchOnReconnect: refetchOnReconnect,
            refetchOnMount: refetchOnMount,
            gcTime: gcTime,
            retry: retry,
            retryOnMount: retryOnMount,
            retryDelay: retryDelay,
            initialData: initialData,
            initialDataUpdatedAt: initialDataUpdatedAt,
            placeholderData: placeholderData,
          ),
      [
        queryClient,
        queryFn,
        initialPageParam,
        getNextPageParam,
        getPreviousPageParam,
        staleTime,
        enabled,
        refetchOnWindowFocus,
        refetchOnReconnect,
        refetchOnMount,
        gcTime,
        retry,
        retryOnMount,
        retryDelay,
        initialData,
        initialDataUpdatedAt,
        placeholderData,
        cacheKey
      ]);
  // Create the observer once for this cache key and keep it in sync via setOptions
  final observer = useMemoized<InfiniteQueryObserver<T>>(
      () => InfiniteQueryObserver<T>(queryClient, options),
      [queryClient, cacheKey]);

  useEffect(() {
    // Keep observer options in sync
    observer.setOptions(options);

    return null;
  }, [observer, options]);

  final state = useState<InfiniteQueryResult<T>>(observer.getCurrentResult());

  useEffect(() {
    final unsubscribe = observer.subscribe((InfiniteQueryResult<T> res) {
      Future.microtask(() {
        try {
          state.value = res;
        } catch (_) {}
      });
    });

    return () {
      unsubscribe();
    };
  }, [observer, cacheKey]);

  return state.value;
}

/// Resets the pagination and result state for an infinite query.
/// Parameters:
/// - [currentPage]: Mutable reference to the current page index.
/// - [initialPageParam]: The page index to reset to.
/// - [result]: The [ValueNotifier] wrapping the current [InfiniteQueryResult<T>]
///   that will be modified.
/// - [isLoading]: Optional flag (currently unused) reserved for future control
///   of loading state.
///
/// Note: This operation clears existing data and places the query into a
/// pending state.
void resetValues<T>(ObjectRef<int> currentPage, int initialPageParam,
    ValueNotifier<InfiniteQueryResult<T>> result,
    {bool isLoading = false}) {
  currentPage.value = initialPageParam;
  // Use copyWith to create a fresh immutable-like result with cleared data
  // and pending status rather than mutating fields directly.
  result.value =
      result.value.copyWith(status: QueryStatus.pending, data: <T>[]);
}
