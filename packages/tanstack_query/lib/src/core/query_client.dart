import 'package:tanstack_query/tanstack_query.dart';

/// Core client that owns the cache and provides utilities to invalidate,
/// set, and notify query data. Prefer obtaining the active client via
/// `useQueryClient()` (with `QueryClientProvider`) in hooks and widgets; a
class QueryClient {
  /// Global default options applied to queries and mutations.
  final DefaultOptions defaultOptions;

  /// Query cache instance owned by this client (never null).
  final QueryCache queryCache;

  /// Mutation cache for mutation lifecycles (owned by this client).
  final MutationCache mutationCache;

  /// A globally available reference to the last constructed `QueryClient`.
  static late QueryClient instance;

  QueryClient(
      {this.defaultOptions = const DefaultOptions(),
      QueryCache? queryCache,
      MutationCache? mutationCache})
      : queryCache = queryCache ?? QueryCache(config: QueryCacheConfig()),
        mutationCache =
            mutationCache ?? MutationCache(config: MutationCacheConfig()) {
    instance = this;
  }

  /// Trigger refetch behavior for queries configured to refetch on restart.
  void refetchOnRestart() {
    queryCache.refetchOnRestart();
  }

  /// Trigger refetch behavior for queries configured to refetch on reconnect.
  void refetchOnReconnect() {
    queryCache.refetchOnReconnect();
  }

  void invalidateQueries({List<Object>? queryKey, bool exact = false}) {
    // If queryKey is null we invalidate everything.
    if (queryKey == null) {
      final invalidatedKeys = queryCache.keys.toList();
      queryCache.clear();
      for (var key in invalidatedKeys) {
        queryCache.refetchByCacheKey(key);
      }
      return;
    }

    if (exact) {
      final cacheKey = queryKeyToCacheKey(queryKey);
      queryCache.remove(cacheKey);
      queryCache.refetchByCacheKey(cacheKey);
    } else {
      final cacheKey = queryKeyToCacheKey(queryKey);
      final List<String> invalidatedKeys = [];

      queryCache.removeWhere((key, value) {
        if (key.startsWith(cacheKey)) {
          invalidatedKeys.add(key);
          return true;
        }
        return false;
      });

      for (var key in invalidatedKeys) {
        queryCache.refetchByCacheKey(key);
      }
    }
  }

  /// Synchronously updates the cached query data for [keys] using [updateFn].
  ///
  /// The [updateFn] receives the previous cached value (or `null`) and must
  /// return the new data which will be stored in the cache
  void setQueryData<T>(List<Object> keys, T Function(T? oldData) updateFn) {
    final cacheKey = queryKeyToCacheKey(keys);
    final oldEntry = queryCache[cacheKey];
    final oldData = oldEntry?.result.data as T?;
    final newData = updateFn(oldData);
    final queryResult = QueryResult(
        cacheKey,
        QueryStatus.success,
        newData,
        null,
        isFetching: false,
        dataUpdatedAt: DateTime.now().millisecondsSinceEpoch,
        isPlaceholderData: false);

    queryCache[cacheKey] = QueryCacheEntry(queryResult, DateTime.now());
  }

  /// Synchronously updates cached infinite query data for [keys] using
  /// [updateFn]. The function receives the previous list of pages and must
  /// return the updated list to store in cache.
  void setQueryInfiniteData<T>(
      List<Object> keys, List<T> Function(List<T>? oldDatas) updateFn) {
    final cacheKey = queryKeyToCacheKey(keys);
    final oldEntry = queryCache[cacheKey];
    final oldDatas = oldEntry?.result.data as List<T>? ?? <T>[];
    final newDatas = updateFn(oldDatas);

    final queryResult = InfiniteQueryResult(
        key: cacheKey,
        status: QueryStatus.success,
        data: newDatas as List<Object>,
        isFetching: false,
        error: null,
        isFetchingNextPage: false,
        fetchNextPage: () async {});

    // annotate dataUpdatedAt on the stored result
    try {
      queryResult.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;
      queryResult.isPlaceholderData = false;
    } catch (_) {}

    queryCache[cacheKey] = QueryCacheEntry(queryResult, DateTime.now());
  }

  /// Clears the entire in-memory cache and notifies listeners that cached
  /// values have been removed so widgets can react accordingly.
  void clear() {
    queryCache.clear();
  }
}
