import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'subscribable.dart';

/// Options specific to infinite queries.
///
/// Note: This extends the general `QueryOptions` so shared options such as
/// `retry`, `retryDelay` and `retryOnMount` are available for infinite
/// queries as well. The `queryFn` for infinite queries receives a `pageParam`.
class InfiniteQueryOptions<T> extends QueryOptions<T> {
  /// The page-aware query function. Receives the page parameter and returns
  /// the page data or `null`.
  final Future<T?> Function(int pageParam) pageQueryFn;

  final int initialPageParam;
  final int Function(T lastResult)? getNextPageParam;
  final int Function(T firstResult)? getPreviousPageParam;
  final Duration? debounceTime;

  InfiniteQueryOptions({
    required List<Object> queryKey,
    required Future<T?> Function(int pageParam) queryFn,
    required this.initialPageParam,
    this.getNextPageParam,
    this.getPreviousPageParam,
    this.debounceTime,
    double? staleTime,
    bool? enabled,
    bool? refetchOnRestart,
    bool? refetchOnReconnect,
    int? gcTime,
    dynamic retry,
    bool? retryOnMount,
    dynamic retryDelay,
  })  : pageQueryFn = queryFn,
        super(
          queryFn: () async => (await queryFn(initialPageParam)) as T,
          queryKey: queryKey,
          staleTime: staleTime,
          enabled: enabled,
          refetchOnRestart: refetchOnRestart,
          refetchOnReconnect: refetchOnReconnect,
          gcTime: gcTime,
          retry: retry,
          retryDelay: retryDelay,
          retryOnMount: retryOnMount,
        );
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
  }

  void setOptions(InfiniteQueryOptions<T> options) {
    _options = options;
  }

  @override
  void onSubscribe() {
    // When the first listener subscribes, behave similarly to QueryObserver:
    // only fetch if enabled AND (no cache entry exists, the cache entry is errored
    // and retryOnMount is true, or the cache entry is stale per staleTime)
    final cacheKey = queryKeyToCacheKey(_options.queryKey);
    final entry = _client.queryCache[cacheKey];

    final enabled = _options.enabled ?? _client.defaultOptions.queries.enabled;

    final isErrored = entry != null && entry.result is QueryResult && (entry.result as QueryResult).isError;
    final retryOnMount = _options.retryOnMount ?? _client.defaultOptions.queries.retryOnMount;

    final shouldFetch = enabled &&
        (entry == null || (isErrored && retryOnMount) ||
            (DateTime.now().difference(entry.timestamp).inMilliseconds > (_options.staleTime ?? 0)));

    if (shouldFetch) {
      if (_options.debounceTime == null) {
        refetch();
      } else {
        _setLoadingWithDebounce();
      }
    }
  }

  InfiniteQueryResult<T> getCurrentResult() => _currentResult;

  Future<void> refetch() async {
    // reset to initial state and fetch the first page
    _currentPage = _options.initialPageParam;
    final cacheKey = queryKeyToCacheKey(_options.queryKey);

    // Only create a running entry if none exists or the existing one is finished
    var cacheEntry = _client.queryCache[cacheKey];
    var shouldUpdateTheCache = false;

    Retryer<T?>? retryer;
    TrackedFuture<T?>? tracked;

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

      // Use Retryer to respect retry/retryDelay options
      retryer = Retryer<T?>(
        fn: () async => await _options.pageQueryFn(_options.initialPageParam),
        retry: _options.retry ?? _client.defaultOptions.queries.retry,
        retryDelay: _options.retryDelay ?? _client.defaultOptions.queries.retryDelay,
        onFail: (failureCount, error) {
          // Debug: observe retry failures
          debugPrint('DBG onFail initial fetch failureCount=$failureCount error=$error');
          // Update cache to reflect failure while still retrying
          final failRes = InfiniteQueryResult<T>(
              key: cacheKey,
              status: QueryStatus.pending,
              data: [],
              isFetching: true,
              error: error,
              isFetchingNextPage: false);
          try {
            failRes.failureCount = failureCount;
            failRes.failureReason = error;
          } catch (_) {}
          _client.queryCache[cacheKey] = QueryCacheEntry(failRes, DateTime.now(), queryFnRunning: tracked);
          _currentResult = failRes;
          _notify();
        },
      );

      tracked = TrackedFuture<T?>(retryer.start());
      _client.queryCache[cacheKey] = cacheEntry = QueryCacheEntry(queryResult, DateTime.now(), queryFnRunning: tracked);
      shouldUpdateTheCache = true;
    }

    final running = cacheEntry.queryFnRunning;
    if (running == null) return;

    _currentResult = cacheEntry.result as InfiniteQueryResult<T>;
    _notify();

    try {
      final value = await running;
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
      final failureCount = retryer?.failureCount ?? 0;
      debugPrint('DBG final status=QueryStatus.error failureCount=$failureCount failureReason=$e');
      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.error,
        data: <T>[],
        isFetching: false,
        error: e,
        isFetchingNextPage: false,
      );
      try {
        // If the retryer recorded failures, set them
        queryResult.failureCount = failureCount;
        queryResult.failureReason = e;
      } catch (_) {}
      queryResult.fetchNextPage = () => fetchNextPage();

      // Preserve any previously observed failureCount if the new value is missing
      try {
        if ((queryResult.failureCount == 0 || queryResult.failureReason == null) && _currentResult.failureCount > 0) {
          queryResult.failureCount = _currentResult.failureCount;
          queryResult.failureReason = _currentResult.failureReason ?? e;
        }
      } catch (_) {}

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

    // Use Retryer so next-page fetches respect retry semantics
    final retryer = Retryer<T?>(
      fn: () async => await _options.pageQueryFn(nextPage),
      retry: _options.retry ?? _client.defaultOptions.queries.retry,
      retryDelay: _options.retryDelay ?? _client.defaultOptions.queries.retryDelay,
      onFail: (failureCount, error) {
        debugPrint('DBG onFail next-page failureCount=$failureCount error=$error');
        final failRes = _currentResult.copyWith(isFetching: true, isFetchingNextPage: true);
        try {
          failRes.failureCount = failureCount;
          failRes.failureReason = error;
        } catch (_) {}
        _client.queryCache[cacheKey] = QueryCacheEntry(failRes, DateTime.now());
        _currentResult = failRes;
        _notify();
      },
    );

    final running = TrackedFuture<T?>(retryer.start());

    running.then((value) {
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
      final failureCount = retryer.failureCount;
      debugPrint('DBG next-page final status=QueryStatus.error failureCount=$failureCount failureReason=$e');
      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.error,
        data: <T>[],
        isFetching: false,
        error: e,
        isFetchingNextPage: false,
      );
      try {
        queryResult.failureCount = failureCount;
        queryResult.failureReason = e;
      } catch (_) {}
      queryResult.fetchNextPage = () => fetchNextPage();
      try {
        if ((queryResult.failureCount == 0 || queryResult.failureReason == null) && _currentResult.failureCount > 0) {
          queryResult.failureCount = _currentResult.failureCount;
          queryResult.failureReason = _currentResult.failureReason ?? e;
        }
      } catch (_) {}
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
          // Preserve failure metadata from cache entry
          try {
            q.failureCount = raw.failureCount;
            q.failureReason = raw.failureReason;
          } catch (_) {}
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
        final pageData = await _options.pageQueryFn(page);
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

    // Build or get a Query instance for this cache key and schedule GC.
    // This ensures infinite queries (which manage their cache directly)
    // are garbage collected when there are no observers.
    try {
      final qOptions = QueryOptions<T>(
        queryFn: () async => (await _options.pageQueryFn(_options.initialPageParam)) as T,
        queryKey: _options.queryKey,
        enabled: _options.enabled,
        gcTime: _options.gcTime,
      );

      final q = _client.queryCache.build<T>(_client, qOptions);
      q.scheduleGc();
    } catch (_) {}
  }

  void _notify() {
    // Debug: show what we notify observers with
    try {
      debugPrint('DBG notify status=${_currentResult.status} failureCount=${_currentResult.failureCount}');
    } catch (_) {}

    notifyAll((listener) {
      try {
        final typed = listener as void Function(InfiniteQueryResult<T>);
        typed(_currentResult);
      } catch (_) {}
    });
  }
}
