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

  /// Trigger refetch behavior for queries configured to refetch on window/app focus.
  void refetchOnWindowFocus() {
    queryCache.refetchOnWindowFocus();
  }

  /// Trigger refetch behavior for queries configured to refetch on reconnect.
  void refetchOnReconnect() {
    queryCache.refetchOnReconnect();
  }

  // Tracking how many times the client was mounted (e.g. provider instances)
  int _mountCount = 0;
  void Function()? _unsubscribeFocus;
  void Function()? _unsubscribeOnline;

  /// Mount the client to start listening to focus/online events. The
  /// QueryClientProvider should call [mount] on mount and [unmount] on
  /// dispose.
  void mount() {
    _mountCount++;
    if (_mountCount != 1) return;

    _unsubscribeFocus = focusManager.subscribe((focused) async {
      if (focused) {
        await resumePausedMutations();
        queryCache.onFocus();
      }
    });

    _unsubscribeOnline = onlineManager.subscribe((online) async {
      if (online) {
        await resumePausedMutations();
        queryCache.onOnline();
      }
    });
  }

  /// Stop listening to global focus/online events when the client is
  /// unmounted (e.g. provider disposed).
  void unmount() {
    _mountCount--;
    if (_mountCount != 0) return;

    _unsubscribeFocus?.call();
    _unsubscribeFocus = null;

    _unsubscribeOnline?.call();
    _unsubscribeOnline = null;
  }

  /// Resume any paused mutations; placeholder for environments that persist
  /// mutations across app restarts or offline periods.
  Future<void> resumePausedMutations() async {
    // No-op for now; implement if mutation persistence is added.
    return;
  }

  void invalidateQueries({List<Object>? queryKey, bool exact = false}) {
    // If queryKey is null we invalidate everything.
    if (queryKey == null) {
      // Snapshot all Query instances BEFORE clear() destroys them.
      final queries = queryCache.getAllQueries();
      queryCache.clear();
      // Notify observers on the (now-destroyed) old queries. Each observer's
      // refetch() calls _updateQuery() which builds a fresh Query in the cache.
      for (var q in queries) {
        q.notifyObserversRefetch();
      }
      return;
    }

    if (exact) {
      final cacheKey = queryKeyToCacheKey(queryKey);
      final q = queryCache.getQuery(cacheKey);
      if (q != null) {
        queryCache.remove(q);
        // Notify observers on the removed query; they'll rebuild via _updateQuery().
        q.notifyObserversRefetch();
      }
    } else {
      final cacheKey = queryKeyToCacheKey(queryKey);
      // Snapshot matching Query instances BEFORE removeWhere() destroys them.
      final matchingQueries = queryCache.keys
          .where((k) => k.startsWith(cacheKey))
          .map((k) => queryCache.getQuery(k))
          .whereType<Query>()
          .toList();

      queryCache.removeWhere((key, value) => key.startsWith(cacheKey));

      for (var q in matchingQueries) {
        q.notifyObserversRefetch();
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
        cacheKey, QueryStatus.success, newData, null,
        isFetching: false,
        dataUpdatedAt: DateTime.now().millisecondsSinceEpoch,
        isPlaceholderData: false);

    queryCache[cacheKey] = QueryCacheEntry(queryResult, DateTime.now());
    // Mirrors React: notify observers directly through the Query object
    // (setData -> dispatch -> onQueryUpdate), not via cache events.
    queryCache.getQuery(cacheKey)?.notifyObservers();
  }

  /// Synchronously updates cached infinite query data for [keys] using
  /// [updateFn]. The function receives the previous [InfiniteData] and must
  /// return the updated [InfiniteData] to store in cache.
  void setQueryInfiniteData<T, TPageParam>(List<Object> keys,
      InfiniteData<T, TPageParam> Function(InfiniteData<T, TPageParam>? oldData)
          updateFn) {
    final cacheKey = queryKeyToCacheKey(keys);
    final oldEntry = queryCache[cacheKey];
    final oldData = oldEntry?.result.data as InfiniteData<T, TPageParam>?;
    final newData = updateFn(oldData);

    final queryResult = InfiniteQueryResult<T, TPageParam>(
      key: cacheKey,
      status: QueryStatus.success,
      data: newData,
      isFetching: false,
      error: null,
      isFetchingNextPage: false,
      fetchNextPage: null,
    );

    // annotate dataUpdatedAt on the stored result
    try {
      queryResult.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;
      queryResult.isPlaceholderData = false;
    } catch (_) {}

    queryCache[cacheKey] = QueryCacheEntry(queryResult, DateTime.now());
    // Mirrors React: notify observers directly through the Query object.
    queryCache.getQuery(cacheKey)?.notifyObservers();
  }

  /// Clears the entire in-memory cache and notifies listeners that cached
  /// values have been removed so widgets can react accordingly.
  void clear() {
    queryCache.clear();
  }
}
