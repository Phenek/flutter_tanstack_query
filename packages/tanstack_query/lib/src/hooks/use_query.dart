import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Subscribe to a query identified by [queryKey] and manage its lifecycle.
///
/// [queryFn] is called to fetch data. Returns a [QueryResult<T>] that contains
/// `data`, `error`, and `status` flags to drive UI states.
///
/// Parameters:
/// - [queryFn] (required): Function returning a `Future<T>` used to fetch data.
/// - [queryKey] (required): A `List<Object>` uniquely identifying the query.
/// - [staleTime]: Time in **milliseconds** after which cached data is considered
///   stale and will be refetched on next access. If null, the client's default
///   `staleTime` is used.
/// - [enabled]: When `false`, automatic fetching is disabled until `true`.
///   Defaults to `queryClient.defaultOptions.queries.enabled`.
/// - [refetchOnRestart]: When `true`, refetches on app restart.
/// - [refetchOnReconnect]: When `true`, refetches on reconnect.
/// - [gcTime]: Garbage-collection time in milliseconds for this query's cache
///   entry. When all observers are removed, the query will be removed from the
///   cache after `gcTime` ms. A value <= 0 disables GC. If unspecified, the
///   client default is used.
/// - [retry]: Controls retry behavior; same accepted forms as in `useMutation`:
///   `false`, `true`, an `int`, or a function `(failureCount, error) => bool`.
/// - [retryOnMount]: If `false`, a query that currently has an error will not
///   attempt to retry when mounted.
/// - [retryDelay]: Milliseconds between retries, or a function
///   `(attempt, error) => int` returning the delay in ms.
///
/// Returns:
/// The current [QueryResult<T>] for the query (fields include `data`, `error`,
/// and `status`).
QueryResult<T> useQuery<T>(
    {required Future<T> Function() queryFn,
    required List<Object> queryKey,
    double? staleTime,
    bool? enabled,
    bool? refetchOnRestart,
    bool? refetchOnReconnect,
    int? gcTime,
    dynamic retry,
    bool? retryOnMount,
    dynamic retryDelay}) {
  final queryClient = useQueryClient();
  final cacheKey = queryKeyToCacheKey(queryKey);

  // Build initial QueryOptions and create an observer lazily
  final options = useMemoized(
      () => QueryOptions<T>(
            queryFn: queryFn,
            queryKey: queryKey,
            staleTime: staleTime,
            enabled: enabled ?? queryClient.defaultOptions.queries.enabled,
            refetchOnRestart: refetchOnRestart,
            refetchOnReconnect: refetchOnReconnect,
            gcTime: gcTime,
            retry: retry,
            retryOnMount: retryOnMount,
            retryDelay: retryDelay,
          ),
      [queryClient, queryFn, staleTime, enabled, refetchOnRestart, refetchOnReconnect, gcTime, retry, retryOnMount, retryDelay, cacheKey]);

  // Observer follows the same pattern as useInfiniteQuery: create once and
  // keep it in sync via setOptions to avoid complex lifecycle code in the hook.
  // Create the observer once for this cache key and keep it in sync via setOptions
  final observer = useMemoized<QueryObserver<T, Object?, T>>(
      () => QueryObserver<T, Object?, T>(queryClient, options), [queryClient, cacheKey]);

  // Keep observer options in sync when any option changes
  useEffect(() {
    observer.setOptions(options);
    return null;
  }, [observer, options]);

  // use the observer's result directly (it already exposes a `QueryResult<T>`)
  final state = useState<QueryResult<T>>(observer.getCurrentResult());

  useEffect(() {
    // Subscribe with a typed listener matching QueryObserver's contract
    final unsubscribe = observer.subscribe((QueryResult<T> res) {
      try {
        state.value = res;
        print('useQuery - status ${state.value.status} value: ${state.value}');
      } catch (_) {}
    });

    // initialize
    // state.value = observer.getCurrentResult();
    // print('initialize useQuery - status ${state.value.status} value: ${state.value}');

    return () {
      unsubscribe();
      print('dispose useQuery - status ${state.value.status} value: ${state.value}');
    };
  }, [observer, cacheKey]);

  return state.value;
}
