import 'package:tanstack_query/tanstack_query.dart';
import 'subscribable.dart';

/// Result shape returned by the observer.
class QueryObserverResult<T, E> {
  final T? data;
  final Object? error;
  final String status;
  final bool isFetching;
  final bool isSuccess;
  final bool isError;
  final bool isStale;

  final Future<QueryObserverResult<T, E>> Function({bool? throwOnError}) refetch;

  QueryObserverResult({
    required this.data,
    required this.error,
    required this.status,
    required this.isFetching,
    required this.isSuccess,
    required this.isError,
    required this.isStale,
    required this.refetch,
  });
}

/// Listener typedef used by `QueryObserver`.
typedef QueryObserverListener<T, E> = void Function(QueryObserverResult<T, E>);

/// A simplified `QueryObserver` that mirrors the behavior of the JS implementation
/// insofar as it maintains a current result based on a Query, can be subscribed
/// to by multiple listeners, and can trigger refetch.
class QueryObserver<TQueryFnData, TError, TData> extends Subscribable<Function> {
  final QueryClient _client;
  QueryOptions<TQueryFnData> options;

  QueryCacheEntry? _currentEntry;
  QueryObserverResult<TData, TError>? _currentResult;
  Query? _query;

  QueryObserver(this._client, this.options) {
    _updateQuery();
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
      refetch();
    }
  }

  QueryObserverResult<TData, TError> getCurrentResult() => _currentResult!;

  @override
  void onSubscribe() {
    // Called when the first listener subscribes. Start a refetch when
    // the current cache entry is missing, stale, or in error state —
    // mirroring the previous `useQuery` behavior.
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    final entry = _client.queryCache[cacheKey];

    final enabled = options.enabled ?? true;

    final shouldFetch = enabled && (
      entry == null ||
      (entry.result is QueryResult && (entry.result as QueryResult).isError) ||
      (DateTime.now().difference(entry.timestamp).inMilliseconds > (options.staleTime ?? 0))
    );

    if (shouldFetch) {
      // Fire-and-forget the fetch
      refetch();
    }
  }

  @override
  void onUnsubscribe() {
    try {
      _query?.removeObserver(this);
      _query?.scheduleGc();
      _query = null;
    } catch (_) {}
  }

  Future<QueryObserverResult<TData, TError>> refetch({bool? throwOnError}) async {
    _updateQuery();
    final cacheKey = queryKeyToCacheKey(options.queryKey);

    var entry = _client.queryCache[cacheKey];

    if (entry == null || entry.queryFnRunning == null || entry.queryFnRunning!.isCompleted || entry.queryFnRunning!.hasError) {
      final queryResult = QueryResult<TData>(cacheKey, QueryStatus.pending, null, null, isFetching: true);
      final futureFetch = TrackedFuture<TData>(options.queryFn() as Future<TData>);
      _client.queryCache[cacheKey] = QueryCacheEntry<TData>(queryResult, DateTime.now(), queryFnRunning: futureFetch);
      entry = _client.queryCache[cacheKey];
      // Ensure observer sees the updated entry
      _currentEntry = _client.queryCache[cacheKey];
      _updateResult();
      _notify();
    }

    final running = entry?.queryFnRunning;
    if (running != null) {
      try {
        final value = await running as TData;
        final queryResult = QueryResult<TData>(cacheKey, QueryStatus.success, value, null, isFetching: false);
        _client.queryCache[cacheKey] = QueryCacheEntry<TData>(queryResult, DateTime.now());
        _client.queryCache.config.onSuccess?.call(value);
        // refresh observer entry
        _currentEntry = _client.queryCache[cacheKey];
      } catch (e) {
        final queryResult = QueryResult<TData>(cacheKey, QueryStatus.error, null, e, isFetching: false);
        _client.queryCache[cacheKey] = QueryCacheEntry<TData>(queryResult, DateTime.now());
        _client.queryCache.config.onError?.call(e);
        _currentEntry = _client.queryCache[cacheKey];
      } finally {
        _updateResult();
        _notify();
      }
    }

    return _currentResult!;
  }

  void onQueryUpdate() {
    _updateResult();
    _notify();
  }

  void _updateQuery() {
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    // Use QueryCache.build to obtain a Query instance and subscribe to it
    final q = _client.queryCache.build<TData>(_client, options as QueryOptions<TData>);

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
    final resDynamic = entry?.result;

    TData? data;
    Object? error;
    QueryStatus? status;
    bool isFetching = false;
    bool isSuccess = false;
    bool isError = false;

    if (resDynamic is QueryResult) {
      data = resDynamic.data as TData?;
      error = resDynamic.error;
      status = resDynamic.status;
      isFetching = resDynamic.isFetching;
      isSuccess = resDynamic.isSuccess;
      isError = resDynamic.isError;
    }

    final statusStr = status == QueryStatus.success
        ? 'success'
        : (status == QueryStatus.error ? 'error' : 'pending');

    _currentResult = QueryObserverResult<TData, TError>(
      data: data,
      error: error,
      status: statusStr,
      isFetching: isFetching,
      isSuccess: isSuccess,
      isError: isError,
      isStale: entry == null ? true : DateTime.now().difference(entry.timestamp).inMilliseconds > (options.staleTime ?? 0),
      refetch: ({bool? throwOnError}) => refetch(throwOnError: throwOnError),
    );
  }

  void _notify() {
    notifyAll((listener) {
      try {
        final typed = listener as QueryObserverListener<TData, TError>;
        typed(_currentResult!);
      } catch (_) {}
    });


  }
}
