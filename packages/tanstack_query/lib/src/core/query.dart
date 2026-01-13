import 'dart:async';
import 'package:flutter/foundation.dart';
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
        final prevEntry = client.queryCache[cacheKey];
        final prevRes = prevEntry?.result as QueryResult<T>?;
        final hasPrevData = prevRes != null && prevRes.data != null;

        final failRes = QueryResult<T>(
            cacheKey,
            hasPrevData ? prevRes.status : QueryStatus.pending,
            hasPrevData ? prevRes.data : null,
            error,
            isFetching: true,
            dataUpdatedAt: hasPrevData ? prevRes.dataUpdatedAt : null,
            isPlaceholderData: false,
            failureCount: failureCount,
            failureReason: error);
        client.queryCache[cacheKey] = QueryCacheEntry<T>(
            failRes, DateTime.now(),
            queryFnRunning: running);
        _notifyObservers();
      },
    );

    // Mark as pending in cache and notify observers immediately
    final prevEntry = client.queryCache[cacheKey];
    final prevRes = prevEntry?.result as QueryResult<T>?;
    final hasPrevData = prevRes != null && prevRes.data != null;

    final pending = QueryResult<T>(
        cacheKey,
        hasPrevData ? QueryStatus.success : QueryStatus.pending,
        hasPrevData ? prevRes.data : null,
        null,
        isFetching: true,
        dataUpdatedAt: hasPrevData ? prevRes.dataUpdatedAt : null,
        isPlaceholderData: false,
        failureCount: 0,
        failureReason: null);

    // Wrap retryer.start() in a TrackedFuture so other code can inspect queryFnRunning
    running = TrackedFuture<T>(_retryer!.start());
    debugPrint('TrackedFuture created for $cacheKey');
    client.queryCache[cacheKey] =
        QueryCacheEntry<T>(pending, DateTime.now(), queryFnRunning: running);
    _notifyObservers();

    try {
      final value = await running;
      final queryResult = QueryResult<T>(
          cacheKey, QueryStatus.success, value, null,
          isFetching: false,
          dataUpdatedAt: DateTime.now().millisecondsSinceEpoch,
          isPlaceholderData: false,
          failureCount: 0,
          failureReason: null);
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
          isFetching: false,
          dataUpdatedAt: null,
          isPlaceholderData: false,
          failureCount: failureCount,
          failureReason: e);
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

  /// Handle window/app focus events: find an observer that wants a refetch
  /// on focus and trigger it, then continue any paused retryer.
  void onFocus() {
    dynamic observer;
    for (var o in _observers) {
      try {
        if (o.shouldFetchOnWindowFocus != null) {
          observer = o;
          break;
        }
      } catch (_) {}
    }

    try {
      observer?.refetch();
    } catch (_) {}

    // Continue fetch if currently paused
    try {
      _retryer?.continueRetry();
    } catch (_) {}
  }

  /// Handle online events: find an observer that wants a refetch on reconnect
  /// and trigger it, then continue any paused retryer.
  void onOnline() {
    dynamic observer;
    for (var o in _observers) {
      try {
        if (o.shouldFetchOnReconnect != null) {
          observer = o;
          break;
        }
      } catch (_) {}
    }

    try {
      observer?.refetch();
    } catch (_) {}

    // Continue fetch if currently paused
    try {
      _retryer?.continueRetry();
    } catch (_) {}
  }

  @override
  void optionalRemove() {
    client.queryCache.remove(cacheKey);
  }
}
