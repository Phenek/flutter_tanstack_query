import 'dart:async';
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
/// - [debounceTime]: If set, delays the initial fetch by the provided
///   duration to debounce rapid key changes.
/// - [retry]: Controls retry behavior; same accepted forms as in `useMutation`:
///   `false`, `true`, an `int`, or a function `(failureCount, error) => bool`.
/// - [retryOnMount]: If `false`, a query that currently has an error will not
///   attempt to retry when mounted.
/// - [retryDelay]: Milliseconds between retries, or a function
///   `(attempt, error) => int` returning the delay in ms.
/// - [enabled], [refetchOnRestart], [refetchOnReconnect]: same semantics as
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
  int Function(T lastResult)? getNextPageParam,
  Duration? debounceTime,
  double? staleTime,
  bool? refetchOnRestart,
  bool? refetchOnReconnect,
  int? gcTime,
  dynamic retry,
  bool? retryOnMount,
  dynamic retryDelay,
}) {
  final queryClient = useQueryClient();
  final cacheKey = queryKeyToCacheKey(queryKey);

  final options = useMemoized(
      () => InfiniteQueryOptions<T>(
            queryKey: queryKey,
            queryFn: queryFn,
            initialPageParam: initialPageParam,
            getNextPageParam: getNextPageParam,
            debounceTime: debounceTime,
            staleTime: staleTime,
            enabled: enabled,
            refetchOnRestart: refetchOnRestart,
            refetchOnReconnect: refetchOnReconnect,
            gcTime: gcTime,
            retry: retry,
            retryOnMount: retryOnMount,
            retryDelay: retryDelay,
          ),
      [
        queryClient,
        queryFn,
        initialPageParam,
        getNextPageParam,
        debounceTime,
        staleTime,
        enabled,
        refetchOnRestart,
        refetchOnReconnect,
        gcTime,
        retry,
        retryOnMount,
        retryDelay,
        cacheKey
      ]);

  // Create the observer once for this cache key and keep it in sync via setOptions
  final observer = useMemoized<InfiniteQueryObserver<T>>(
      () => InfiniteQueryObserver<T>(queryClient, options), [queryClient, cacheKey]);

  useEffect(() {
    // Keep observer options in sync
    observer.setOptions(options);

    return null;
  }, [observer, options]);

  final state = useState<InfiniteQueryResult<T>>(observer.getCurrentResult());

  useEffect(() {
    final unsubscribe = observer.subscribe((InfiniteQueryResult<T> res) {
      try {
        state.value = res;
        print('useInfiniteQuery - status ${state.value.status} value: ${state.value}');
      } catch (_) {}
    });

    return () {
      unsubscribe();
      print('dispose useInfiniteQuery - status ${state.value.status} value: ${state.value}');
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
void resetValues<T>(ObjectRef<int> currentPage, int initialPageParam, ValueNotifier<InfiniteQueryResult<T>> result,
    {bool isLoading = false}) {
  currentPage.value = initialPageParam;
  result.value.status = QueryStatus.pending;
  result.value.data = [];
}
