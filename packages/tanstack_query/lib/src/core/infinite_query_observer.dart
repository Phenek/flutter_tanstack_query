import 'package:tanstack_query/tanstack_query.dart';

/// Observer for infinite/paginated queries.
///
/// This mirrors the JS `InfiniteQueryObserver` by extending `QueryObserver`
/// and overriding result creation to include pagination state and helpers.
class InfiniteQueryObserver<T>
    extends QueryObserver<List<T>, Object, List<T>> {
  List<T>? _lastPlaceholderData;
  dynamic _lastPlaceholderDataOption;
  InfiniteQueryObserver(QueryClient client, InfiniteQueryOptions<T> options)
      : super(client, options);

  @override
  void setOptions(QueryOptions<List<T>> options) {
    super.setOptions(options);
  }

  InfiniteQueryResult<T> getCurrentResult() =>
      _coerceResult(super.getCurrentResult());

  InfiniteQueryResult<T> _coerceResult(QueryResult<List<T>> base) {
    if (base is InfiniteQueryResult<T>) return base;

    final opts = options as InfiniteQueryOptions<T>;
    List<T> safeData = <T>[];
    var status = base.status;
    var error = base.error;
    var isPlaceholder = base.isPlaceholderData;
    try {
      if (base.data != null) {
        safeData = (base.data as List).cast<T>();
      }
    } catch (_) {
      safeData = <T>[];
      status = QueryStatus.pending;
      error = null;
    }

    if (opts.placeholderData != null &&
        safeData.isEmpty &&
        status == QueryStatus.pending) {
      dynamic placeholderData;
      if (isPlaceholder && opts.placeholderData == _lastPlaceholderDataOption) {
        placeholderData = _lastPlaceholderData;
      } else {
        placeholderData = opts.resolvePlaceholderPages(null, null);
      }

      if (placeholderData is List<T>) {
        safeData = placeholderData;
        status = QueryStatus.success;
        error = null;
        isPlaceholder = true;
        _lastPlaceholderDataOption = opts.placeholderData;
        _lastPlaceholderData = placeholderData;
      }
    }

    return InfiniteQueryResult<T>(
      key: base.key,
      status: status,
      data: safeData,
      isFetching: base.isFetching,
      error: error,
      isFetchingNextPage: false,
      isFetchingPreviousPage: false,
      isFetchNextPageError: false,
      isFetchPreviousPageError: false,
      isRefetchError: base.isError,
      isRefetching: base.isFetching,
      hasNextPage: hasNextPage(opts, safeData),
      hasPreviousPage: hasPreviousPage(opts, safeData),
      fetchNextPage: fetchNextPage,
      fetchPreviousPage: fetchPreviousPage,
      isStale: base.isStale,
      dataUpdatedAt: base.dataUpdatedAt,
      isPlaceholderData: isPlaceholder,
      failureCount: base.failureCount,
      failureReason: base.failureReason,
      refetch: base.refetch,
      fetchMeta: base.fetchMeta,
    );
  }

  @override
  bool shouldFetchOnMount() {
    final cacheKey = queryKeyToCacheKey(options.queryKey);
    final entry = QueryClient.instance.queryCache[cacheKey];

    if (entry?.result is InfiniteQueryResult) {
      try {
        final raw = entry!.result as InfiniteQueryResult;
        if (raw.data != null) {
          (raw.data as List).cast<T>();
        }
      } catch (_) {
        return true;
      }
    }

    return super.shouldFetchOnMount();
  }

  @override
  Future<QueryResult<List<T>>> fetch({FetchMeta? meta, bool? throwOnError}) async {
    return await _fetchInfinite(meta: meta, throwOnError: throwOnError);
  }

  Future<InfiniteQueryResult<T>> fetchNextPage() async {
    final result = await fetch(
      meta: const FetchMeta(
          fetchMore: FetchMore(direction: FetchDirection.forward)),
    );
    return result as InfiniteQueryResult<T>;
  }

  Future<InfiniteQueryResult<T>> fetchPreviousPage() async {
    final result = await fetch(
      meta: const FetchMeta(
          fetchMore: FetchMore(direction: FetchDirection.backward)),
    );
    return result as InfiniteQueryResult<T>;
  }

  Future<InfiniteQueryResult<T>> _fetchInfinite(
      {FetchMeta? meta, bool? throwOnError}) async {
    final opts = options as InfiniteQueryOptions<T>;
    final cacheKey = queryKeyToCacheKey(opts.queryKey);
    final cacheEntry = QueryClient.instance.queryCache[cacheKey];

    final current = getCurrentResult();
    final currentData = current.data ?? <T>[];
    final hasPrevData = currentData.isNotEmpty;

    final direction = meta?.fetchMore?.direction;
    final isFetchingNextPage = direction == FetchDirection.forward;
    final isFetchingPreviousPage = direction == FetchDirection.backward;

    if (isFetchingNextPage && current.isFetchingNextPage) {
      return current;
    }
    if (isFetchingPreviousPage && current.isFetchingPreviousPage) {
      return current;
    }

    if (direction == FetchDirection.forward &&
        (opts.getNextPageParam == null || !hasPrevData)) {
      return current;
    }
    if (direction == FetchDirection.backward &&
        (opts.getPreviousPageParam == null || !hasPrevData)) {
      return current;
    }

    final pending = InfiniteQueryResult<T>(
      key: cacheKey,
      status: hasPrevData ? QueryStatus.success : QueryStatus.pending,
      data: currentData,
      isFetching: true,
      error: null,
      isFetchingNextPage: isFetchingNextPage,
      isFetchingPreviousPage: isFetchingPreviousPage,
      isRefetching: !isFetchingNextPage && !isFetchingPreviousPage,
      isRefetchError: false,
      isFetchNextPageError: false,
      isFetchPreviousPageError: false,
      hasNextPage: hasNextPage(opts, currentData),
      hasPreviousPage: hasPreviousPage(opts, currentData),
      dataUpdatedAt: current.dataUpdatedAt,
      isPlaceholderData: current.isPlaceholderData,
      failureCount: current.failureCount,
      failureReason: current.failureReason,
      refetch: ({bool? throwOnError}) => fetch(throwOnError: throwOnError),
      fetchMeta: meta,
      fetchNextPage: fetchNextPage,
      fetchPreviousPage: fetchPreviousPage,
    );

    // Share in-flight fetches for the initial/refetch flow (no direction)
    if (direction == null &&
        cacheEntry?.queryFnRunning != null &&
        !cacheEntry!.queryFnRunning!.isCompleted &&
        !cacheEntry.queryFnRunning!.hasError) {
      try {
        await cacheEntry.queryFnRunning;
      } catch (_) {
        // ignore, final cache state will be read below
      }
      final cachedResult = QueryClient.instance.queryCache[cacheKey]?.result;
      if (cachedResult is InfiniteQueryResult<T>) {
        return cachedResult;
      }
      if (cachedResult is QueryResult<List<T>>) {
        return _coerceResult(cachedResult);
      }
      return current;
    }

    TrackedFuture<T?>? tracked;
    QueryCacheEntry? nextEntry = cacheEntry;
    if (direction == null) {
      final retryer = Retryer<T?>(
        fn: () async => await opts.pageQueryFn(opts.initialPageParam),
        retry: opts.retry ?? QueryClient.instance.defaultOptions.queries.retry,
        retryDelay: opts.retryDelay ??
            QueryClient.instance.defaultOptions.queries.retryDelay,
      );
      tracked = TrackedFuture<T?>(retryer.start());
      QueryClient.instance.queryCache[cacheKey] = nextEntry = QueryCacheEntry(
        pending,
        DateTime.now(),
        queryFnRunning: tracked,
      );

      try {
        final value = await tracked;
        if (value == null) return current;
        final queryResult = InfiniteQueryResult<T>(
          key: cacheKey,
          status: QueryStatus.success,
          data: [value],
          isFetching: false,
          error: null,
          isFetchingNextPage: false,
          isFetchingPreviousPage: false,
          isRefetching: false,
          isRefetchError: false,
          isFetchNextPageError: false,
          isFetchPreviousPageError: false,
          hasNextPage: hasNextPage(opts, [value]),
          hasPreviousPage: hasPreviousPage(opts, [value]),
          dataUpdatedAt: DateTime.now().millisecondsSinceEpoch,
          isPlaceholderData: false,
          refetch: ({bool? throwOnError}) => fetch(throwOnError: throwOnError),
          fetchMeta: meta,
          fetchNextPage: fetchNextPage,
          fetchPreviousPage: fetchPreviousPage,
        );
        QueryClient.instance.queryCache[cacheKey] =
            QueryCacheEntry(queryResult, DateTime.now());
        QueryClient.instance.queryCache.config.onSuccess?.call([value]);
        return queryResult;
      } catch (e) {
        final failureCount = retryer.failureCount;
        final queryResult = InfiniteQueryResult<T>(
          key: cacheKey,
          status: QueryStatus.error,
          data: currentData,
          isFetching: false,
          error: e,
          isFetchingNextPage: false,
          isFetchingPreviousPage: false,
          isRefetching: false,
          isRefetchError: true,
          isFetchNextPageError: false,
          isFetchPreviousPageError: false,
          hasNextPage: hasNextPage(opts, currentData),
          hasPreviousPage: hasPreviousPage(opts, currentData),
          dataUpdatedAt: current.dataUpdatedAt,
          isPlaceholderData: current.isPlaceholderData,
          failureCount: failureCount,
          failureReason: e,
          refetch: ({bool? throwOnError}) => fetch(throwOnError: throwOnError),
          fetchMeta: meta,
          fetchNextPage: fetchNextPage,
          fetchPreviousPage: fetchPreviousPage,
        );
        QueryClient.instance.queryCache[cacheKey] =
            QueryCacheEntry(queryResult, DateTime.now());
        QueryClient.instance.queryCache.config.onError?.call(e);
        if (throwOnError == true) rethrow;
        return queryResult;
      }
    }

    QueryClient.instance.queryCache[cacheKey] =
        QueryCacheEntry(pending, DateTime.now());

    try {
      List<T> newData = <T>[];

      if (direction == FetchDirection.forward) {
        final nextParam = opts.getNextPageParam!(currentData.last);
        if (nextParam == null) return current;
        final pageData = await _fetchInfinitePage(
          opts,
          nextParam,
          currentData,
          meta: meta,
          isFetchingNextPage: true,
          isFetchingPreviousPage: false,
        );
        if (pageData == null) return current;
        newData = [...currentData, pageData];
      } else if (direction == FetchDirection.backward) {
        final prevParam = opts.getPreviousPageParam!(currentData.first);
        if (prevParam == null) return current;
        final pageData = await _fetchInfinitePage(
          opts,
          prevParam,
          currentData,
          meta: meta,
          isFetchingNextPage: false,
          isFetchingPreviousPage: true,
        );
        if (pageData == null) return current;
        newData = [pageData, ...currentData];
      } else {
        newData = await _refetchAllPages(opts, currentData);
      }

      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.success,
        data: newData,
        isFetching: false,
        error: null,
        isFetchingNextPage: false,
        isFetchingPreviousPage: false,
        isRefetching: false,
        isRefetchError: false,
        isFetchNextPageError: false,
        isFetchPreviousPageError: false,
        hasNextPage: hasNextPage(opts, newData),
        hasPreviousPage: hasPreviousPage(opts, newData),
        dataUpdatedAt: DateTime.now().millisecondsSinceEpoch,
        isPlaceholderData: false,
        refetch: ({bool? throwOnError}) => fetch(throwOnError: throwOnError),
        fetchMeta: meta,
        fetchNextPage: fetchNextPage,
        fetchPreviousPage: fetchPreviousPage,
      );

      QueryClient.instance.queryCache[cacheKey] =
          QueryCacheEntry(queryResult, DateTime.now());
      QueryClient.instance.queryCache.config.onSuccess?.call(newData);
      return queryResult;
    } catch (e) {
      final cached = QueryClient.instance.queryCache[cacheKey]?.result;
      var failureCount = current.failureCount;
      Object? failureReason = e;
      if (cached is InfiniteQueryResult) {
        failureCount = cached.failureCount;
        failureReason = cached.failureReason ?? e;
      }
      final errorData =
          isFetchingNextPage || isFetchingPreviousPage ? <T>[] : currentData;
      final queryResult = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.error,
        data: errorData,
        isFetching: false,
        error: e,
        isFetchingNextPage: false,
        isFetchingPreviousPage: false,
        isRefetching: false,
        isRefetchError: true,
        isFetchNextPageError: isFetchingNextPage,
        isFetchPreviousPageError: isFetchingPreviousPage,
        hasNextPage: hasNextPage(opts, currentData),
        hasPreviousPage: hasPreviousPage(opts, currentData),
        dataUpdatedAt: current.dataUpdatedAt,
        isPlaceholderData: current.isPlaceholderData,
        failureCount: failureCount,
        failureReason: failureReason,
        refetch: ({bool? throwOnError}) => fetch(throwOnError: throwOnError),
        fetchMeta: meta,
        fetchNextPage: fetchNextPage,
        fetchPreviousPage: fetchPreviousPage,
      );
      QueryClient.instance.queryCache[cacheKey] =
          QueryCacheEntry(queryResult, DateTime.now());
      QueryClient.instance.queryCache.config.onError?.call(e);
      if (throwOnError == true) rethrow;
      return queryResult;
    }
  }

  Future<T?> _fetchInfinitePage(
    InfiniteQueryOptions<T> opts,
    int pageParam,
    List<T> currentData, {
    FetchMeta? meta,
    required bool isFetchingNextPage,
    required bool isFetchingPreviousPage,
  }) async {
    final retryer = Retryer<T?>(
      fn: () async => await opts.pageQueryFn(pageParam),
      retry: opts.retry ?? QueryClient.instance.defaultOptions.queries.retry,
      retryDelay: opts.retryDelay ??
          QueryClient.instance.defaultOptions.queries.retryDelay,
    );

    try {
      return await retryer.start();
    } catch (e) {
      final cacheKey = queryKeyToCacheKey(opts.queryKey);
      final errorData =
          isFetchingNextPage || isFetchingPreviousPage ? <T>[] : currentData;
      final failRes = InfiniteQueryResult<T>(
        key: cacheKey,
        status: QueryStatus.error,
        data: errorData,
        isFetching: false,
        error: e,
        isFetchingNextPage: isFetchingNextPage,
        isFetchingPreviousPage: isFetchingPreviousPage,
        isRefetching: false,
        isRefetchError: true,
        isFetchNextPageError: isFetchingNextPage,
        isFetchPreviousPageError: isFetchingPreviousPage,
        hasNextPage: hasNextPage(opts, currentData),
        hasPreviousPage: hasPreviousPage(opts, currentData),
        failureCount: retryer.failureCount,
        failureReason: e,
        refetch: ({bool? throwOnError}) => fetch(throwOnError: throwOnError),
        fetchMeta: meta,
        fetchNextPage: fetchNextPage,
        fetchPreviousPage: fetchPreviousPage,
      );
      QueryClient.instance.queryCache[cacheKey] =
          QueryCacheEntry(failRes, DateTime.now());
      rethrow;
    }
  }

  Future<List<T>> _refetchAllPages(
      InfiniteQueryOptions<T> opts, List<T> currentData) async {
    final List<T> data = [];
    final int pageCount = currentData.isNotEmpty ? currentData.length : 1;
    int? pageParam = opts.initialPageParam;

    for (var i = 0; i < pageCount; i++) {
      final pageData = await _fetchInfinitePage(
        opts,
        pageParam!,
        currentData,
        isFetchingNextPage: false,
        isFetchingPreviousPage: false,
      );
      if (pageData == null) break;
      data.add(pageData);

      if (opts.getNextPageParam == null) break;
      final nextParam = opts.getNextPageParam!(pageData);
      if (nextParam == null) break;
      pageParam = nextParam;
    }

    return data;
  }

  @override
  QueryResult<List<T>> createResult(
      QueryResult<dynamic> res, QueryCacheEntry? entry) {
    final parentResult = super.createResult(res, entry);
    final opts = options as InfiniteQueryOptions<T>;

    List<T> safeData = <T>[];
    var status = parentResult.status;
    var error = parentResult.error;
    try {
      if (parentResult.data != null) {
        safeData = (parentResult.data as List).cast<T>();
      }
    } catch (_) {
      safeData = <T>[];
      status = QueryStatus.pending;
      error = null;
    }

    var isPlaceholder = parentResult.isPlaceholderData;
    if (opts.placeholderData != null &&
        safeData.isEmpty &&
        status == QueryStatus.pending) {
      dynamic placeholderData;
      if (isPlaceholder && opts.placeholderData == _lastPlaceholderDataOption) {
        placeholderData = _lastPlaceholderData;
      } else {
        placeholderData = opts.resolvePlaceholderPages(null, null);
      }

      if (placeholderData is List<T>) {
        safeData = placeholderData;
        status = QueryStatus.success;
        error = null;
        isPlaceholder = true;
        _lastPlaceholderDataOption = opts.placeholderData;
        _lastPlaceholderData = placeholderData;
      }
    }

    final fetchDirection = parentResult.fetchMeta?.fetchMore?.direction;

    final isFetchNextPageError =
        parentResult.isError && fetchDirection == FetchDirection.forward;
    final isFetchingNextPage =
        parentResult.isFetching && fetchDirection == FetchDirection.forward;

    final isFetchPreviousPageError =
        parentResult.isError && fetchDirection == FetchDirection.backward;
    final isFetchingPreviousPage =
        parentResult.isFetching && fetchDirection == FetchDirection.backward;

    final result = InfiniteQueryResult<T>(
      key: parentResult.key,
      status: status,
      data: safeData,
      isFetching: parentResult.isFetching,
      error: error,
      isFetchingNextPage: isFetchingNextPage,
      isFetchingPreviousPage: isFetchingPreviousPage,
      isFetchNextPageError: isFetchNextPageError,
      isFetchPreviousPageError: isFetchPreviousPageError,
      isRefetchError: parentResult.isError &&
          !isFetchNextPageError &&
          !isFetchPreviousPageError,
      isRefetching: parentResult.isFetching &&
          !isFetchingNextPage &&
          !isFetchingPreviousPage,
      hasNextPage: hasNextPage(opts, parentResult.data),
      hasPreviousPage: hasPreviousPage(opts, parentResult.data),
      fetchNextPage: hasNextPage(opts, parentResult.data) ? fetchNextPage : null,
      fetchPreviousPage: fetchPreviousPage,
      isStale: parentResult.isStale,
      dataUpdatedAt: parentResult.dataUpdatedAt,
      isPlaceholderData: isPlaceholder,
      failureCount: parentResult.failureCount,
      failureReason: parentResult.failureReason,
      refetch: parentResult.refetch,
      fetchMeta: parentResult.fetchMeta,
    );

    return result;
  }
}
