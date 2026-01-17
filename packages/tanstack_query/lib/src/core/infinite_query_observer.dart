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
    required super.queryKey,
    required Future<T?> Function(int pageParam) queryFn,
    required this.initialPageParam,
    this.getNextPageParam,
    this.getPreviousPageParam,
    this.debounceTime,
    super.staleTime,
    super.enabled,
    super.refetchOnWindowFocus,
    super.refetchOnReconnect,
    super.refetchOnMount,
    super.gcTime,
    super.retry,
    super.retryOnMount,
    super.retryDelay,
    dynamic super.initialData,
    dynamic super.initialDataUpdatedAt,
    dynamic super.placeholderData,
  })  : pageQueryFn = queryFn,
        super(
          queryFn: () async => (await queryFn(initialPageParam)) as T,
        );

  /// Evaluate initial data for infinite queries as a list of pages.
  List<T>? resolveInitialPages() {
    try {
      if (initialData is InitialDataFn<List<T>>) {
        return (initialData as InitialDataFn<List<T>>)();
      }
      return initialData as List<T>?;
    } catch (_) {
      return null;
    }
  }

  /// Evaluate placeholder data for infinite queries as a list of pages.
  List<T>? resolvePlaceholderPages(
      List<T>? previousValue, dynamic previousQuery) {
    try {
      if (placeholderData is PlaceholderDataFn<List<T>>) {
        return (placeholderData as PlaceholderDataFn<List<T>>)(
            previousValue, previousQuery);
      }
      return placeholderData as List<T>?;
    } catch (_) {
      return null;
    }
  }
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

  // For placeholderData behavior
  Query? _lastQueryWithDefinedData;
  dynamic _lastPlaceholderDataOption;

  void setOptions(InfiniteQueryOptions<T> options) {
    _options = options;
  }

  /// Try to safely cast an untyped [InfiniteQueryResult] (often coming from
  /// the cache) into a typed [InfiniteQueryResult<T>]. If the underlying
  /// data cannot be cast to `T` this returns `null` so the observer can
  /// treat the cache entry as absent instead of throwing a [TypeError].
  InfiniteQueryResult<T>? _tryCastInfiniteQueryResult(
      dynamic raw, void Function()? fetchNextPageCallback) {
    if (raw is! InfiniteQueryResult) return null;
    try {
      final List<T> data =
          raw.data == null ? <T>[] : (raw.data as List).cast<T>();
      final q = InfiniteQueryResult<T>(
        key: raw.key,
        status: raw.status,
        data: data,
        isFetching: raw.isFetching,
        error: raw.error,
        isFetchingNextPage: raw.isFetchingNextPage,
      );
      try {
        q.failureCount = raw.failureCount;
        q.failureReason = raw.failureReason;
      } catch (_) {}
      q.fetchNextPage = fetchNextPageCallback ?? () {};
      return q;
    } catch (e) {
      debugPrint(
          'DBG: unable to cast cached InfiniteQueryResult to typed variant: $e');
      return null;
    }
  }

  @override
  void onSubscribe() {
    // Delegate mount-time fetching policy to shouldFetchOnMount to match
    // the QueryObserver behavior and the new `refetchOnMount` option.
    if (shouldFetchOnMount()) {
      if (_options.debounceTime == null) {
        refetch();
      } else {
        _setLoadingWithDebounce();
      }
    }
  }

  bool shouldFetchOnMount() {
    final cacheKey = queryKeyToCacheKey(_options.queryKey);
    final entry = _client.queryCache[cacheKey];

    final enabled = _options.enabled ?? _client.defaultOptions.queries.enabled;

    final isErrored = entry != null &&
        entry.result is QueryResult &&
        (entry.result as QueryResult).isError;
    final retryOnMount =
        _options.retryOnMount ?? _client.defaultOptions.queries.retryOnMount;

    final isStale = entry == null ||
        (DateTime.now().difference(entry.timestamp).inMilliseconds >
            (_options.staleTime ?? 0));

    final refetchOnMount = _options.refetchOnMount ??
        _client.defaultOptions.queries.refetchOnMount;

    return enabled &&
        refetchOnMount &&
        (entry == null || (isErrored && retryOnMount) || isStale);
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

    // Snapshot which observer-facing result to show while the initial fetch runs.
    InfiniteQueryResult<T>? observerSnapshot;

    if (cacheEntry == null ||
        cacheEntry.queryFnRunning == null ||
        cacheEntry.queryFnRunning!.isCompleted ||
        cacheEntry.queryFnRunning!.hasError) {
      final prevRes = _tryCastInfiniteQueryResult(
          cacheEntry?.result, () => fetchNextPage());

      // Determine whether there is real cached data (do NOT treat observer
      // placeholder data as cache data — placeholder should not be persisted).
      final bool prevHasCacheData = (prevRes?.data?.isNotEmpty == true);
      final List<T> cachePrevData =
          prevHasCacheData ? (prevRes!.data as List<T>) : <T>[];

      // For the observer we may still want to show the placeholder/initial
      // data while fetching even if it is not persisted to cache.
      final bool localHasData = (_currentResult.data?.isNotEmpty == true);
      final bool hasPrevDataForObserver = prevHasCacheData || localHasData;
      final List<T> observerPrevData =
          prevHasCacheData ? cachePrevData : (_currentResult.data ?? <T>[]);

      // Preserve placeholder flag from the observer if the data we are using
      // originates from the observer's placeholder/initial state.
      final bool prevIsPlaceholder =
          _currentResult.isPlaceholderData == true && !prevHasCacheData;

      // Build the observer-facing result (keeps placeholder if appropriate)
      final observerResult = InfiniteQueryResult<T>(
          key: cacheKey,
          status: hasPrevDataForObserver
              ? QueryStatus.success
              : QueryStatus.pending,
          data: observerPrevData,
          isFetching: true,
          error: null,
          isFetchingNextPage: false);
      try {
        observerResult.isPlaceholderData = prevIsPlaceholder;
      } catch (_) {}

      // Build the cache-facing result (do NOT persist placeholder data)
      final cacheFacingResult = InfiniteQueryResult<T>(
          key: cacheKey,
          status: prevHasCacheData ? QueryStatus.success : QueryStatus.pending,
          data: cachePrevData,
          isFetching: true,
          error: null,
          isFetchingNextPage: false);

      // Use Retryer to respect retry/retryDelay options
      retryer = Retryer<T?>(
        fn: () async => await _options.pageQueryFn(_options.initialPageParam),
        retry: _options.retry ?? _client.defaultOptions.queries.retry,
        retryDelay:
            _options.retryDelay ?? _client.defaultOptions.queries.retryDelay,
        onFail: (failureCount, error) {
          // Debug: observe retry failures
          debugPrint(
              'DBG onFail initial fetch failureCount=$failureCount error=$error');
          // Update cache to reflect failure while still retrying (do not persist placeholder)
          final failRes = InfiniteQueryResult<T>(
              key: cacheKey,
              status:
                  prevHasCacheData ? QueryStatus.success : QueryStatus.pending,
              data: cachePrevData,
              isFetching: true,
              error: error,
              isFetchingNextPage: false);
          try {
            failRes.failureCount = failureCount;
            failRes.failureReason = error;
          } catch (_) {}
          _client.queryCache[cacheKey] =
              QueryCacheEntry(failRes, DateTime.now(), queryFnRunning: tracked);
          _currentResult = observerResult;
          _notify();
        },
      );

      // Assign observer result to be shown immediately (but persist cacheFacingResult)
      tracked = TrackedFuture<T?>(retryer.start());
      _client.queryCache[cacheKey] = cacheEntry = QueryCacheEntry(
          cacheFacingResult, DateTime.now(),
          queryFnRunning: tracked);
      _currentResult = observerResult;
      observerSnapshot = observerResult;
      shouldUpdateTheCache = true;
    }

    final running = cacheEntry.queryFnRunning;
    if (running == null) return;

    // Show the observer-facing result (may include placeholder data) while the
    // running fetch completes. Prefer the snapshot we captured above, or fall
    // back to the cache entry if none.
    _currentResult =
        observerSnapshot ?? (cacheEntry.result as InfiniteQueryResult<T>);
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
      if (shouldUpdateTheCache) {
        _client.queryCache[cacheKey] =
            QueryCacheEntry(queryResult, DateTime.now());
      }
      _client.queryCache.config.onSuccess?.call(value);
      _notify();
    } catch (e) {
      final failureCount = retryer?.failureCount ?? 0;
      debugPrint(
          'DBG final status=QueryStatus.error failureCount=$failureCount failureReason=$e');
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
        if ((queryResult.failureCount == 0 ||
                queryResult.failureReason == null) &&
            _currentResult.failureCount > 0) {
          queryResult.failureCount = _currentResult.failureCount;
          queryResult.failureReason = _currentResult.failureReason ?? e;
        }
      } catch (_) {}

      _currentResult = queryResult;
      if (shouldUpdateTheCache) {
        _client.queryCache[cacheKey] =
            QueryCacheEntry(queryResult, DateTime.now());
      }
      _client.queryCache.config.onError?.call(e);
      _notify();
    }
  }

  void _setLoadingWithDebounce() {
    final cacheKey = queryKeyToCacheKey(_options.queryKey);
    _currentResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.pending,
        data: [],
        isFetching: true,
        error: null,
        isFetchingNextPage: false);
    _notify();

    _timer?.cancel();
    _timer = Timer(_options.debounceTime!, () => refetch());
  }

  void fetchNextPage() {
    final hasData =
        _currentResult.data != null && _currentResult.data!.isNotEmpty;
    final nextPage = _options.getNextPageParam != null && hasData
        ? _options.getNextPageParam!(_currentResult.data!.last)
        : _currentPage;

    if (nextPage <= _currentPage || _currentResult.isFetchingNextPage) return;

    _currentPage = nextPage;
    final cacheKey = queryKeyToCacheKey(_options.queryKey);

    final queryLoadingMore =
        _currentResult.copyWith(isFetching: true, isFetchingNextPage: true);
    _currentResult = queryLoadingMore;
    _notify();

    // Use Retryer so next-page fetches respect retry semantics
    final retryer = Retryer<T?>(
      fn: () async => await _options.pageQueryFn(nextPage),
      retry: _options.retry ?? _client.defaultOptions.queries.retry,
      retryDelay:
          _options.retryDelay ?? _client.defaultOptions.queries.retryDelay,
      onFail: (failureCount, error) {
        debugPrint(
            'DBG onFail next-page failureCount=$failureCount error=$error');
        final failRes =
            _currentResult.copyWith(isFetching: true, isFetchingNextPage: true);
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
      _client.queryCache[cacheKey] =
          QueryCacheEntry(queryResult, DateTime.now());
      _client.queryCache.config.onSuccess?.call(value);
      _notify();
    }).catchError((e) {
      final failureCount = retryer.failureCount;
      debugPrint(
          'DBG next-page final status=QueryStatus.error failureCount=$failureCount failureReason=$e');
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
        if ((queryResult.failureCount == 0 ||
                queryResult.failureReason == null) &&
            _currentResult.failureCount > 0) {
          queryResult.failureCount = _currentResult.failureCount;
          queryResult.failureReason = _currentResult.failureReason ?? e;
        }
      } catch (_) {}
      _currentResult = queryResult;
      _client.queryCache[cacheKey] =
          QueryCacheEntry(queryResult, DateTime.now());
      _client.queryCache.config.onError?.call(e);
      _notify();
    });
  }

  void _initFromCache() {
    final cacheKey = queryKeyToCacheKey(_options.queryKey);
    final cacheEntry = _client.queryCache[cacheKey];

    // If cache entry exists, prefer it (and possibly use placeholderData when empty)
    if (cacheEntry != null && cacheEntry.result is InfiniteQueryResult) {
      final rawCasted =
          _tryCastInfiniteQueryResult(cacheEntry.result, () => fetchNextPage());

      // If we couldn't cast the cached result to the expected generic type,
      // treat it as if there was no cache entry to avoid runtime type errors.
      if (rawCasted == null) {
        debugPrint(
            'DBG: skipping cache entry due to type mismatch for key=$cacheKey');
      } else {
        final raw = rawCasted;

        // Track last query with defined data
        if (raw.data?.isNotEmpty == true) {
          _lastQueryWithDefinedData = null; // nothing useful to attach here
        }

        // If there's no real data but placeholderData is provided, use it
        if ((raw.data?.isEmpty ?? true) && _options.placeholderData != null) {
          dynamic placeholderData;
          if (_currentResult.isPlaceholderData &&
              _options.placeholderData == _lastPlaceholderDataOption) {
            placeholderData = _currentResult.data;
          } else {
            placeholderData = _options.resolvePlaceholderPages(
                _lastQueryWithDefinedData?.entry?.result?.data,
                _lastQueryWithDefinedData);
          }

          if (placeholderData != null && placeholderData is List<T>) {
            _currentResult = InfiniteQueryResult<T>(
                key: queryKeyToCacheKey(_options.queryKey),
                status: QueryStatus.success,
                data: placeholderData,
                isFetching: false,
                error: null,
                isFetchingNextPage: false);
            _currentResult.fetchNextPage = () => fetchNextPage();
            _currentResult.isPlaceholderData = true;
            _lastPlaceholderDataOption = _options.placeholderData;
            return;
          }
        }

        _currentResult = raw;
        _currentResult.fetchNextPage = () => fetchNextPage();
        return;
      }
    }

    // No cache entry: if initialData is provided, seed it into the observer and cache
    if (_options.initialData != null) {
      dynamic initData;
      initData = _options.resolveInitialPages();

      if (initData != null && initData is List<T>) {
        final int? updatedAt = _options.resolveInitialDataUpdatedAt();

        final q = InfiniteQueryResult<T>(
            key: cacheKey,
            status: QueryStatus.success,
            data: initData,
            isFetching: false,
            error: null,
            isFetchingNextPage: false);
        q.fetchNextPage = () => fetchNextPage();
        try {
          q.dataUpdatedAt = updatedAt ?? 0;
          q.isPlaceholderData = false;
        } catch (_) {}

        _currentResult = q;
        // Persist initialData to cache; if updatedAt was not provided we
        // intentionally set the cache timestamp to epoch (0) so it is treated
        // as stale by default and will refetch on mount unless staleTime is set.
        final ts = DateTime.fromMillisecondsSinceEpoch(q.dataUpdatedAt ?? 0);
        _client.queryCache[cacheKey] =
            QueryCacheEntry<InfiniteQueryResult<T>>(q, ts);
        return;
      }
    }

    // If no cache entry and placeholderData is provided, use it for the observer
    if (_options.placeholderData != null) {
      dynamic placeholderData;
      if (_currentResult.isPlaceholderData &&
          _options.placeholderData == _lastPlaceholderDataOption) {
        placeholderData = _currentResult.data;
      } else {
        placeholderData = _options.resolvePlaceholderPages(null, null);
      }

      if (placeholderData != null && placeholderData is List<T>) {
        final q = InfiniteQueryResult<T>(
            key: cacheKey,
            status: QueryStatus.success,
            data: placeholderData,
            isFetching: false,
            error: null,
            isFetchingNextPage: false);
        q.fetchNextPage = () => fetchNextPage();
        q.isPlaceholderData = true;
        _lastPlaceholderDataOption = _options.placeholderData;
        _currentResult = q;
        return;
      }
    }

    // Fallback: leave current result as initial pending state
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
      } else if (event.type == QueryCacheEventType.added ||
          event.type == QueryCacheEventType.updated) {
        // Use the safe casting helper to avoid TypeError on generic mismatches
        final dynamic rawEntry = event.entry?.result;
        final raw =
            _tryCastInfiniteQueryResult(rawEntry, () => fetchNextPage());
        if (raw == null) return;

        // If no data but placeholderData is provided, try to use it
        if ((raw.data?.isEmpty ?? true) && _options.placeholderData != null) {
          dynamic placeholderData;
          if (_currentResult.isPlaceholderData &&
              _options.placeholderData == _lastPlaceholderDataOption) {
            placeholderData = _currentResult.data;
          } else {
            try {
              if (_options.placeholderData is PlaceholderDataFn<List<T>>) {
                placeholderData = (_options.placeholderData
                    as PlaceholderDataFn<List<T>>)(null, null);
              } else {
                placeholderData = _options.placeholderData as List<T>?;
              }
            } catch (_) {
              placeholderData = null;
            }
          }

          if (placeholderData != null && placeholderData is List<T>) {
            final q = InfiniteQueryResult<T>(
                key: queryKeyToCacheKey(_options.queryKey),
                status: QueryStatus.success,
                data: placeholderData,
                isFetching: raw.isFetching,
                error: raw.error,
                isFetchingNextPage: raw.isFetchingNextPage);
            // Preserve failure metadata from cache entry
            try {
              q.failureCount = raw.failureCount;
              q.failureReason = raw.failureReason;
            } catch (_) {}
            q.fetchNextPage = () => fetchNextPage();
            q.isPlaceholderData = true;
            _lastPlaceholderDataOption = _options.placeholderData;
            _currentResult = q;
            _notify();
            return;
          }
        }

        // Use the safely casted raw value directly
        final q = InfiniteQueryResult<T>(
            key: queryKeyToCacheKey(_options.queryKey),
            status: raw.status,
            data: raw.data ?? <T>[],
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
      } else if (event.type == QueryCacheEventType.refetch ||
          (event.type == QueryCacheEventType.refetchOnWindowFocus &&
              (_options.refetchOnWindowFocus ??
                  _client.defaultOptions.queries.refetchOnWindowFocus)) ||
          (event.type == QueryCacheEventType.refetchOnReconnect &&
              (_options.refetchOnReconnect ??
                  _client.defaultOptions.queries.refetchOnReconnect))) {
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
      // Preserve previous data (including placeholder) while refetching pages
      final prevRes = _tryCastInfiniteQueryResult(
          _client.queryCache[cacheKey]?.result, () => fetchNextPage());
      final bool prevHasData = prevRes?.data?.isNotEmpty == true;
      final bool localHasData = _currentResult.data?.isNotEmpty == true;
      final bool hasPrevData = prevHasData || localHasData;
      final List<T> prevData = prevHasData
          ? (prevRes!.data as List<T>)
          : (_currentResult.data ?? <T>[]);
      final bool prevIsPlaceholder =
          _currentResult.isPlaceholderData == true && !prevHasData;

      var queryResult = InfiniteQueryResult<T>(
          key: cacheKey,
          status: hasPrevData ? QueryStatus.success : QueryStatus.pending,
          data: prevData,
          isFetching: true,
          error: null,
          isFetchingNextPage: false);
      queryResult.fetchNextPage = () => fetchNextPage();
      try {
        queryResult.isPlaceholderData = prevIsPlaceholder;
      } catch (_) {}
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
      // annotate update time
      try {
        queryResult.dataUpdatedAt = DateTime.now().millisecondsSinceEpoch;
        queryResult.isPlaceholderData = false;
      } catch (_) {}
      _currentResult = queryResult;
      _client.queryCache[queryKeyToCacheKey(_options.queryKey)] =
          QueryCacheEntry(queryResult, DateTime.now());
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
        queryFn: () async =>
            (await _options.pageQueryFn(_options.initialPageParam)) as T,
        queryKey: _options.queryKey,
        enabled: _options.enabled,
        gcTime: _options.gcTime,
      );

      final q = _client.queryCache.build<T>(_client, qOptions);
      q.scheduleGc();
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
