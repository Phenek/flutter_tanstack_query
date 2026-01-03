import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/material.dart';

/// Subscribes to a query identified by [queryKey] and manages its lifecycle.
///
/// [queryFn] is called to fetch data. Returns a [QueryResult<T>] that contains
/// `data`, `error`, and `status` flags that can be used by widgets.
///
/// Parameters:
/// - [queryFn]: Function that returns a `Future<T>` with the data.
/// - [queryKey]: A list of objects uniquely identifying the query.
/// - [staleTime]: Duration in milliseconds after which cached data is considered
///   stale and will be refetched when `useQuery` runs (default behavior uses
///   `DefaultOptions`).
/// - [enabled]: If `false`, disables automatic fetching until set to `true`.
/// - [refetchOnRestart]: When `true`, refetches on app restart.
/// - [refetchOnReconnect]: When `true`, refetches on reconnect.
///
/// Returns a [QueryResult<T>] representing the current query state and data.
QueryResult<T> useQuery<T>(
    {required Future<T> Function() queryFn,
    required List<Object> queryKey,
    double? staleTime,
    bool? enabled,
    bool? refetchOnRestart,
    bool? refetchOnReconnect}) {
  final queryClient = useQueryClient();
  final cacheKey = queryKeyToCacheKey(queryKey);
  var cacheEntry = queryClient.queryCache[cacheKey];
  var isFirstRequest = useRef(true);
  final callerId = useMemoized(() => DateTime.now().microsecondsSinceEpoch.toString(), []);
  final result = useState<QueryResult<T>>(
      cacheEntry != null && cacheEntry.result.isSuccess
          ? QueryResult<T>(cacheKey, cacheEntry.result.status,
              cacheEntry.result.data as T?, cacheEntry.result.error,
              isFetching: cacheEntry.result.isFetching)
          : QueryResult<T>(cacheKey, QueryStatus.pending, null, null,
              isFetching: false));
  var isMounted = true;

  void updateCache(QueryResult<T> queryResult) {
    // If the query returned null *and* it is a successful result, remove
    // the existing cache entry. For error results we still persist the
    // failing result so subscribers can reflect the error state.
    if (queryResult.data == null && queryResult.isSuccess && queryClient.queryCache.containsKey(cacheKey)) {
      queryClient.queryCache.remove(cacheKey);
      return;
    }

    queryClient.queryCache.set(cacheKey, QueryCacheEntry(queryResult, DateTime.now()), callerId: callerId);
  }

  void fetch() {
    isFirstRequest.value = false;
    var cacheEntry = queryClient.queryCache[cacheKey];
    var shouldUpdateTheCache = false;

    // If there's no cache entry, or there is no currently running fetch (or it finished/errored),
    // create a new fetch. This ensures we can refetch stale data even when cached data exists.
    if (cacheEntry == null ||
        (cacheEntry.queryFnRunning == null ||
            cacheEntry.queryFnRunning!.isCompleted ||
            cacheEntry.queryFnRunning!.hasError)) {
      var queryResult = QueryResult<T>(
          cacheKey, QueryStatus.pending, null, null,
          isFetching: true);

      var futureFetch = TrackedFuture(queryFn());

      queryClient.queryCache[cacheKey] = cacheEntry = QueryCacheEntry<T>(
          queryResult, DateTime.now(),
          queryFnRunning: futureFetch);

      shouldUpdateTheCache = true;
    }
    // Loading State: cacheEntry has a Running Function, set result to propagate the loading state
    var futureFetch = cacheEntry.queryFnRunning;
    if (isMounted) result.value = cacheEntry.result as QueryResult<T>;

    futureFetch?.then((value) {
      final queryResult = QueryResult<T>(
          cacheKey, QueryStatus.success, value, null,
          isFetching: false);
      if (isMounted) result.value = queryResult;
      if (shouldUpdateTheCache) updateCache(queryResult);

      queryClient.queryCache.config.onSuccess?.call(value);
    }).catchError((e) {
      final queryResult = QueryResult<T>(cacheKey, QueryStatus.error, null, e,
          isFetching: false);
      if (isMounted) result.value = queryResult;
      if (shouldUpdateTheCache) updateCache(queryResult);

      queryClient.queryCache.config.onError?.call(e);
    });
  }

  useEffect(() {
    if ((enabled ?? queryClient.defaultOptions.queries.enabled) == false) {
      return null;
    }

    bool shouldFetch = result.value.data == null ||
        result.value.isError ||
        result.value.key != cacheKey;

    // If the current value is an error and this is not the first request,
    // avoid immediately re-fetching (prevents a fast retry loop during error handling).
    if (result.value.isError && isFirstRequest.value == false) {
      shouldFetch = false;
    }

    //Check StaleTime here
    if (isFirstRequest.value == true &&
        staleTime != double.infinity &&
        cacheEntry != null) {
      staleTime ??= 0;
      final isStale =
          DateTime.now().difference(cacheEntry.timestamp).inMilliseconds >
              staleTime!;
      shouldFetch = shouldFetch || isStale;
    }

    if (shouldFetch) {
      fetch();
    }


    final unsubscribe = queryClient.queryCache.subscribe((event) {

      // Only care about events for our cacheKey
      if (event.cacheKey != cacheKey) return;
      // Ignore events originating from this caller
      if (event.callerId != null && event.callerId == callerId) return;

      try {
        if (event.type == QueryCacheEventType.removed) {
          result.value = QueryResult<T>(
              cacheKey, QueryStatus.pending, null, null,
              isFetching: false);
        } else if (event.type == QueryCacheEventType.added || event.type == QueryCacheEventType.updated) {
          final newResult = event.entry?.result as QueryResult<T>?;
          if (newResult != null) {
            result.value = QueryResult<T>(
                cacheKey, newResult.status, newResult.data, newResult.error,
                isFetching: newResult.isFetching);
          }
        } else if (event.type == QueryCacheEventType.refetch ||
            (event.type == QueryCacheEventType.refetchOnRestart &&
                (refetchOnRestart ?? queryClient.defaultOptions.queries.refetchOnRestart)) ||
            (event.type == QueryCacheEventType.refetchOnReconnect &&
                (refetchOnReconnect ?? queryClient.defaultOptions.queries.refetchOnReconnect))) {
          fetch();
        }
      } catch (e) {
        debugPrint(e.toString());
      }
    });

    return () {
      isMounted = false;
      unsubscribe();
    };
  }, [enabled, ...queryKey]);

  return result.value;
}
