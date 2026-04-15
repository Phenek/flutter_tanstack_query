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
class InfiniteQueryObserver<T> extends QueryObserver<List<T>, Object, List<T>> {
  List<T>? _lastPlaceholderData;
  dynamic _lastPlaceholderDataOption;

  InfiniteQueryObserver(super._client, super.options);

  @override
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

    // Accept both InfiniteQueryResult (legacy) and plain QueryResult<List<T>>
    // (written by the new Query.fetch() + InfiniteQueryBehavior path).
    if (entry?.result is InfiniteQueryResult ||
        entry?.result is QueryResult<List<T>>) {
      try {
        final raw = entry!.result;
        if (raw.data != null) {
          // Force eager evaluation to catch type mismatches (List.cast is lazy).
          List<T>.from(raw.data as List);
        }
      } catch (_) {
        return true;
      }
    }

    return super.shouldFetchOnMount();
  }

  @override
  Future<QueryResult<List<T>>> fetch(
      {FetchMeta? meta, bool? throwOnError}) async {
    // Mirror React: rebuild _query so it is live after a clear().
    updateQuery();

    // Inject the behavior so Query.fetch() uses InfiniteQueryBehavior as the
    // fetchFn provider, giving us a single Retryer as the dedup gate.
    final opts = options as InfiniteQueryOptions<T>;

    final q = currentQuery;
    if (q == null) return getCurrentResult();

    try {
      // Pass the behavior directly to Query.fetch() so that options
      // (InfiniteQueryOptions) are preserved intact for the behavior cast.
      await q.fetch(meta: meta, behavior: InfiniteQueryBehavior<T>());
    } catch (e) {
      if (throwOnError == true) rethrow;
    }

    // After the query settles, read the raw result and wrap it as
    // InfiniteQueryResult — preserving backward-compat for tests that cast
    // client.queryCache[key]!.result as InfiniteQueryResult.
    final cacheKey = queryKeyToCacheKey(opts.queryKey);
    final settled = QueryClient.instance.queryCache[cacheKey]?.result;

    if (settled is InfiniteQueryResult<T>) return settled;

    if (settled is QueryResult<List<T>>) {
      final wrapped = _buildInfiniteResult(opts, settled, meta);
      QueryClient.instance.queryCache[cacheKey] =
          QueryCacheEntry(wrapped, DateTime.now());
      // Fan-out to all observers on this Query (mirrors React's #dispatch fan-out).
      q.notifyObservers();
      return wrapped;
    }

    // Fallback: read via normal observer path.
    q.notifyObservers();
    return getCurrentResult();
  }

  /// Build an [InfiniteQueryResult] from a plain [QueryResult<List<T>>] that
  /// came out of [Query.fetch()] via [InfiniteQueryBehavior].
  InfiniteQueryResult<T> _buildInfiniteResult(
    InfiniteQueryOptions<T> opts,
    QueryResult<List<T>> res,
    FetchMeta? fetchMeta,
  ) {
    List<T> safeData = <T>[];
    try {
      if (res.data != null) safeData = (res.data as List).cast<T>();
    } catch (_) {}

    final direction = fetchMeta?.fetchMore?.direction;
    final isFetchingNextPage =
        res.isFetching && direction == FetchDirection.forward;
    final isFetchingPreviousPage =
        res.isFetching && direction == FetchDirection.backward;
    final isFetchNextPageError =
        res.isError && direction == FetchDirection.forward;
    final isFetchPreviousPageError =
        res.isError && direction == FetchDirection.backward;

    return InfiniteQueryResult<T>(
      key: res.key,
      status: res.status,
      data: safeData,
      isFetching: res.isFetching,
      error: res.error,
      isFetchingNextPage: isFetchingNextPage,
      isFetchingPreviousPage: isFetchingPreviousPage,
      isFetchNextPageError: isFetchNextPageError,
      isFetchPreviousPageError: isFetchPreviousPageError,
      isRefetchError:
          res.isError && !isFetchNextPageError && !isFetchPreviousPageError,
      isRefetching:
          res.isFetching && !isFetchingNextPage && !isFetchingPreviousPage,
      hasNextPage: hasNextPage(opts, safeData),
      hasPreviousPage: hasPreviousPage(opts, safeData),
      fetchNextPage: hasNextPage(opts, safeData) ? fetchNextPage : null,
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

  /// Returns a copy of [opts] with [InfiniteQueryBehavior] injected as the
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

    // ── React parity: read direction from Query.fetchMeta (canonical in-flight
    // state) rather than from the cached result's fetchMeta.
    //
    // When a plain refetch fires (e.g. stale-on-mount), Query._fetchMeta is
    // null/idle, so isFetchingNextPage is correctly false — even if the last
    // cached result carried direction=forward from a prior fetchNextPage().
    final fetchDirection = currentQuery?.fetchMeta?.fetchMore?.direction;

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
      fetchNextPage:
          hasNextPage(opts, parentResult.data) ? fetchNextPage : null,
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
