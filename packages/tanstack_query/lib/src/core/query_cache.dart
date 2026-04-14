import 'types.dart';
import 'utils.dart';
import 'subscribable.dart';
import 'query.dart';
import 'query_client.dart';
import 'query_types.dart';

/// Configuration callbacks for query cache events like `onError`, `onSuccess` and `onSettled`.
class QueryCacheConfig {
  /// Called when a query fetch results in an error.
  final void Function(dynamic error)? onError;

  /// Called when a query fetch completes successfully.
  final void Function(dynamic data)? onSuccess;

  /// Called when a query settles (either success or error).
  final void Function(dynamic data, dynamic error)? onSettled;

  const QueryCacheConfig({this.onError, this.onSuccess, this.onSettled});
}

/// The kinds of events emitted by the query cache.
enum QueryCacheEventType {
  added,
  updated,
  removed,
  refetch,
  refetchOnWindowFocus,
  refetchOnReconnect,
}

/// Listener signature for cache-level notifications.
typedef QueryCacheListener = void Function(QueryCacheNotifyEvent event);

/// A notification event emitted by `QueryCache`.
class QueryCacheNotifyEvent {
  final QueryCacheEventType type;
  final String? cacheKey;
  final QueryCacheEntry? entry;
  final String? callerId;

  QueryCacheNotifyEvent(this.type, this.cacheKey, this.entry, {this.callerId});

  @override
  String toString() =>
      'QueryCacheNotifyEvent(type: $type, cacheKey: $cacheKey, entry: $entry, callerId: $callerId)';
}

/// A cache entry storing the last query [result], a [timestamp] and optionally
/// a running [queryFnRunning] future.
///
/// - `result`: The last stored `QueryResult` or `InfiniteQueryResult` produced
///   by the UI layer.
/// - `timestamp`: When the value was cached (used to compute staleness).
/// - `queryFnRunning`: If non-null, a `TrackedFuture` representing an in-flight
///   fetch for this key.
class QueryCacheEntry<T> {
  final dynamic
      result; // can be QueryResult/InfiniteQueryResult from flutter layer
  final DateTime timestamp;
  TrackedFuture<T>? queryFnRunning;

  QueryCacheEntry(this.result, this.timestamp, {this.queryFnRunning});

  @override
  String toString() =>
      'QueryCacheEntry(result: $result, timestamp: $timestamp, running: $queryFnRunning)';
}

/// Query cache that stores cache entries and provides utilities to
/// find/subscribe/clear entries. It is intended to be owned by a `QueryClient` instance.

class QueryCache extends Subscribable<QueryCacheListener> {
  /// Configuration containing callbacks for query lifecycle events.
  final QueryCacheConfig config;

  final Map<String, QueryCacheEntry<dynamic>> _cache = {};

  // Map of built Query instances by cache key
  final Map<String, dynamic> _queries = {};

  QueryCache({this.config = const QueryCacheConfig()});

  QueryCacheEntry? operator [](String key) => _cache[key];
  void operator []=(String key, QueryCacheEntry value) => set(key, value);
  bool containsKey(String key) => _cache.containsKey(key);

  Iterable<String> get keys => _cache.keys;

  /// Set or update a cache entry and notify listeners.
  ///
  /// Emits an `added` event when the key did not previously exist, otherwise
  /// `updated` when replacing an existing entry.
  void set(String key, QueryCacheEntry value, {String? callerId}) {
    final existed = _cache.containsKey(key);
    _cache[key] = value;
    _notifyListeners(QueryCacheNotifyEvent(
        existed ? QueryCacheEventType.updated : QueryCacheEventType.added,
        key,
        value,
        callerId: callerId));
  }

  /// Remove a query and its cache entry by Query object identity.
  ///
  /// Mirrors React's QueryCache.remove(query): only deletes the cache entry
  /// and _queries slot when the registered instance IS the passed query.
  /// This prevents orphaned Query instances (e.g., left over after a clear()
  /// + reload()) from evicting a newer Query that took over the same key.
  void remove(Query query, {String? callerId}) {
    final queryInMap = _queries[query.cacheKey];
    if (queryInMap == null) return;

    // Destroy the passed query (clears its GC timer, cancels retryer).
    // This is always safe regardless of identity — we always want to stop
    // orphaned queries from doing further work.
    try {
      query.destroy();
    } catch (_) {}

    // Only delete the registered slot, fire the notification, and remove the
    // cache entry when the identity matches — mirrors React's
    // `if (queryInMap === query)` guard.
    //
    // Unlike React, Dart observers subscribe to QueryCache events directly
    // (via _subscribeToCache), so we must NOT fire a `removed` notification
    // for orphaned queries: an orphaned Q1 calling remove(Q1) when Q2 is the
    // registered instance must be a silent no-op to avoid resetting live
    // observers to pending state.
    if (identical(queryInMap, query)) {
      _queries.remove(query.cacheKey);
      _cache.remove(query.cacheKey);
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.removed, query.cacheKey, null,
          callerId: callerId));
    }
  }

  /// Remove entries for which [test] returns true, and notify listeners for each removed entry.
  void removeWhere(bool Function(String, QueryCacheEntry) test) {
    final removedEntries = <String, QueryCacheEntry>{};
    _cache.removeWhere((k, v) {
      final shouldRemove = test(k, v);
      if (shouldRemove) removedEntries[k] = v;
      return shouldRemove;
    });
    for (var entry in removedEntries.entries) {
      // If there was a built Query instance for this key, destroy and remove it.
      if (_queries.containsKey(entry.key)) {
        final q = _queries.remove(entry.key);
        try {
          if (q != null && q is Query) q.destroy();
        } catch (_) {}
      }
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.removed, entry.key, entry.value));
    }
  }

  /// Request a refetch for all cache entries matching [queryKey].
  ///
  /// Mirrors React: notify observers directly through the Query object rather
  /// than via cache events. Also fires a cache event for external subscribers.
  void refetch(List<Object> queryKey, {String? callerId}) {
    final cacheKey = queryKeyToCacheKey(queryKey);
    for (var k in _cache.keys.where((k) => k.startsWith(cacheKey)).toList()) {
      // Direct observer notification through Query (React pattern).
      getQuery(k)?.notifyObserversRefetch();
      // Cache event retained for external cache subscribers.
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.refetch, k, _cache[k],
          callerId: callerId));
    }
  }

  /// Request a refetch for a specific cache key.
  ///
  /// Mirrors React: notify observers directly through the Query object rather
  /// than via cache events. Also fires a cache event for external subscribers.
  void refetchByCacheKey(String cacheKey, {String? callerId}) {
    // Direct observer notification through Query (React pattern).
    getQuery(cacheKey)?.notifyObserversRefetch();
    // Cache event retained for external cache subscribers.
    _notifyListeners(QueryCacheNotifyEvent(
        QueryCacheEventType.refetch, cacheKey, _cache[cacheKey],
        callerId: callerId));
  }

  /// Trigger refetch events for all cache entries when window/app focus occurs.
  void refetchOnWindowFocus() {
    for (var k in _cache.keys) {
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.refetchOnWindowFocus, k, _cache[k]));
    }
  }

  /// Trigger refetch events for all cache entries when the connection is re-established.
  void refetchOnReconnect() {
    for (var k in _cache.keys) {
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.refetchOnReconnect, k, _cache[k]));
    }
  }

  /// Notify each built Query instance that the app/window gained focus so
  /// they can decide whether to refetch.
  void onFocus() {
    for (var q in _queries.values) {
      try {
        if (q != null && q is Query) q.onFocus();
      } catch (_) {}
    }
  }

  /// Notify each built Query instance that the connection returned online so
  /// they can decide whether to refetch.
  void onOnline() {
    for (var q in _queries.values) {
      try {
        if (q != null && q is Query) q.onOnline();
      } catch (_) {}
    }
  }

  /// Find a single entry by exact query key.
  QueryCacheEntry? find(List<Object> queryKey) =>
      _cache[queryKeyToCacheKey(queryKey)];

  /// Find all entries whose cache keys start with the serialized [queryKey].
  List<QueryCacheEntry> findAll(List<Object> queryKey) {
    final cacheKey = queryKeyToCacheKey(queryKey);
    return _cache.entries
        .where((e) => e.key.startsWith(cacheKey))
        .map((e) => e.value)
        .toList();
  }

  /// Clear all entries — mirrors React's QueryCache.clear().
  ///
  /// Iterates all registered Query instances and calls remove(query) for each,
  /// which handles destroy + identity-safe deletion + notifications. Any
  /// cache-only entries (no Query built) are then swept from _cache directly.
  void clear({String? callerId}) {
    // Snapshot so iteration is safe while remove() mutates _queries.
    final queries = _queries.values.whereType<Query>().toList();
    for (final q in queries) {
      remove(q, callerId: callerId);
    }
    // Sweep any cache entries that had no associated Query object.
    final orphanKeys = _cache.keys.toList();
    for (final k in orphanKeys) {
      _cache.remove(k);
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.removed, k, null,
          callerId: callerId));
    }
  }

  void _notifyListeners(QueryCacheNotifyEvent event) {
    // Delegate to Subscribable to iterate and safely call listeners.
    notifyAll((l) => l(event));
  }

  /// Return the currently registered Query instance for [cacheKey], or null.
  /// Used by Query.optionalRemove() to perform the identity check before GCing.
  Query? getQuery(String cacheKey) => _queries[cacheKey] as Query?;

  /// Returns a snapshot of all currently registered Query instances.
  List<Query> getAllQueries() => _queries.values.whereType<Query>().toList();

  /// Build or return an existing `Query` instance for the given options.
  Query<T> build<T>(QueryClient client, QueryOptions<T> options) {
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    if (_queries.containsKey(cacheKey)) {
      return _queries[cacheKey] as Query<T>;
    }

    final q = Query<T>(client, options);
    _queries[cacheKey] = q;

    // If there's no cache entry yet and initialData is provided, persist it
    // to the cache so queries start with initialized data.
    if (!_cache.containsKey(cacheKey) && options.initialData != null) {
      final initData = options.resolveInitialData();

      if (initData != null) {
        final updatedAt = options.resolveInitialDataUpdatedAt() ?? 0;

        final queryResult = QueryResult(
            cacheKey, QueryStatus.success, initData as T, null,
            isFetching: false,
            dataUpdatedAt: updatedAt,
            isPlaceholderData: false);
        _cache[cacheKey] = QueryCacheEntry(
            queryResult, DateTime.fromMillisecondsSinceEpoch(updatedAt));
      }
    }

    return q;
  }
}
