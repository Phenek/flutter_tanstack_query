import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'subscribable.dart';

/// Listener typedef used by `QueryObserver`.
///
/// shape so hooks can consume it without an extra mapping step.
typedef QueryObserverListener<T, E> = void Function(QueryResult<T>);

/// A simplified `QueryObserver` that mirrors the behavior of the JS implementation
/// insofar as it maintains a current result based on a Query, can be subscribed
/// to by multiple listeners, and can trigger refetch.
class QueryObserver<TQueryFnData, TError, TData>
    extends Subscribable<Function> {
  final QueryClient _client;
  QueryOptions<TQueryFnData> options;

  QueryResult<TData> _currentResult;
  QueryCacheEntry? _currentEntry;
  Query? _query;

  // Unique id used to avoid reacting to our own cache events
  final String _callerId = DateTime.now().microsecondsSinceEpoch.toString();
  void Function()? _cacheUnsubscribe;

  QueryObserver(
    this._client,
    this.options,
  ) : _currentResult = QueryResult<TData>(
          queryKeyToCacheKey(options.queryKey),
          QueryStatus.pending,
          null,
          null,
        ) {
    _updateQuery();
    _initFromCache();
    _subscribeToCache();
    _updateResult();
  }

  void setOptions(QueryOptions<TQueryFnData> newOptions) {
    final prevKey = queryKeyToCacheKey(options.queryKey);
    final prevEnabled = options.enabled ?? true;

    options = newOptions;

    _updateQuery();
    _updateResult();

    final nextKey = queryKeyToCacheKey(options.queryKey);
    final nextEnabled = options.enabled ?? true;

    // If queryKey changed or it transitioned from disabled->enabled, trigger a refetch
    if (prevKey != nextKey || (!prevEnabled && nextEnabled)) {
      debugPrint(
          'QueryObserver.setOptions: key changed from $prevKey -> $nextKey; triggering refetch');
      refetch();
    }
  }

  QueryResult<TData> getCurrentResult() => _currentResult;

  @override
  void onSubscribe() {
    // Called when the first listener subscribes. Start a refetch when
    // the current cache entry is missing, stale, or in error state —
    // mirroring the previous `useQuery` behavior. Respect `retryOnMount`.
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    final entry = _client.queryCache[cacheKey];

    final enabled = options.enabled ?? true;

    final isErrored = entry != null &&
        entry.result is QueryResult &&
        (entry.result as QueryResult).isError;
    final retryOnMount =
        options.retryOnMount ?? _client.defaultOptions.queries.retryOnMount;

    final shouldFetch = enabled &&
        (entry == null ||
            (isErrored && retryOnMount) ||
            (DateTime.now().difference(entry.timestamp).inMilliseconds >
                (options.staleTime ?? 0)));

    if (shouldFetch) {
      // Fire-and-forget the fetch
      refetch();
    }
  }

  @override
  void onUnsubscribe() {
    try {
      _cacheUnsubscribe?.call();
    } catch (_) {}
    try {
      _query?.removeObserver(this);
      _query?.scheduleGc();
      _query = null;
    } catch (_) {}
  }

  Future<QueryResult<TData>> refetch({bool? throwOnError}) async {
    _updateQuery();
    final cacheKey = queryKeyToCacheKey(options.queryKey);

    if (_query == null) return _currentResult;

    try {
      await _query!.fetch();
      _currentEntry = _client.queryCache[cacheKey];
    } catch (e) {
      _currentEntry = _client.queryCache[cacheKey];
      if (throwOnError == true) rethrow;
    } finally {
      _updateResult();
      _notify();
    }

    return _currentResult;
  }

  void onQueryUpdate() {
    _updateResult();
    _notify();
  }

  void _updateQuery() {
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    // Use QueryCache.build to obtain a Query instance and subscribe to it
    final q = _client.queryCache
        .build<TData>(_client, options as QueryOptions<TData>);

    // If we had a previous query we should remove ourselves
    // (Query itself maintains no back-reference, observers subscribe directly)
    _currentEntry = _client.queryCache[cacheKey];

    // Detach from previous query if different
    if (_query != null && _query != q) {
      try {
        _query!.removeObserver(this);
      } catch (_) {}
    }

    _query = q;

    // Attach listener to the query instance so we get updates
    try {
      q.addObserver(this);
    } catch (_) {}
  }

  void _updateResult() {
    final entry = _currentEntry;
    final res = entry?.result;

    if (res is QueryResult) {
      final cacheKey = queryKeyToCacheKey(options.queryKey);
      final isStale = entry == null ||
          DateTime.now().difference(entry.timestamp).inMilliseconds >
              (options.staleTime ?? 0);

      _currentResult = QueryResult<TData>(
        cacheKey,
        res.status,
        res.data as TData?,
        res.error,
        isFetching: res.isFetching,
        isStale: isStale,
        failureCount: res.failureCount,
        failureReason: res.failureReason,
        refetch: ({bool? throwOnError}) => refetch(throwOnError: throwOnError),
      );
    }
  }

  void _initFromCache() {
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    final cacheEntry = _client.queryCache[cacheKey];
    if (cacheEntry != null && cacheEntry.result is QueryResult) {
      _currentEntry = cacheEntry;
      _updateResult();
    }
  }

  void _handleCacheEvent(QueryCacheNotifyEvent event) {
    if (event.cacheKey != queryKeyToCacheKey(options.queryKey)) return;
    if (event.callerId != null && event.callerId == _callerId) return;

    try {
      if (event.type == QueryCacheEventType.removed) {
        final cacheKey = queryKeyToCacheKey(options.queryKey);
        _currentResult = QueryResult<TData>(
            cacheKey, QueryStatus.pending, null, null,
            isFetching: false);
        _notify();
      } else if (event.type == QueryCacheEventType.added ||
          event.type == QueryCacheEventType.updated) {
        final dynamic raw = event.entry?.result;
        if (raw is QueryResult) {
          _currentEntry = event.entry;
          _updateResult();
          _notify();
        }
      } else if (event.type == QueryCacheEventType.refetch ||
          (event.type == QueryCacheEventType.refetchOnRestart &&
              (options.refetchOnRestart ??
                  _client.defaultOptions.queries.refetchOnRestart)) ||
          (event.type == QueryCacheEventType.refetchOnReconnect &&
              (options.refetchOnReconnect ??
                  _client.defaultOptions.queries.refetchOnReconnect))) {
        // Trigger a refetch according to the cache event and options
        refetch();
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _subscribeToCache() {
    _cacheUnsubscribe = _client.queryCache.subscribe(_handleCacheEvent);
  }

  void _notify() {
    notifyAll((listener) {
      try {
        final typed = listener as QueryObserverListener<TData, TError>;
        typed(_currentResult);
      } catch (_) {}
    });
  }
}
