import 'dart:async';
import 'package:meta/meta.dart';
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
  Query? _query;
  late bool _hadCacheEntryAtInit;

  bool _clearStaleDataOnMount = false;
  int? _clearStaleDataOnMountAt;

  QueryObserver(
    this._client,
    this.options,
  ) : _currentResult = QueryResult<TData>(
          queryKeyToCacheKey(options.queryKey),
          QueryStatus.pending,
          null,
          null,
        ) {
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    _hadCacheEntryAtInit = _client.queryCache.containsKey(cacheKey);
    _clearStaleDataOnMount =
        _hadCacheEntryAtInit && shouldClearStaleDataOnMount();
    if (_clearStaleDataOnMount) {
      _clearStaleDataOnMountAt = DateTime.now().millisecondsSinceEpoch;
    }
    updateQuery();
    _initFromCache();
  }

  void setOptions(QueryOptions<TQueryFnData> newOptions) {
    final prevKey = queryKeyToCacheKey(options.queryKey);
    final prevEnabled = options.enabled ?? true;

    options = newOptions;

    updateQuery();
    _updateResult();
    final nextKey = queryKeyToCacheKey(options.queryKey);
    final nextEnabled = options.enabled ?? true;

    if (prevKey != nextKey) {
      _hadCacheEntryAtInit = _client.queryCache.containsKey(nextKey);
      _clearStaleDataOnMount =
          _hadCacheEntryAtInit && shouldClearStaleDataOnMount();
      if (_clearStaleDataOnMount) {
        _clearStaleDataOnMountAt = DateTime.now().millisecondsSinceEpoch;
      }
    }

    // If queryKey changed or it transitioned from disabled->enabled, trigger a refetch
    if (prevKey != nextKey || (!prevEnabled && nextEnabled)) {
      refetch();
    }
  }

  QueryResult<TData> getCurrentResult() => _currentResult;

  /// Fetch data for this observer. Supports pagination metadata for
  /// infinite queries.
  Future<QueryResult<TData>> fetch(
      {FetchMeta? meta, bool? throwOnError}) async {
    updateQuery();

    if (_query == null) return _currentResult;

    try {
      await _query!.fetch(meta: meta).timeout(Duration(seconds: 4),
          onTimeout: () {
        return null;
      });
    } catch (e) {
      if (throwOnError == true) rethrow;
    } finally {
      _updateResult();
      _notify();
    }
    return _currentResult;
  }

  @override
  void onSubscribe() {
    // Mirror React: only act on the FIRST subscriber (listeners.length == 1).
    if (listeners.length == 1) {
      // Attach this observer to the underlying Query so it prevents GC.
      // React does this in onSubscribe(), NOT in the constructor.
      _query?.addObserver(this);

      // Decide based on `refetchOnMount` whether to start a refetch.
      if (shouldFetchOnMount()) {
        _clearStaleDataOnMount =
            _hadCacheEntryAtInit && shouldClearStaleDataOnMount();
        if (_clearStaleDataOnMount) {
          _clearStaleDataOnMountAt = DateTime.now().millisecondsSinceEpoch;
        }
        refetch();
      } else {
        _updateResult();
      }
    }
  }

  /// Destroy this observer: remove from the underlying Query (which will
  /// schedule GC if no observers remain).
  /// Mirrors React's QueryObserver.destroy().
  void destroy() {
    try {
      _query?.removeObserver(this);
      _query = null;
    } catch (_) {}
  }

  @protected
  bool shouldClearStaleDataOnMount() {
    final staleTime =
        options.staleTime ?? _client.defaultOptions.queries.staleTime ?? 0;
    if (staleTime != 0) return false;

    final refetchOnMount =
        options.refetchOnMount ?? _client.defaultOptions.queries.refetchOnMount;
    if (!refetchOnMount) return false;

    final cacheKey = queryKeyToCacheKey(options.queryKey);
    final entry = _client.queryCache[cacheKey];
    if (entry == null || entry.result is! QueryResult) return false;
    final res = entry.result as QueryResult;
    if (res.data == null) return false;

    return true;
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
    // Mirror React: only destroy when the LAST listener has unsubscribed.
    if (!hasListeners()) {
      destroy();
    }
  }

  Future<QueryResult<TData>> refetch({bool? throwOnError}) async {
    return fetch(throwOnError: throwOnError);
  }

  void onQueryUpdate() {
    _updateResult();
    _notify();
  }

  /// Exposes the currently associated [Query] instance for subclasses.
  /// Mirrors React: `QueryObserver.#currentQuery`.
  @protected
  Query? get currentQuery => _query;

  /// Re-associates this observer with the correct [Query] for the current
  /// options. Builds the query if it does not exist yet, and transfers
  /// addObserver / removeObserver when listeners are already attached.
  /// Mirrors React: `QueryObserver.#updateQuery()`.
  @protected
  void updateQuery() {
    // Use QueryCache.build to obtain a Query instance.
    final q = _client.queryCache
        .build<TData>(_client, options as QueryOptions<TData>);

    if (_query == q) return; // nothing changed

    // Mirror React: only manipulate observer counts when we actually have
    // listeners. Before onSubscribe() fires, addObserver/removeObserver must
    // NOT be called — that is onSubscribe()'s job (first-subscriber only).
    if (hasListeners()) {
      // Detach from the old query so it can schedule GC if needed.
      try {
        _query?.removeObserver(this);
      } catch (_) {}
      // Attach to the new query to prevent it from being GCed.
      try {
        q.addObserver(this);
      } catch (_) {}
    }

    _query = q;
  }

  Query? _lastQueryWithDefinedData;
  dynamic _lastPlaceholderDataOption;

  QueryResult<TData> createResult(
      QueryResult<dynamic> res, QueryCacheEntry? entry) {
    final cacheKey = queryKeyToCacheKey(options.queryKey);

    // Determine the timestamp to use for staleness checks. Prefer the
    // dataUpdatedAt on the result (used by initialData) and fall back to
    // entry.timestamp when missing.
    final int lastUpdatedAt = res.dataUpdatedAt ??
        (entry != null ? entry.timestamp.millisecondsSinceEpoch : 0);

    final isStale = entry == null ||
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(lastUpdatedAt))
                .inMilliseconds >
            (options.staleTime ?? 0);

    // Track last query with defined data for placeholderData function usage
    if (res.data != null) {
      _lastQueryWithDefinedData = _query;
    }

    // Prepare default values
    var status = res.status;
    TData? data;
    try {
      data = res.data as TData?;
    } catch (_) {
      data = null;
      status = QueryStatus.pending;
    }
    var isPlaceholder = res.isPlaceholderData;
    var isFetching = res.isFetching;

    if (_clearStaleDataOnMount) {
      final updatedAt = res.dataUpdatedAt ??
          (entry != null ? entry.timestamp.millisecondsSinceEpoch : 0);
      final clearUntil = _clearStaleDataOnMountAt ?? 0;

      if (res.isFetching || updatedAt <= clearUntil) {
        status = QueryStatus.pending;
        data = null;
        isPlaceholder = false;
        isFetching = true;
      } else {
        _clearStaleDataOnMount = false;
      }
    }

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
            _lastQueryWithDefinedData?.result?.data, _lastQueryWithDefinedData);
      }

      if (placeholderData != null) {
        status = QueryStatus.success;
        data = placeholderData as TData?;
        isPlaceholder = true;
        _lastPlaceholderDataOption = options.placeholderData;
      }
    }

    return QueryResult<TData>(
      cacheKey,
      status,
      data,
      res.error,
      isFetching: isFetching,
      isStale: isStale,
      dataUpdatedAt: res.dataUpdatedAt,
      isPlaceholderData: isPlaceholder,
      failureCount: res.failureCount,
      failureReason: res.failureReason,
      refetch: ({bool? throwOnError}) => fetch(throwOnError: throwOnError),
      fetchMeta: res.fetchMeta,
    );
  }

  void _updateResult() {
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    final entry = _client.queryCache[cacheKey];
    final res = entry?.result;

    if (res is QueryResult) {
      try {
        _currentResult = createResult(res, entry);
      } catch (_) {
        // Ignore cache entry when it cannot be cast to the expected generic type.
      }
    }
  }

  void _initFromCache() {
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    final cacheEntry = _client.queryCache[cacheKey];
    if (cacheEntry != null && cacheEntry.result is QueryResult) {
      _updateResult();
    }
  }

  void _notify() {
    final result = getCurrentResult();
    notifyAll((listener) {
      try {
        (listener as dynamic)(result);
      } catch (_) {}
    });
  }
}
