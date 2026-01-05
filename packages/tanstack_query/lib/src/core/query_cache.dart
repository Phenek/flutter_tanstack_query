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
  refetchOnRestart,
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

  /// Remove a cache entry by key and notify listeners if something was removed.
  QueryCacheEntry? remove(String key, {String? callerId}) {
    final removed = _cache.remove(key);
    if (removed != null) {
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.removed, key, removed,
          callerId: callerId));
    }
    // Also remove any built Query instance
    if (_queries.containsKey(key)) {
      final q = _queries.remove(key);
      try {
        if (q != null && q is Query) q.cancel();
      } catch (_) {}
    }
    return removed;
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
      // If there was a built Query instance for this key, cancel and remove it
      if (_queries.containsKey(entry.key)) {
        final q = _queries.remove(entry.key);
        try {
          if (q != null && q is Query) q.cancel();
        } catch (_) {}
      }
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.removed, entry.key, entry.value));
    }
  }

  /// Request a refetch for all cache entries matching [queryKey].
  ///
  /// This will emit a `refetch` event for each matching cache entry so
  /// listeners can trigger their refetch callbacks. An optional `callerId`
  /// may be provided so listeners can be excluded if needed.
  void refetch(List<Object> queryKey, {String? callerId}) {
    final cacheKey = queryKeyToCacheKey(queryKey);
    for (var k in _cache.keys.where((k) => k.startsWith(cacheKey))) {
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.refetch, k, _cache[k],
          callerId: callerId));
    }
  }

  /// Request a refetch for a specific cache key.
  void refetchByCacheKey(String cacheKey, {String? callerId}) {
    _notifyListeners(QueryCacheNotifyEvent(
        QueryCacheEventType.refetch, cacheKey, _cache[cacheKey],
        callerId: callerId));
  }

  /// Trigger refetch events for all cache entries; typically used on restart.
  void refetchOnRestart() {
    for (var k in _cache.keys) {
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.refetchOnRestart, k, _cache[k]));
    }
  }

  /// Trigger refetch events for all cache entries when the connection is re-established.
  void refetchOnReconnect() {
    for (var k in _cache.keys) {
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.refetchOnReconnect, k, _cache[k]));
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

  /// Clear all entries and notify listeners for each removal and a final `clear` event.
  void clear({String? callerId}) {
    final keys = _cache.keys.toList();
    _cache.clear();

    // Cancel and remove any built Query instances to avoid leaving pending
    // timers (GC timers) running after the cache has been cleared.
    for (var q in _queries.values) {
      try {
        if (q != null && q is Query) q.cancel();
      } catch (_) {}
    }
    _queries.clear();

    for (var k in keys) {
      _notifyListeners(QueryCacheNotifyEvent(
          QueryCacheEventType.removed, k, null,
          callerId: callerId));
    }
  }

  void _notifyListeners(QueryCacheNotifyEvent event) {
    // Delegate to Subscribable to iterate and safely call listeners.
    notifyAll((l) => l(event));
  }

  /// Build or return an existing `Query` instance for the given options.
  Query<T> build<T>(QueryClient client, QueryOptions<T> options) {
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    if (_queries.containsKey(cacheKey)) {
      return _queries[cacheKey] as Query<T>;
    }

    final q = Query<T>(client, options);
    _queries[cacheKey] = q;
    return q;
  }
}
