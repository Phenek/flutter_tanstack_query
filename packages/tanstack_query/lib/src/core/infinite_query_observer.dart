import 'package:meta/meta.dart';
import 'package:tanstack_query/tanstack_query.dart';

/// Observer for infinite/paginated queries.
///
/// Architecture mirrors React's `InfiniteQueryObserver`:
/// - `fetch()` injects [InfiniteQueryBehavior] into the options, then
///   delegates to `Query.fetch()` which is the single dedup gate (one
///   [Retryer] per in-flight fetch, checked synchronously).
/// - `createResult()` reads `currentQuery?.fetchMeta` — the authoritative
///   in-flight direction set synchronously by [Query.fetch()] — so that
///   `isFetchingNextPage` is never derived from the stale cached result.
///
/// [T] is the type of a single page result.
/// [TPageParam] is the type of the page parameter.
class InfiniteQueryObserver<T, TPageParam> extends QueryObserver<
    InfiniteData<T, TPageParam>, Object, InfiniteData<T, TPageParam>> {
  InfiniteData<T, TPageParam>? _lastPlaceholderData;
  dynamic _lastPlaceholderDataOption;

  InfiniteQueryObserver(super._client, super.options);

  /// Mirrors React's `InfiniteQueryObserver`: never hide cached pages behind
  /// a pending state on remount. Stale pages are shown immediately while a
  /// background refetch runs, then replaced silently when data arrives.
  @override
  @protected
  bool shouldClearStaleDataOnMount() => false;

  @override
  InfiniteQueryResult<T, TPageParam> getCurrentResult() =>
      _coerceResult(super.getCurrentResult());

  InfiniteQueryResult<T, TPageParam> _coerceResult(
      QueryResult<InfiniteData<T, TPageParam>> base) {
    if (base is InfiniteQueryResult<T, TPageParam>) return base;

    final opts = options as InfiniteQueryOptions<T, TPageParam>;
    var safeData = base.data; // null when pending with no cache — mirrors React's data: undefined
    var status = base.status;
    var error = base.error;
    var isPlaceholder = base.isPlaceholderData;

    if (opts.placeholderData != null &&
        (safeData == null || safeData.pages.isEmpty) &&
        status == QueryStatus.pending) {
      InfiniteData<T, TPageParam>? placeholderData;
      if (isPlaceholder && opts.placeholderData == _lastPlaceholderDataOption) {
        placeholderData = _lastPlaceholderData;
      } else {
        placeholderData = opts.resolvePlaceholderData(null, null);
      }
      if (placeholderData != null) {
        safeData = placeholderData;
        status = QueryStatus.success;
        error = null;
        isPlaceholder = true;
        _lastPlaceholderDataOption = opts.placeholderData;
        _lastPlaceholderData = placeholderData;
      }
    }

    return InfiniteQueryResult<T, TPageParam>(
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
    if (entry?.result is QueryResult<InfiniteData<T, TPageParam>>) {
      return super.shouldFetchOnMount();
    }
    return super.shouldFetchOnMount();
  }

  @override
  Future<QueryResult<InfiniteData<T, TPageParam>>> fetch(
      {FetchMeta? meta, bool? throwOnError}) async {
    updateQuery();

    final opts = options as InfiniteQueryOptions<T, TPageParam>;
    final q = currentQuery;
    if (q == null) return getCurrentResult();

    try {
      await q.fetch(
          meta: meta, behavior: InfiniteQueryBehavior<T, TPageParam>());
    } catch (e) {
      if (throwOnError == true) rethrow;
    }

    // The cache now holds QueryResult<InfiniteData<T, TPageParam>> directly
    // from the behavior. Wrap into InfiniteQueryResult for type safety and
    // to ensure isFetchingNextPage / isFetchingPreviousPage flags are set.
    final cacheKey = queryKeyToCacheKey(opts.queryKey);
    final settled = QueryClient.instance.queryCache[cacheKey]?.result;

    if (settled is InfiniteQueryResult<T, TPageParam>) return settled;

    if (settled is QueryResult<InfiniteData<T, TPageParam>>) {
      final wrapped = _toInfiniteResult(opts, settled, meta);
      QueryClient.instance.queryCache[cacheKey] =
          QueryCacheEntry(wrapped, DateTime.now());
      q.notifyObservers();
      return wrapped;
    }

    q.notifyObservers();
    return getCurrentResult();
  }

  /// Wraps a settled [QueryResult<InfiniteData<T, TPageParam>>] into a typed
  /// [InfiniteQueryResult] and computes the directional flags from [fetchMeta].
  InfiniteQueryResult<T, TPageParam> _toInfiniteResult(
    InfiniteQueryOptions<T, TPageParam> opts,
    QueryResult<InfiniteData<T, TPageParam>> res,
    FetchMeta? fetchMeta,
  ) {
    final data =
        res.data ?? InfiniteData<T, TPageParam>(pages: [], pageParams: []);
    final direction = fetchMeta?.fetchMore?.direction;
    final isFetchingNextPage =
        res.isFetching && direction == FetchDirection.forward;
    final isFetchingPrevPage =
        res.isFetching && direction == FetchDirection.backward;
    final isFetchNextError =
        res.isError && direction == FetchDirection.forward;
    final isFetchPrevError =
        res.isError && direction == FetchDirection.backward;

    return InfiniteQueryResult<T, TPageParam>(
      key: res.key,
      status: res.status,
      data: data,
      isFetching: res.isFetching,
      error: res.error,
      isFetchingNextPage: isFetchingNextPage,
      isFetchingPreviousPage: isFetchingPrevPage,
      isFetchNextPageError: isFetchNextError,
      isFetchPreviousPageError: isFetchPrevError,
      isRefetchError: res.isError && !isFetchNextError && !isFetchPrevError,
      isRefetching: res.isFetching && !isFetchingNextPage && !isFetchingPrevPage,
      hasNextPage: hasNextPage(opts, data),
      hasPreviousPage: hasPreviousPage(opts, data),
      fetchNextPage: hasNextPage(opts, data) ? fetchNextPage : null,
      fetchPreviousPage: fetchPreviousPage,
      isStale: res.isStale,
      dataUpdatedAt: res.dataUpdatedAt,
      isPlaceholderData: res.isPlaceholderData,
      failureCount: res.failureCount,
      failureReason: res.failureReason,
      refetch: ({bool? throwOnError}) => fetch(throwOnError: throwOnError),
      fetchMeta: fetchMeta,
    );
  }

  Future<InfiniteQueryResult<T, TPageParam>> fetchNextPage() async {
    final result = await fetch(
      meta: const FetchMeta(
          fetchMore: FetchMore(direction: FetchDirection.forward)),
    );
    return result as InfiniteQueryResult<T, TPageParam>;
  }

  Future<InfiniteQueryResult<T, TPageParam>> fetchPreviousPage() async {
    final result = await fetch(
      meta: const FetchMeta(
          fetchMore: FetchMore(direction: FetchDirection.backward)),
    );
    return result as InfiniteQueryResult<T, TPageParam>;
  }

  @override
  QueryResult<InfiniteData<T, TPageParam>> createResult(
      QueryResult<dynamic> res, QueryCacheEntry? entry) {
    final parentResult = super.createResult(res, entry);
    final opts = options as InfiniteQueryOptions<T, TPageParam>;

    // Extract the InfiniteData from the parent result; fall back to empty.
    InfiniteData<T, TPageParam>? safeData;
    var status = parentResult.status;
    var error = parentResult.error;
    try {
      safeData = parentResult.data;
    } catch (_) {
      safeData = null;
      status = QueryStatus.pending;
      error = null;
    }

    // React: data is undefined only for pending state (no cache yet).
    // For error/success states, fall back to empty InfiniteData so existing
    // error-state behaviour is preserved (data.pages == []).
    if (safeData == null && status != QueryStatus.pending) {
      safeData = InfiniteData<T, TPageParam>(pages: [], pageParams: []);
    }

    var isPlaceholder = parentResult.isPlaceholderData;
    if (opts.placeholderData != null &&
        (safeData == null || safeData.pages.isEmpty) &&
        status == QueryStatus.pending) {
      InfiniteData<T, TPageParam>? placeholderData;
      if (isPlaceholder && opts.placeholderData == _lastPlaceholderDataOption) {
        placeholderData = _lastPlaceholderData;
      } else {
        placeholderData = opts.resolvePlaceholderData(null, null);
      }
      if (placeholderData != null) {
        safeData = placeholderData;
        status = QueryStatus.success;
        error = null;
        isPlaceholder = true;
        _lastPlaceholderDataOption = opts.placeholderData;
        _lastPlaceholderData = placeholderData;
      }
    }

    // ── React parity: read direction from Query.fetchMeta (canonical in-flight
    // state) rather than from the cached result's fetchMeta.
    final fetchDirection = currentQuery?.fetchMeta?.fetchMore?.direction;

    final isFetchNextPageError =
        parentResult.isError && fetchDirection == FetchDirection.forward;
    final isFetchingNextPage =
        parentResult.isFetching && fetchDirection == FetchDirection.forward;
    final isFetchPreviousPageError =
        parentResult.isError && fetchDirection == FetchDirection.backward;
    final isFetchingPreviousPage =
        parentResult.isFetching && fetchDirection == FetchDirection.backward;

    return InfiniteQueryResult<T, TPageParam>(
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
      hasNextPage: hasNextPage(opts, safeData),
      hasPreviousPage: hasPreviousPage(opts, safeData),
      fetchNextPage: hasNextPage(opts, safeData) ? fetchNextPage : null,
      fetchPreviousPage: fetchPreviousPage,
      isStale: parentResult.isStale,
      dataUpdatedAt: parentResult.dataUpdatedAt,
      isPlaceholderData: isPlaceholder,
      failureCount: parentResult.failureCount,
      failureReason: parentResult.failureReason,
      refetch: parentResult.refetch,
      fetchMeta: parentResult.fetchMeta,
    );
  }
}
