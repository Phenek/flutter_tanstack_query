import 'package:tanstack_query/tanstack_query.dart';

/// In-memory cache keyed by a serialized query key.
final cacheQuery = <String, CacheQuery<dynamic>>{};

/// Core client that owns the cache and provides utilities to invalidate,
/// set, and notify query data. Use `QueryClient.instance` for global access
/// when required by hooks and widgets.
class QueryClient {
  /// Global default options applied to queries and mutations.
  final DefaultOptions defaultOptions;

  /// Optional query cache that can be configured to receive lifecycle events.
  final QueryCache? queryCache;

  /// Optional mutation cache for mutation lifecycles.
  final MutationCache? mutationCache;
  final Map<String, List<QueryCacheListener>> _listeners = {};

  /// A globally available reference to the last constructed `QueryClient`.
  static late QueryClient instance;

  QueryClient(
      {this.defaultOptions = const DefaultOptions(),
      this.queryCache,
      this.mutationCache}) {
    instance = this;
  }

  // #region listeners
  /// Register a [listener] for changes to the cache entries matching [keys].
  void addListener(List<Object> keys, QueryCacheListener listener) {
    final cacheKey = queryKeyToCacheKey(keys);
    _listeners.putIfAbsent(cacheKey, () => []).add(listener);
  }

  /// Remove a previously registered listener for [keys].
  void removeListener(List<Object> keys, QueryCacheListener listener) {
    final cacheKey = queryKeyToCacheKey(keys);
    _listeners[cacheKey]?.remove(listener);
  }

  /// Broadcasts [newResult] to all listeners for the cache entry identified
  /// by [cacheKey] except the optional [excludeCallerId].
  void notifyUpdate(String cacheKey, dynamic newResult,
      {String? excludeCallerId}) {
    for (var listener in _listeners[cacheKey] ?? <QueryCacheListener>[]) {
      if (listener.id != excludeCallerId) {
        listener.listenUpdateCallBack(newResult);
      }
    }
  }

  /// Requests a refetch from all listeners of [cacheKey].
  void notifyRefetch(String cacheKey) {
    for (var listener in _listeners[cacheKey] ?? <QueryCacheListener>[]) {
      listener.refetchCallBack();
    }
  }

  /// Iterate listeners and trigger `refetchCallBack` for those configured
  /// to refetch on app restart.
  void refetchOnRestart() {
    _listeners.forEach((key, listenersList) {
      for (var listener in listenersList) {
        if (listener.refetchOnRestart ??
            defaultOptions.queries.refetchOnRestart) {
          listener.refetchCallBack();
        }
      }
    });
  }

  /// Iterate listeners and trigger `refetchCallBack` for those configured
  /// to refetch on reconnect.
  void refetchOnReconnect() {
    _listeners.forEach((key, listenersList) {
      for (var listener in listenersList) {
        if (listener.refetchOnReconnect ??
            defaultOptions.queries.refetchOnReconnect) {
          listener.refetchCallBack();
        }
      }
    });
  }
  // #endRegion listeners

  void invalidateQueries({List<Object>? queryKey, bool exact = false}) {
    // If queryKey is null we invalidate everything.
    if (queryKey == null) {
      final invalidatedKeys = cacheQuery.keys.toList();
      cacheQuery.clear();
      for (var key in invalidatedKeys) {
        notifyRefetch(key);
      }
      return;
    }

    if (exact) {
      final cacheKey = queryKeyToCacheKey(queryKey);
      cacheQuery.remove(cacheKey);
      notifyRefetch(cacheKey);
    } else {
      final cacheKey = queryKeyToCacheKey(queryKey);
      final List<String> invalidatedKeys = [];

      cacheQuery.removeWhere((key, value) {
        if (key.startsWith(cacheKey)) {
          invalidatedKeys.add(key);
          return true;
        }
        return false;
      });

      for (var key in invalidatedKeys) {
        notifyRefetch(key);
      }
    }
  }

  /// Synchronously updates the cached query data for [keys] using [updateFn].
  ///
  /// The [updateFn] receives the previous cached value (or `null`) and must
  /// return the new data which will be stored in the cache and broadcast to
  /// listeners.
  void setQueryData<T>(List<Object> keys, T Function(T? oldData) updateFn) {
    final cacheKey = queryKeyToCacheKey(keys);
    final oldEntry = cacheQuery[cacheKey];
    final oldData = oldEntry?.result.data as T?;
    final newData = updateFn(oldData);
    final queryResult = QueryResult(
        cacheKey, QueryStatus.success, newData, null,
        isFetching: false);

    cacheQuery[cacheKey] = CacheQuery(queryResult, DateTime.now());
    notifyUpdate(cacheKey, queryResult);
  }

  /// Synchronously updates cached infinite query data for [keys] using
  /// [updateFn]. The function receives the previous list of pages and must
  /// return the updated list to store in cache.
  void setQueryInfiniteData<T>(
      List<Object> keys, List<T> Function(List<T>? oldDatas) updateFn) {
    final cacheKey = queryKeyToCacheKey(keys);
    final oldEntry = cacheQuery[cacheKey];
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

    cacheQuery[cacheKey] = CacheQuery(queryResult, DateTime.now());
    notifyUpdate(cacheKey, queryResult);
  }

  /// Clears the entire in-memory cache and notifies listeners that cached
  /// values have been removed so widgets can react accordingly.
  void clear() {
    final keys = cacheQuery.keys.toList();
    cacheQuery.clear();
    for (var key in keys) {
      // Notify listeners that cache was cleared for this key. The UI layer will
      // interpret `null` or missing cache entries appropriately.
      notifyUpdate(key, null);
    }
  }
}
