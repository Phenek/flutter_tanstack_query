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

  // Build initial QueryOptions and create an observer lazily
  final options = QueryOptions<T>(
    queryFn: queryFn,
    queryKey: queryKey,
    staleTime: staleTime,
    enabled: enabled ?? queryClient.defaultOptions.queries.enabled,
    refetchOnRestart: refetchOnRestart,
    refetchOnReconnect: refetchOnReconnect,
  );

  final observer = useMemoized<QueryObserver<T, Object?, T>>(() =>
      QueryObserver<T, Object?, T>(queryClient, options), [queryClient]);

  // keep observer options in sync
  useEffect(() {
    observer.setOptions(QueryOptions<T>(
      queryFn: queryFn,
      queryKey: queryKey,
      staleTime: staleTime,
      enabled: enabled ?? queryClient.defaultOptions.queries.enabled,
      refetchOnRestart: refetchOnRestart,
      refetchOnReconnect: refetchOnReconnect,
    ));
    return null;
  }, [observer, queryFn, ...queryKey, staleTime, enabled, refetchOnRestart, refetchOnReconnect]);

  // Map observer result -> QueryResult<T>
  QueryResult<T> mapObserverResult(QueryObserverResult<T, Object?> res) {
    final status = res.status == 'success'
        ? QueryStatus.success
        : (res.status == 'error' ? QueryStatus.error : QueryStatus.pending);

    return QueryResult<T>(cacheKey, status, res.data, res.error,
        isFetching: res.isFetching);
  }

  final resultState = useState<QueryResult<T>>(mapObserverResult(observer.getCurrentResult()));

  // Reintroduce the old fetch implementation to match previous behavior and
  // ensure tests relying on immediate fetching continue to behave.
  void fetch() {
    var cacheEntry = queryClient.queryCache[cacheKey];
    var shouldUpdateTheCache = false;

    if (cacheEntry == null ||
        (cacheEntry.queryFnRunning == null ||
            cacheEntry.queryFnRunning!.isCompleted ||
            cacheEntry.queryFnRunning!.hasError)) {
      var queryResult = QueryResult<T>(cacheKey, QueryStatus.pending, null, null, isFetching: true);

      var futureFetch = TrackedFuture<T>(queryFn());

      queryClient.queryCache[cacheKey] = cacheEntry = QueryCacheEntry<T>(queryResult, DateTime.now(), queryFnRunning: futureFetch);

      shouldUpdateTheCache = true;
    }

    var futureFetch = cacheEntry?.queryFnRunning;
    // update local state to reflect loading
    if (futureFetch != null) resultState.value = cacheEntry!.result as QueryResult<T>;

    futureFetch?.then((value) {
      final queryResult = QueryResult<T>(cacheKey, QueryStatus.success, value, null, isFetching: false);
      resultState.value = queryResult;
      if (shouldUpdateTheCache) {
        queryClient.queryCache[cacheKey] = QueryCacheEntry<T>(queryResult, DateTime.now());
      }

      queryClient.queryCache.config.onSuccess?.call(value);
    }).catchError((e) {
      final queryResult = QueryResult<T>(cacheKey, QueryStatus.error, null, e, isFetching: false);
      resultState.value = queryResult;
      if (shouldUpdateTheCache) {
        queryClient.queryCache[cacheKey] = QueryCacheEntry<T>(queryResult, DateTime.now());
      }

      queryClient.queryCache.config.onError?.call(e);
    });
  }

  useEffect(() {
    // Determine whether an initial fetch should run — mirror previous logic
    final entry = queryClient.queryCache[cacheKey];

    final resolvedEnabled = enabled ?? queryClient.defaultOptions.queries.enabled;

    var shouldFetch = false;

    if (resolvedEnabled) {
      shouldFetch = resultState.value.data == null || resultState.value.isError || resultState.value.key != cacheKey;

      // Check stale on first mount: if we have cached entry and it's older than staleTime, fetch
      if (entry != null && staleTime != double.infinity) {
        final isStale = DateTime.now().difference(entry.timestamp).inMilliseconds > (staleTime ?? 0);
        shouldFetch = shouldFetch || isStale;
      }

      // If current value is an error, we still allow fetching once (prevents a fast retry loop elsewhere)
      if (resultState.value.isError) {
        shouldFetch = true;
      }
    }

    if (shouldFetch) {
      fetch();
    }

    final unsubscribe = observer.subscribe((res) {
      resultState.value = mapObserverResult(res as QueryObserverResult<T, Object?>);
    });

    // initialize from observer
    resultState.value = mapObserverResult(observer.getCurrentResult());

    // Also subscribe to cache events for compatibility with the existing behavior
    final callerId = DateTime.now().microsecondsSinceEpoch.toString();
    final cacheUnsub = queryClient.queryCache.subscribe((event) {
      if (event.cacheKey != cacheKey) return;
      if (event.callerId != null && event.callerId == callerId) return;

      try {
        if (event.type == QueryCacheEventType.removed) {
          resultState.value = QueryResult<T>(cacheKey, QueryStatus.pending, null, null, isFetching: false);
        } else if (event.type == QueryCacheEventType.added || event.type == QueryCacheEventType.updated) {
          final newResult = event.entry?.result as QueryResult<T>?;
          if (newResult != null) {
            resultState.value = QueryResult<T>(cacheKey, newResult.status, newResult.data, newResult.error, isFetching: newResult.isFetching);
          }
        } else if (event.type == QueryCacheEventType.refetch || (event.type == QueryCacheEventType.refetchOnRestart && (refetchOnRestart ?? queryClient.defaultOptions.queries.refetchOnRestart)) || (event.type == QueryCacheEventType.refetchOnReconnect && (refetchOnReconnect ?? queryClient.defaultOptions.queries.refetchOnReconnect))) {
          observer.refetch();
        }
      } catch (e) {
        debugPrint(e.toString());
      }
    });

    return () {
      unsubscribe();
      cacheUnsub();
    };
  }, [observer, ...queryKey]);

  return resultState.value;
}
