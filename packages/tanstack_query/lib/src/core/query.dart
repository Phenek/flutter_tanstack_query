import 'dart:async';
import 'package:tanstack_query/tanstack_query.dart';
import 'removable.dart';

/// Minimal `Query` implementation to centralize fetch and observer logic.
class Query<T> extends Removable {
  final QueryClient client;
  QueryOptions<T> options;
  final String cacheKey;

  final Set<dynamic> _observers = <dynamic>{};

  /// Active retryer
  Retryer<T>? _retryer;

  Query(this.client, this.options)
      : cacheKey = queryKeyToCacheKey(options.queryKey) {
    // Initialize GC timing using options + client defaults
    updateGcTime(options.gcTime,
        defaultGcTime: client.defaultOptions.queries.gcTime);
  }

  void addObserver(dynamic observer) {
    _observers.add(observer);
    // If an observer is added, cancel GC
    clearGcTimeout();
  }

  void removeObserver(dynamic observer) {
    _observers.remove(observer);
    if (_observers.isEmpty) {
      scheduleGc();
    }
  }

  QueryCacheEntry<T>? get entry =>
      client.queryCache[cacheKey] as QueryCacheEntry<T>?;

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

  /// Fetch using Retryer with retry configuration from options.
  Future<T?> fetch() async {
    // If there's already an in-flight retryer return its promise
    if (_retryer != null && _retryer!.status() == 'pending') {
      return _retryer!.start();
    }

    Future<T> fn() async {
      // Execute the query function
      return await options.queryFn();
    }

    TrackedFuture<T>? running;

    _retryer = Retryer<T>(
      fn: fn,
      retry: options.retry ?? client.defaultOptions.queries.retry,
      retryDelay:
          options.retryDelay ?? client.defaultOptions.queries.retryDelay,
      onFail: (failureCount, error) {
        // Update cache to reflect the failure count/reason while still retrying
        final failRes = QueryResult<T>(
            cacheKey, QueryStatus.pending, null, error,
            isFetching: true, failureCount: failureCount, failureReason: error);
        client.queryCache[cacheKey] = QueryCacheEntry<T>(
            failRes, DateTime.now(),
            queryFnRunning: running);
        _notifyObservers();
      },
    );

    // Mark as pending in cache and notify observers immediately
    final pending = QueryResult<T>(cacheKey, QueryStatus.pending, null, null,
        isFetching: true, failureCount: 0, failureReason: null);
    // Wrap retryer.start() in a TrackedFuture so other code can inspect queryFnRunning
    running = TrackedFuture<T>(_retryer!.start());
    client.queryCache[cacheKey] =
        QueryCacheEntry<T>(pending, DateTime.now(), queryFnRunning: running);
    _notifyObservers();

    try {
      final value = await running;
      final queryResult = QueryResult<T>(
          cacheKey, QueryStatus.success, value, null,
          isFetching: false, failureCount: 0, failureReason: null);
      client.queryCache[cacheKey] =
          QueryCacheEntry<T>(queryResult, DateTime.now());
      client.queryCache.config.onSuccess?.call(value);
      _notifyObservers();
      // Clear the retryer reference since the fetch has settled
      _retryer = null;
      return value;
    } catch (e) {
      final failureCount = _retryer?.failureCount ?? 0;
      final errorRes = QueryResult<T>(cacheKey, QueryStatus.error, null, e,
          isFetching: false, failureCount: failureCount, failureReason: e);
      client.queryCache[cacheKey] =
          QueryCacheEntry<T>(errorRes, DateTime.now());
      client.queryCache.config.onError?.call(e);
      _notifyObservers();
      // Clear the retryer reference since the fetch has settled
      _retryer = null;
      rethrow;
    }
  }

  void cancel() {
    _retryer?.cancel();
    clearGcTimeout();
  }

  @override
  void optionalRemove() {
    client.queryCache.remove(cacheKey);
  }
}
