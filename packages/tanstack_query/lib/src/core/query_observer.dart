import 'dart:async';
import 'package:tanstack_query/tanstack_query.dart';
import 'subscribable.dart';
import 'package:flutter/foundation.dart';

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
    // Called when the first listener subscribes. Decide based on
    // `refetchOnMount` whether to start a refetch. Delegate the policy to
    // `shouldFetchOnMount` so behavior matches JS implementation.
    if (shouldFetchOnMount()) {
      refetch();
    }
  }

  /// Whether this observer should trigger a refetch when it mounts/subscribes.
  bool shouldFetchOnMount() {
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    final entry = _client.queryCache[cacheKey];

    final enabled = options.enabled ?? true;

    final isErrored = entry != null &&
        entry.result is QueryResult &&
        (entry.result as QueryResult).isError;
    final retryOnMount =
        options.retryOnMount ?? _client.defaultOptions.queries.retryOnMount;

    final isStale = entry == null ||
        (DateTime.now().difference(entry.timestamp).inMilliseconds >
            (options.staleTime ?? 0));

    final refetchOnMount =
        options.refetchOnMount ?? _client.defaultOptions.queries.refetchOnMount;

    return enabled &&
        refetchOnMount &&
        (entry == null || (isErrored && retryOnMount) || isStale);
  }

  /// Whether this observer should refetch when the window/app regains focus.
  bool shouldFetchOnWindowFocus() {
    final refetchOnWindowFocus = options.refetchOnWindowFocus ??
        _client.defaultOptions.queries.refetchOnWindowFocus;
    if (!refetchOnWindowFocus) return false;
    final enabled = options.enabled ?? true;
    if (!enabled) return false;
    return _currentResult.isStale;
  }

  /// Whether this observer should refetch when the connection reconnects.
  bool shouldFetchOnReconnect() {
    final refetchOnReconnect = options.refetchOnReconnect ??
        _client.defaultOptions.queries.refetchOnReconnect;
    if (!refetchOnReconnect) return false;
    final enabled = options.enabled ?? true;
    if (!enabled) return false;
    return _currentResult.isStale;
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
      // Bound the fetch with a timeout so observers don't wait forever
      try {
        await _query!.fetch().timeout(Duration(seconds: 4), onTimeout: () {
          debugPrint('QueryObserver.refetch TIMEOUT for $cacheKey');
          return null;
        });
        debugPrint('QueryObserver.refetch fetch completed for $cacheKey');
      } catch (e) {
        debugPrint(
            'QueryObserver.refetch fetch error (caught) for $cacheKey -> $e');
      }

      _currentEntry = _client.queryCache[cacheKey];
    } catch (e) {
      debugPrint('QueryObserver.refetch fetch error for $cacheKey -> $e');
      _currentEntry = _client.queryCache[cacheKey];
      if (throwOnError == true) rethrow;
    } finally {
      _updateResult();
      _notify();
    }

    debugPrint('QueryObserver.refetch DONE for $cacheKey');
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

  Query? _lastQueryWithDefinedData;
  dynamic _lastPlaceholderDataOption;

  void _updateResult() {
    final entry = _currentEntry;
    final res = entry?.result;

    if (res is QueryResult) {
      final cacheKey = queryKeyToCacheKey(options.queryKey);

      // Determine the timestamp to use for staleness checks. Prefer the
      // dataUpdatedAt on the result (used by initialData) and fall back to
      // entry.timestamp when missing.
      final int lastUpdatedAt = res.dataUpdatedAt ??
          (entry != null ? entry.timestamp.millisecondsSinceEpoch : 0);

      final isStale = entry == null ||
          DateTime.now()
                  .difference(
                      DateTime.fromMillisecondsSinceEpoch(lastUpdatedAt))
                  .inMilliseconds >
              (options.staleTime ?? 0);

      // Track last query with defined data for placeholderData function usage
      if (res.data != null) {
        _lastQueryWithDefinedData = _query;
      }

      // Prepare default values
      var status = res.status;
      var data = res.data as TData?;
      var isPlaceholder = false;

      // If placeholderData is configured and we have no data and are pending,
      // compute placeholderData and treat it as success for this observer only
      if (options.placeholderData != null &&
          data == null &&
          status == QueryStatus.pending) {
        dynamic placeholderData;

        // Reuse previous placeholder data if possible (memoization)
        if (_currentResult.isPlaceholderData &&
            options.placeholderData == _lastPlaceholderDataOption) {
          placeholderData = _currentResult.data;
        } else {
          placeholderData = options.resolvePlaceholderData(
              _lastQueryWithDefinedData?.result?.data,
              _lastQueryWithDefinedData);
        }

        if (placeholderData != null) {
          status = QueryStatus.success;
          data = placeholderData as TData?;
          isPlaceholder = true;
          _lastPlaceholderDataOption = options.placeholderData;
        }
      }

      _currentResult = QueryResult<TData>(
        cacheKey,
        status,
        data,
        res.error,
        isFetching: res.isFetching,
        isStale: isStale,
        dataUpdatedAt: res.dataUpdatedAt,
        isPlaceholderData: isPlaceholder,
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
          (event.type == QueryCacheEventType.refetchOnWindowFocus &&
              (options.refetchOnWindowFocus ??
                  _client.defaultOptions.queries.refetchOnWindowFocus)) ||
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
