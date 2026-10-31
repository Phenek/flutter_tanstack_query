import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';

/// Warms the cache for [queryKey] while a widget builds, without subscribing to it.
///
/// Port of `usePrefetchQuery`. It returns nothing and never rebuilds the widget:
/// the point is that a *later* `useQuery` on the same key finds the data already
/// there. Prefetch on the screen before the one that needs the data — a list
/// row, a marker tap — rather than on the screen that displays it.
///
/// Like the React version, the fetch is skipped when the key already has a cache
/// entry, so this is safe to call on every build.
void usePrefetchQuery<T>({
  required List<Object> queryKey,
  required Future<T> Function() queryFn,
  double? staleTime,
  int? gcTime,
  dynamic retry,
  dynamic retryDelay,
}) {
  final queryClient = useQueryClient();
  final cacheKey = queryKeyToCacheKey(queryKey);

  useMemoized(() {
    if (queryClient.getQueryState<T>(queryKey) == null) {
      queryClient.prefetchQuery<T>(
        queryKey: queryKey,
        queryFn: queryFn,
        staleTime: staleTime,
        gcTime: gcTime,
        retry: retry,
        retryDelay: retryDelay,
      );
    }
    return null;
  }, [queryClient, cacheKey]);
}

/// Warms the cache for an infinite query's first page.
///
/// Port of `usePrefetchInfiniteQuery`. Same contract as [usePrefetchQuery]: no
/// return value, no subscription, skipped when the key is already cached.
void usePrefetchInfiniteQuery<T>({
  required List<Object> queryKey,
  required Future<T?> Function(int pageParam) queryFn,
  required int initialPageParam,
  int? Function(T lastResult)? getNextPageParam,
  int? Function(T firstResult)? getPreviousPageParam,
  double? staleTime,
  int? gcTime,
  dynamic retry,
  dynamic retryDelay,
}) {
  final queryClient = useQueryClient();
  final cacheKey = queryKeyToCacheKey(queryKey);

  useMemoized(() {
    if (queryClient.getQueryState<List<T>>(queryKey) == null) {
      queryClient.prefetchInfiniteQuery<T>(
        queryKey: queryKey,
        queryFn: queryFn,
        initialPageParam: initialPageParam,
        getNextPageParam: getNextPageParam,
        getPreviousPageParam: getPreviousPageParam,
        staleTime: staleTime,
        gcTime: gcTime,
        retry: retry,
        retryDelay: retryDelay,
      );
    }
    return null;
  }, [queryClient, cacheKey]);
}
