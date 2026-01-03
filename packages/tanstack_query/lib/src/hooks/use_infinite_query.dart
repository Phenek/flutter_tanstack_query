import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';

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
/// - [enabled], [refetchOnRestart], [refetchOnReconnect]: same semantics as
///   [useQuery].
InfiniteQueryResult<T> useInfiniteQuery<T>({
  required List<Object> queryKey,
  required Future<T?> Function(int pageParam) queryFn,
  bool? enabled,
  required int initialPageParam,
  int Function(T lastResult)? getNextPageParam,
  Duration? debounceTime,
  bool? refetchOnRestart,
  bool? refetchOnReconnect,
}) {
  final queryClient = useQueryClient();
  final cacheKey = queryKeyToCacheKey(queryKey);
  final currentPage = useRef<int>(initialPageParam);
  var isFirstRequest = useRef(true);
  final callerId =
      useMemoized(() => DateTime.now().microsecondsSinceEpoch.toString(), []);
  var cacheEntry = queryClient.queryCache[cacheKey];
  final result = useState<InfiniteQueryResult<T>>(
      cacheEntry != null && cacheEntry.result.isSuccess
          ? InfiniteQueryResult(
              key: cacheKey,
              status: cacheEntry.result.status,
              data: cacheEntry.result.data as List<T>,
              isFetching: cacheEntry.result.isFetching,
              error: cacheEntry.result.error,
              isFetchingNextPage: false)
          : InfiniteQueryResult(
              key: cacheKey,
              status: QueryStatus.pending,
              data: [],
              isFetching: false,
              error: null,
              isFetchingNextPage: false));

  var isMounted = true;
  Timer? timer;

  void updateCache(InfiniteQueryResult<T> queryResult,
      {TrackedFuture<dynamic>? queryFnRunning}) {
    if (queryResult.data == null && queryClient.queryCache.containsKey(cacheKey)) {
      queryClient.queryCache.remove(cacheKey);
      return;
    }

    queryClient.queryCache.set(cacheKey,
        QueryCacheEntry(queryResult, DateTime.now(), queryFnRunning: queryFnRunning),
        callerId: callerId);
  }

  // Safe setter to avoid updating the ValueNotifier after it has been disposed.
  void safeSetResult(InfiniteQueryResult<T> newValue) {
    if (!isMounted) return;
    try {
      result.value = newValue;
    } catch (e) {
      // In fetchNextPage the ValueNotifier may be disposed before
      // his async callback runs. Swallow the error to prevent an app freeze.
    }
  }

  void fetchNextPage(InfiniteQueryResult<T> resultPreviousPage) {
    final nextPage = getNextPageParam != null
        ? getNextPageParam(resultPreviousPage.data!.last)
        : currentPage.value;

    if (!isMounted) return;
    if (nextPage <= currentPage.value || resultPreviousPage.isFetchingNextPage)
      { return; }

    currentPage.value = nextPage;

    var queryLoadingMore = resultPreviousPage.copyWith(
        isFetching: true,
        status: resultPreviousPage.status,
        error: null,
        isFetchingNextPage: true);

    var futureFetch = TrackedFuture(queryFn(nextPage));
    if (isMounted) result.value = queryLoadingMore;
    updateCache(queryLoadingMore, queryFnRunning: futureFetch);

    futureFetch.then((value) {
      if (value is! T) return;
      var pageData = value;

      final data = [...?resultPreviousPage.data, value];

      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.success,
        data: data,
        isFetching: false,
        error: null,
        isFetchingNextPage: false,
      );
      queryResult.fetchNextPage = () => fetchNextPage(queryResult);

      safeSetResult(queryResult);
      updateCache(queryResult);

      queryClient.queryCache.config.onSuccess?.call(pageData);
    }).catchError((e) {
      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.error,
        data: <T>[],
        isFetching: false,
        error: e,
        isFetchingNextPage: false,
      );
      queryResult.fetchNextPage = () => fetchNextPage(queryResult);
      safeSetResult(queryResult);
      updateCache(queryResult);

      queryClient.queryCache.config.onError?.call(e);
    });
  }

  void fetch() {
    isFirstRequest.value = false;
    var cacheEntry = queryClient.queryCache[cacheKey];
    var shouldUpdateTheCache = false;

    if (cacheEntry == null ||
        cacheEntry.queryFnRunning == null ||
        cacheEntry.queryFnRunning!.isCompleted ||
        cacheEntry.queryFnRunning!.hasError) {
      var queryResult = InfiniteQueryResult<T>(
          key: cacheKey,
          status: QueryStatus.pending,
          data: [],
          isFetching: true,
          error: null,
          isFetchingNextPage: false);
      queryResult.fetchNextPage = () => fetchNextPage(queryResult);

      shouldUpdateTheCache = true;
      var futureFetch = TrackedFuture(queryFn(initialPageParam));

      //create CacheEntry
      queryClient.queryCache[cacheKey] = cacheEntry =
          QueryCacheEntry(queryResult, DateTime.now(), queryFnRunning: futureFetch);
    }
    // Loading State: cacheEntry has a Running Function, set result to propagate the loading state
    var futureFetch = cacheEntry.queryFnRunning!;
    if (isMounted) result.value = cacheEntry.result as InfiniteQueryResult<T>;

    futureFetch.then((value) {
      if (value is! T) return;
      var pageData = value;

      final data = [pageData];
      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.success,
        data: data,
        isFetching: false,
        error: null,
        isFetchingNextPage: false,
      );
      queryResult.fetchNextPage = () => fetchNextPage(queryResult);

      if (isMounted) result.value = queryResult;
      if (shouldUpdateTheCache) updateCache(queryResult);

      queryClient.queryCache.config.onSuccess?.call(pageData);
    }).catchError((e) {
      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.error,
        data: <T>[],
        isFetching: false,
        error: e,
        isFetchingNextPage: false,
      );
      queryResult.fetchNextPage = () => fetchNextPage(queryResult);
      if (isMounted) result.value = queryResult;
      if (shouldUpdateTheCache) updateCache(queryResult);

      queryClient.queryCache.config.onError?.call(e);
    });
  }

  void refetchPagesUpToCurrent() async {
    final List<T> data = [];
    try {
      //Loading...
      var queryResult = InfiniteQueryResult<T>(
          key: cacheKey,
          status: QueryStatus.pending,
          data: [],
          isFetching: true,
          error: null,
          isFetchingNextPage: false);
      queryResult.fetchNextPage = () => fetchNextPage(queryResult);
      if (isMounted) result.value = queryResult;

      for (int page = initialPageParam; page <= currentPage.value; page++) {
        final pageData = await queryFn(page);
        if (pageData == null || !isMounted) return;
        data.add(pageData);
      }

      queryResult = InfiniteQueryResult(
        key: cacheKey,
        status: QueryStatus.success,
        data: data,
        isFetching: false,
        error: null,
        isFetchingNextPage: false,
      );
      queryResult.fetchNextPage = () => fetchNextPage(queryResult);
      if (isMounted) result.value = queryResult;

      updateCache(queryResult);
    } catch (e) {
      debugPrint("An error occurred while refetching pages up to current: $e");
    }
  }

  useEffect(() {
    if ((enabled ?? queryClient.defaultOptions.queries.enabled) == false) { return null; }

    if (debounceTime == null || isFirstRequest.value) {
      resetValues(currentPage, initialPageParam, result);
      fetch();
    } else {
      if (timer == null) {
        resetValues(currentPage, initialPageParam, result, isLoading: true);
      }
      if (timer != null) {
        timer!.cancel();
      }
      timer = Timer(debounceTime, () {
        fetch();
      });
    }


    final unsubscribe = queryClient.queryCache.subscribe((event) {
      if (event.cacheKey != cacheKey) return;
      if (event.callerId != null && event.callerId == callerId) return;

      try {
        if (event.type == QueryCacheEventType.removed) {
          result.value = InfiniteQueryResult(
              key: cacheKey,
              status: QueryStatus.pending,
              data: [],
              isFetching: false,
              error: null,
              isFetchingNextPage: false);
        } else if (event.type == QueryCacheEventType.added || event.type == QueryCacheEventType.updated) {
          final newResult = event.entry?.result as InfiniteQueryResult<T>?;
          if (newResult != null) {
            final q = InfiniteQueryResult<T>(
                key: cacheKey,
                status: newResult.status,
                data: newResult.data as List<T>,
                isFetching: newResult.isFetching,
                error: newResult.error,
                isFetchingNextPage: newResult.isFetchingNextPage);
            q.fetchNextPage = () => fetchNextPage(q);
            result.value = q;
          }
        } else if (event.type == QueryCacheEventType.refetch ||
            (event.type == QueryCacheEventType.refetchOnRestart &&
                (refetchOnRestart ?? queryClient.defaultOptions.queries.refetchOnRestart)) ||
            (event.type == QueryCacheEventType.refetchOnReconnect &&
                (refetchOnReconnect ?? queryClient.defaultOptions.queries.refetchOnReconnect))) {
          refetchPagesUpToCurrent();
        }
      } catch (e) {
        debugPrint(e.toString());
      }
    });

    return () {
      isMounted = false;
      unsubscribe();
      if (timer != null) {
        timer!.cancel();
      }
    };
  }, [enabled, ...queryKey]);

  result.value.fetchNextPage = () => fetchNextPage(result.value);
  return result.value;
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
  result.value.status = QueryStatus.pending;
  result.value.data = [];
}
