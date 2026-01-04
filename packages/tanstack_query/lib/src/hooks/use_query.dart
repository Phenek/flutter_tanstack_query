import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

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
  final options = useMemoized(
      () => QueryOptions<T>(
            queryFn: queryFn,
            queryKey: queryKey,
            staleTime: staleTime,
            enabled: enabled ?? queryClient.defaultOptions.queries.enabled,
            refetchOnRestart: refetchOnRestart,
            refetchOnReconnect: refetchOnReconnect,
          ),
      [queryClient, queryFn, staleTime, enabled, refetchOnRestart, refetchOnReconnect, cacheKey]);

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
