import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'subscribable.dart';

/// Options specific to infinite queries.
class InfiniteQueryOptions<T> {
  final List<Object> queryKey;
  final Future<T?> Function(int pageParam) queryFn;
  final int initialPageParam;
  final int Function(T lastResult)? getNextPageParam;
  final int Function(T firstResult)? getPreviousPageParam;
  final Duration? debounceTime;
  final bool? enabled;
  final bool? refetchOnRestart;
  final bool? refetchOnReconnect;

  InfiniteQueryOptions({
    required this.queryKey,
    required this.queryFn,
    required this.initialPageParam,
    this.getNextPageParam,
    this.getPreviousPageParam,
    this.debounceTime,
    this.enabled,
    this.refetchOnRestart,
    this.refetchOnReconnect,
  });
}

/// Observer for infinite/paginated queries.
///
/// This mirrors the responsibilities of the JS `InfiniteQueryObserver` by
/// exposing `getCurrentResult`, `fetchNextPage` and `fetchPreviousPage` and by
/// keeping a cached result in sync with the QueryClient's cache.
class InfiniteQueryObserver<T> extends Subscribable<Function> {
  final QueryClient _client;
  late InfiniteQueryOptions<T> _options;

  InfiniteQueryResult<T> _currentResult;
  Timer? _timer;
  bool _isMounted = true;
  int _currentPage = 0;
  final String _callerId = DateTime.now().microsecondsSinceEpoch.toString();
  void Function()? _cacheUnsubscribe;

  InfiniteQueryObserver(this._client, InfiniteQueryOptions<T> options)
      : _options = options,
        _currentResult = InfiniteQueryResult<T>(
            key: queryKeyToCacheKey(options.queryKey),
            status: QueryStatus.pending,
            data: [],
            isFetching: false,
            error: null,
            isFetchingNextPage: false) {
    _currentPage = options.initialPageParam;
    _initFromCache();
    _subscribeToCache();
    // Trigger initial fetch if enabled
    final enabled = options.enabled ?? _client.defaultOptions.queries.enabled;
    if (enabled) {
      if (options.debounceTime == null) {
        refetch();
      } else {
        _setLoadingWithDebounce();
      }
    }
  }

  void setOptions(InfiniteQueryOptions<T> options) {
    _options = options;
  }

  InfiniteQueryResult<T> getCurrentResult() => _currentResult;

  Future<void> refetch() async {
    // reset to initial state and fetch the first page
    _currentPage = _options.initialPageParam;
    final cacheKey = queryKeyToCacheKey(_options.queryKey);

    // Only create a running entry if none exists or the existing one is finished
    var cacheEntry = _client.queryCache[cacheKey];
    var shouldUpdateTheCache = false;

    if (cacheEntry == null ||
        cacheEntry.queryFnRunning == null ||
        cacheEntry.queryFnRunning!.isCompleted ||
        cacheEntry.queryFnRunning!.hasError) {
      final queryResult = InfiniteQueryResult<T>(
          key: cacheKey,
          status: QueryStatus.pending,
          data: [],
          isFetching: true,
          error: null,
          isFetchingNextPage: false);

      final futureFetch = TrackedFuture<T?>(_options.queryFn(_options.initialPageParam));
      _client.queryCache[cacheKey] =
          cacheEntry = QueryCacheEntry(queryResult, DateTime.now(), queryFnRunning: futureFetch);
      shouldUpdateTheCache = true;
    }

    final running = cacheEntry.queryFnRunning;
    if (running == null) return;
    final futureFetch = running;

    _currentResult = cacheEntry.result as InfiniteQueryResult<T>;
    _notify();

    try {
      final value = await futureFetch;
      if (value == null) return;

      final List<T> data = [value as T];
      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.success,
        data: data,
        isFetching: false,
        error: null,
        isFetchingNextPage: false,
      );
      queryResult.fetchNextPage = () => fetchNextPage();

      _currentResult = queryResult;
      if (shouldUpdateTheCache) _client.queryCache[cacheKey] = QueryCacheEntry(queryResult, DateTime.now());
      _client.queryCache.config.onSuccess?.call(value);
      _notify();
    } catch (e) {
      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.error,
        data: <T>[],
        isFetching: false,
        error: e,
        isFetchingNextPage: false,
      );
      queryResult.fetchNextPage = () => fetchNextPage();
      _currentResult = queryResult;
      if (shouldUpdateTheCache) _client.queryCache[cacheKey] = QueryCacheEntry(queryResult, DateTime.now());
      _client.queryCache.config.onError?.call(e);
      _notify();
    }
  }

  void _setLoadingWithDebounce() {
    final cacheKey = queryKeyToCacheKey(_options.queryKey);
    _currentResult = InfiniteQueryResult<T>(
        key: cacheKey, status: QueryStatus.pending, data: [], isFetching: true, error: null, isFetchingNextPage: false);
    _notify();

    _timer?.cancel();
    _timer = Timer(_options.debounceTime!, () => refetch());
  }

  void fetchNextPage() {
    final hasData = _currentResult.data != null && _currentResult.data!.isNotEmpty;
    final nextPage = _options.getNextPageParam != null && hasData
        ? _options.getNextPageParam!(_currentResult.data!.last)
        : _currentPage;

    if (nextPage <= _currentPage || _currentResult.isFetchingNextPage) return;

    _currentPage = nextPage;
    final cacheKey = queryKeyToCacheKey(_options.queryKey);

    final queryLoadingMore = _currentResult.copyWith(isFetching: true, isFetchingNextPage: true);
    _currentResult = queryLoadingMore;
    _notify();

    final futureFetch = TrackedFuture<T?>(_options.queryFn(nextPage));

    futureFetch.then((value) {
      if (!_isMounted) return;
      if (value is! T) return;
      final existing = _currentResult.data ?? <T>[];
      final List<T> data = [...existing, value];

      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.success,
        data: data,
        isFetching: false,
        error: null,
        isFetchingNextPage: false,
      );
      queryResult.fetchNextPage = () => fetchNextPage();

      _currentResult = queryResult;
      _client.queryCache[cacheKey] = QueryCacheEntry(queryResult, DateTime.now());
      _client.queryCache.config.onSuccess?.call(value);
      _notify();
    }).catchError((e) {
      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.error,
        data: <T>[],
        isFetching: false,
        error: e,
        isFetchingNextPage: false,
      );
      queryResult.fetchNextPage = () => fetchNextPage();
      _currentResult = queryResult;
      _client.queryCache[cacheKey] = QueryCacheEntry(queryResult, DateTime.now());
      _client.queryCache.config.onError?.call(e);
      _notify();
    });
  }

  void _initFromCache() {
    final cacheKey = queryKeyToCacheKey(_options.queryKey);
    final cacheEntry = _client.queryCache[cacheKey];
    if (cacheEntry != null && cacheEntry.result is InfiniteQueryResult) {
      _currentResult = cacheEntry.result as InfiniteQueryResult<T>;
      _currentResult.fetchNextPage = () => fetchNextPage();
    }
  }

  void _handleCacheEvent(QueryCacheNotifyEvent event) {
    if (event.cacheKey != queryKeyToCacheKey(_options.queryKey)) return;
    if (event.callerId != null && event.callerId == _callerId) return;

    try {
      if (event.type == QueryCacheEventType.removed) {
        final cacheKey = queryKeyToCacheKey(_options.queryKey);
        _currentResult = InfiniteQueryResult<T>(
            key: cacheKey,
            status: QueryStatus.pending,
            data: [],
            isFetching: false,
            error: null,
            isFetchingNextPage: false);
        _notify();
      } else if (event.type == QueryCacheEventType.added || event.type == QueryCacheEventType.updated) {
        final dynamic raw = event.entry?.result;
        if (raw is InfiniteQueryResult<T>) {
          final q = InfiniteQueryResult<T>(
              key: queryKeyToCacheKey(_options.queryKey),
              status: raw.status,
              data: raw.data as List<T>,
              isFetching: raw.isFetching,
              error: raw.error,
              isFetchingNextPage: raw.isFetchingNextPage);
          q.fetchNextPage = () => fetchNextPage();
          _currentResult = q;
          _notify();
        }
      } else if (event.type == QueryCacheEventType.refetch ||
          (event.type == QueryCacheEventType.refetchOnRestart &&
              (_options.refetchOnRestart ?? _client.defaultOptions.queries.refetchOnRestart)) ||
          (event.type == QueryCacheEventType.refetchOnReconnect &&
              (_options.refetchOnReconnect ?? _client.defaultOptions.queries.refetchOnReconnect))) {
        // re-fetch pages up to the current page
        refetchPagesUpToCurrent();
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _subscribeToCache() {
    _cacheUnsubscribe = _client.queryCache.subscribe(_handleCacheEvent);
  }

  void refetchPagesUpToCurrent() async {
    final List<T> data = [];
    try {
      final cacheKey = queryKeyToCacheKey(_options.queryKey);
      // loading...
      var queryResult = InfiniteQueryResult<T>(
          key: cacheKey,
          status: QueryStatus.pending,
          data: [],
          isFetching: true,
          error: null,
          isFetchingNextPage: false);
      queryResult.fetchNextPage = () => fetchNextPage();
      _currentResult = queryResult;
      _notify();

      for (int page = _options.initialPageParam; page <= _currentPage; page++) {
        final pageData = await _options.queryFn(page);
        if (pageData == null) return;
        data.add(pageData);
      }

      queryResult = InfiniteQueryResult(
        key: queryKeyToCacheKey(_options.queryKey),
        status: QueryStatus.success,
        data: data,
        isFetching: false,
        error: null,
        isFetchingNextPage: false,
      );
      queryResult.fetchNextPage = () => fetchNextPage();
      _currentResult = queryResult;
      _client.queryCache[queryKeyToCacheKey(_options.queryKey)] = QueryCacheEntry(queryResult, DateTime.now());
      _notify();
    } catch (e) {
      debugPrint("An error occurred while refetching pages up to current: $e");
    }
  }

  @override
  void onUnsubscribe() {
    _isMounted = false;
    _timer?.cancel();
    try {
      _cacheUnsubscribe?.call();
    } catch (_) {}
  }

  void _notify() {
    notifyAll((listener) {
      try {
        final typed = listener as void Function(InfiniteQueryResult<T>);
        typed(_currentResult);
      } catch (_) {}
    });
  }
}
