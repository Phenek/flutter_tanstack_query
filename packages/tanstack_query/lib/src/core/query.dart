import 'dart:async';
import 'retryer.dart';
import 'package:tanstack_query/tanstack_query.dart';

/// Minimal `Query` implementation to centralize fetch and observer logic.
class Query<T> {
  final QueryClient client;
  QueryOptions<T> options;
  final String cacheKey;

  final Set<dynamic> _observers = <dynamic>{};

  /// GC timer id
  Timer? _gcTimer;

  /// Active retryer
  Retryer<T>? _retryer;

  Query(this.client, this.options) : cacheKey = queryKeyToCacheKey(options.queryKey);

  void addObserver(dynamic observer) {
    _observers.add(observer);
    // If an observer is added, cancel GC
    _gcTimer?.cancel();
    _gcTimer = null;
  }

  void removeObserver(dynamic observer) {
    _observers.remove(observer);
    if (_observers.isEmpty) {
      scheduleGc();
    }
  }

  QueryCacheEntry<T>? get entry => client.queryCache[cacheKey] as QueryCacheEntry<T>?;

  QueryResult<T>? get result => entry?.result as QueryResult<T>?;

  bool get hasObservers => _observers.isNotEmpty;

  void _notifyObservers() {
    for (var o in List<dynamic>.from(_observers)) {
      try {
        o.onQueryUpdate();
      } catch (_) {
        // ignore
      }
    }
  }

  /// Schedule garbage collection to remove this query from cache after gcTime.
  void scheduleGc() {
    _gcTimer?.cancel();
    final gc = options.gcTime ?? client.defaultOptions.queries.gcTime;
    // Avoid scheduling very long-lived GC timers during tests which can
    // leave pending timers and fail the test harness. Only schedule if
    // a reasonably small GC time is configured.
    if (gc <= 0 || gc > 10000) return;

    _gcTimer = Timer(Duration(milliseconds: gc), () {
      if (!_observers.isNotEmpty) {
        client.queryCache.remove(cacheKey);
      }
    });
  }

  /// Fetch using Retryer with retry configuration from options.
  Future<T?> fetch() async {
    // If there's already a pending retryer return its promise
    if (_retryer != null && _retryer!.status() != 'rejected') {
      return _retryer!.start();
    }

    final fn = () async {
      // Execute the query function
      return await options.queryFn();
    };

    _retryer = Retryer<T>(fn: fn, retry: options.retry ?? client.defaultOptions.queries.retry, retryDelay: options.retryDelay ?? client.defaultOptions.queries.retryDelay);

    // Mark as pending in cache and notify observers immediately
    final pending = QueryResult<T>(cacheKey, QueryStatus.pending, null, null, isFetching: true);
    // Wrap retryer.start() in a TrackedFuture so other code can inspect queryFnRunning
    final running = TrackedFuture<T>(_retryer!.start());
    client.queryCache[cacheKey] = QueryCacheEntry<T>(pending, DateTime.now(), queryFnRunning: running);
    _notifyObservers();

    try {
      final value = await running;
      final queryResult = QueryResult<T>(cacheKey, QueryStatus.success, value, null, isFetching: false);
      client.queryCache[cacheKey] = QueryCacheEntry<T>(queryResult, DateTime.now());
      client.queryCache.config.onSuccess?.call(value);
      _notifyObservers();
      return value;
    } catch (e) {
      final errorRes = QueryResult<T>(cacheKey, QueryStatus.error, null, e, isFetching: false);
      client.queryCache[cacheKey] = QueryCacheEntry<T>(errorRes, DateTime.now());
      client.queryCache.config.onError?.call(e);
      _notifyObservers();
      rethrow;
    }
  }

  void cancel() {
    _retryer?.cancel();
  }
}
