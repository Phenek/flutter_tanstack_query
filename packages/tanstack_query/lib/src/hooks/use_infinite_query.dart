import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';
import '../core/infinite_query_observer.dart';

/// Hook for paginated/infinite queries.
///
/// Mirrors React's `useInfiniteQuery` — the returned [InfiniteQueryResult]
/// exposes `fetchNextPage`, `fetchPreviousPage`, `isFetchingNextPage`,
/// `hasNextPage`, and `data` (an [InfiniteData] struct with parallel
/// `pages` and `pageParams` arrays).
///
/// Parameters:
/// - [queryKey]: Unique key for this infinite query.
/// - [queryFn]: Receives a [TPageParam] and returns the page data.
/// - [initialPageParam]: The first param passed to [queryFn] on mount.
/// - [getNextPageParam]: 4-arg function — `(lastPage, allPages, lastPageParam,
///   allPageParams) => TPageParam?`. Return `null` to signal no next page.
/// - [getPreviousPageParam]: 4-arg function for backward pagination. Optional.
/// - [maxPages]: Maximum number of pages to keep. Oldest page is dropped when
///   exceeded (mirrors React's `maxPages` option).
/// - [gcTime]: GC time in milliseconds for this query's cache entry.
/// - [enabled]: Whether the query is enabled.
/// - [initialData]: Value or `() => InfiniteData<T, TPageParam>` persisted to
///   cache on first access.
/// - [initialDataUpdatedAt]: Timestamp for [initialData] freshness.
/// - [placeholderData]: Observer-only placeholder shown while pending; not
///   persisted to cache.
/// - [refetchOnMount], [refetchOnReconnect], [refetchOnWindowFocus]: same
///   semantics as [useQuery].
/// - [retry], [retryOnMount], [retryDelay]: same semantics as [useQuery].
/// - [staleTime]: Staleness duration (milliseconds) for cached pages.
InfiniteQueryResult<T, TPageParam> useInfiniteQuery<T, TPageParam>({
  required List<Object> queryKey,
  required Future<T?> Function(TPageParam pageParam) queryFn,
  bool? enabled,
  required TPageParam initialPageParam,
  TPageParam? Function(
    T lastPage,
    List<T> allPages,
    TPageParam lastPageParam,
    List<TPageParam> allPageParams,
  )? getNextPageParam,
  TPageParam? Function(
    T firstPage,
    List<T> allPages,
    TPageParam firstPageParam,
    List<TPageParam> allPageParams,
  )? getPreviousPageParam,
  int? maxPages,
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
}) {
  final queryClient = useQueryClient();
  final cacheKey = queryKeyToCacheKey(queryKey);

  final options = useMemoized(
      () => InfiniteQueryOptions<T, TPageParam>(
            queryKey: queryKey,
            queryFn: queryFn,
            initialPageParam: initialPageParam,
            getNextPageParam: getNextPageParam,
            getPreviousPageParam: getPreviousPageParam,
            maxPages: maxPages,
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
        maxPages,
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

  final observer = useMemoized<InfiniteQueryObserver<T, TPageParam>>(
      () => InfiniteQueryObserver<T, TPageParam>(queryClient, options),
      [queryClient, cacheKey]);

  useEffect(() {
    observer.setOptions(options);
    return null;
  }, [observer, options]);

  final state = useState<InfiniteQueryResult<T, TPageParam>>(
      observer.getCurrentResult());

  useEffect(() {
    final unsubscribe =
        observer.subscribe((InfiniteQueryResult<T, TPageParam> res) {
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
///
/// Clears existing pages and places the query into a pending state.
void resetValues<T, TPageParam>(
    ObjectRef<TPageParam> currentPage,
    TPageParam initialPageParam,
    ValueNotifier<InfiniteQueryResult<T, TPageParam>> result,
    {bool isLoading = false}) {
  currentPage.value = initialPageParam;
  result.value = result.value.copyWith(
    status: QueryStatus.pending,
    data: InfiniteData<T, TPageParam>(pages: [], pageParams: []),
  );
}

/// Hook for paginated/infinite queries.
