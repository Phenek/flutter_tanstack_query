import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Subscribe to a query identified by [queryKey] and manage its lifecycle.
///
/// [queryFn] is called to fetch data. Returns a [QueryResult<T>] that contains
/// `data`, `error`, and `status` flags to drive UI states.
///
/// Parameters:
/// - [queryKey] (required): A `List<Object>` uniquely identifying the query.
/// - [queryFn] (required): Function returning a `Future<T>` used to fetch data.
/// - [gcTime]: Garbage-collection time in milliseconds for this query's cache
///   entry. When all observers are removed, the query will be removed from the
///   cache after `gcTime` ms. A value <= 0 disables GC. If unspecified, the
///   client default is used.
/// - [enabled]: When `false`, automatic fetching is disabled until `true`.
///   Defaults to `queryClient.defaultOptions.queries.enabled`.
/// - [initialData]: T | () => T — initial value that is persisted to cache if
///   provided and the cache is empty. It is considered stale by default
///   unless `initialDataUpdatedAt` is set.
/// - [initialDataUpdatedAt]: int (ms) | () => int | null — timestamp for when
///   the initialData was last updated; used together with staleTime to
///   determine if a refetch is required on mount.
/// - [placeholderData]: T | (previousValue, previousQuery) => T — observer-only
///   placeholder shown while the query is pending; not persisted to cache.
/// - [refetchOnMount]: When `true`, refetch when the observer mounts.
/// - [refetchOnReconnect]: When `true`, refetch query on reconnect.
/// - [refetchOnWindowFocus]: When `true`, refetch query on window/app focus.
/// - [retry]: Controls retry behavior; same accepted forms as in `useMutation`:
///   `false`, `true`, an `int`, or a function `(failureCount, error) => bool`.
/// - [retryOnMount]: If `false`, a query that currently has an error will not
///   attempt to retry when mounted.
/// - [retryDelay]: Milliseconds between retries, or a function
///   `(attempt, error) => int` returning the delay in ms.
/// - [staleTime]: Time in **milliseconds** after which cached data is considered
///   stale and will be refetched on next access. If null, the client's default
///   `staleTime` is used.
///
/// Returns:
/// The current [QueryResult<T>] for the query
QueryResult<T> useQuery<T>(
    {required List<Object> queryKey,
    required Future<T> Function() queryFn,
    int? gcTime,
    bool? enabled,
    Object? initialData,
    Object? initialDataUpdatedAt,
    Object? placeholderData,
    bool? refetchOnMount,
    bool? refetchOnReconnect,
    bool? refetchOnWindowFocus,
    dynamic retry,
    bool? retryOnMount,
    dynamic retryDelay,
    double? staleTime}) {
  final queryClient = useQueryClient();
  final cacheKey = queryKeyToCacheKey(queryKey);

  // Build initial QueryOptions and create an observer lazily
  final options = useMemoized(
      () => QueryOptions<T>(
            queryFn: queryFn,
            queryKey: queryKey,
            staleTime: staleTime,
            enabled: enabled ?? queryClient.defaultOptions.queries.enabled,
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
  // Observer follows the same pattern as useInfiniteQuery: create once and
  // keep it in sync via setOptions to avoid complex lifecycle code in the hook.
  // Create the observer once for this cache key and keep it in sync via setOptions
  final observer = useMemoized<QueryObserver<T, Object?, T>>(
      () => QueryObserver<T, Object?, T>(queryClient, options),
      [queryClient, cacheKey]);

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
      } catch (_) {}
    });

    return () {
      unsubscribe();
    };
  }, [observer, cacheKey]);

  return state.value;
}
