import 'dart:async';
import 'package:tanstack_query/tanstack_query.dart';
import 'removable.dart';

/// Minimal `Query` implementation to centralize fetch and observer logic.
class Query<T> extends Removable {
  final QueryClient client;
  QueryOptions<T> options;
  final String cacheKey;

  final Set<dynamic> _observers = <dynamic>{};

  /// Active retryer
  Retryer<T>? _retryer;

  FetchMeta? _fetchMeta;

  bool _isInvalidated = false;

  /// Whether this query has been marked out of date by
  /// `QueryClient.invalidateQueries`. Mirrors React's `state.isInvalidated`.
  ///
  /// An invalidated query is always considered stale regardless of
  /// `staleTime`, but keeps its cached data until the next successful fetch
  /// replaces it.
  bool get isInvalidated => _isInvalidated;

  /// The [FetchMeta] for the currently in-flight fetch, or `null` when idle.
  ///
  /// Mirrors React's `query.state.fetchMeta` — set synchronously before any
  /// `await`, and cleared when the fetch settles.  `InfiniteQueryObserver`
  /// reads this instead of the cached result's [fetchMeta] so that
  /// `isFetchingNextPage` is `false` during a plain refetch even when the
  /// last cached result carried `direction=forward`.
  FetchMeta? get fetchMeta => _fetchMeta;

  Query(this.client, this.options)
      : cacheKey = queryKeyToCacheKey(options.queryKey) {
    // Initialize GC timing using options + client defaults
    updateGcTime(options.gcTime,
        defaultGcTime: client.defaultOptions.queries.gcTime);
    // Schedule initial GC so unused queries are collected
    scheduleGc();
  }

  void addObserver(dynamic observer) {
    _observers.add(observer);
    // If an observer is added, cancel GC
    clearGcTimeout();
  }

  void removeObserver(dynamic observer) {
    _observers.remove(observer);
    if (_observers.isEmpty) {
      scheduleGc();
    }
  }

  /// The cache entry for this query, or `null`. Entries are sometimes written
  /// untyped (e.g. by [QueryClient.setQueryData] before this iteration), so the
  /// cast is a checked `is` test: a mismatched entry reads as "no data" instead
  /// of throwing out of [isStaleByTime] into an imperative caller.
  QueryCacheEntry<T>? get entry {
    final e = client.queryCache[cacheKey];
    return e is QueryCacheEntry<T> ? e : null;
  }

  QueryResult<T>? get result {
    final r = client.queryCache[cacheKey]?.result;
    return r is QueryResult<T> ? r : null;
  }

  bool get hasObservers => _observers.isNotEmpty;

  /// Whether at least one observer is enabled. Mirrors React's
  /// `Query.isActive()`: only active queries are refetched by
  /// `invalidateQueries`.
  bool get isActive {
    for (var o in _observers) {
      try {
        if ((o.options.enabled as bool?) ?? true) return true;
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  /// Mark this query as stale without touching its cached data and notify
  /// observers so their `isStale` flag updates. Mirrors React's
  /// `Query.invalidate()` → `dispatch({type: 'invalidate'})`.
  void invalidate() {
    if (_isInvalidated) return;
    _isInvalidated = true;
    _notifyObservers();
  }

  /// Clear the invalidated flag. Called when fresh data lands in the cache
  /// (successful fetch or `setQueryData`), mirroring React's `success` action.
  void markFresh() {
    _isInvalidated = false;
  }

  /// Whether the cached data is stale for the given [staleTime] (ms).
  /// Mirrors React's `Query.isStaleByTime()`: no data, invalidated, or older
  /// than `staleTime`.
  ///
  /// An infinite [staleTime] means "never stale by time" — but, exactly as in
  /// JavaScript, the absence of data and `isInvalidated` are checked *first*,
  /// so an invalidated query is stale whatever its `staleTime`.
  bool isStaleByTime([num staleTime = 0]) {
    final res = result;
    if (res == null || res.data == null) return true;
    if (_isInvalidated) return true;
    if (staleTime.isInfinite) return false;
    final updatedAt =
        res.dataUpdatedAt ?? entry?.timestamp.millisecondsSinceEpoch ?? 0;
    // `>=`, not `>`: React computes `!timeUntilStale(updatedAt, staleTime)` with
    // `timeUntilStale = max(updatedAt + staleTime - now, 0)`, so at `staleTime: 0`
    // data written in the same millisecond is already stale.
    return DateTime.now().millisecondsSinceEpoch - updatedAt >= staleTime;
  }

  void _notifyObservers() {
    for (var o in List<dynamic>.from(_observers)) {
      try {
        o.onQueryUpdate();
      } catch (_) {
        // ignore
      }
    }
  }

  /// Public entry-point for QueryClient.setQueryData — mirrors React's
  /// query.dispatch({type:'success'}) path where observers are notified
  /// directly through the Query object rather than via cache events.
  void notifyObservers() => _notifyObservers();

  /// Notify all observers to trigger a refetch. Used by QueryCache and
  /// QueryClient to route invalidation through the Query object rather than
  /// firing cache events — mirrors React's QueryCache.notify pattern.
  void notifyObserversRefetch() {
    for (var o in List<dynamic>.from(_observers)) {
      try {
        o.refetch();
      } catch (_) {}
    }
  }

  /// Fetch using Retryer with retry configuration from options.
  ///
  /// Mirrors React's `Query.fetch()`:
  /// 1. Dedup: if a retryer is already pending, return its promise (the
  ///    [Retryer.start] guard handles this synchronously).
  /// 2. Build a [FetchContext] and call [QueryBehavior.onFetch] so behaviors
  ///    (e.g. [InfiniteQueryBehavior]) can replace [FetchContext.fetchFn].
  /// 3. Set [_fetchMeta] synchronously — observers read it via [fetchMeta]
  ///    to compute `isFetchingNextPage` without touching the stale cache.
  /// 4. Write a pending result to the cache and notify observers — all before
  ///    any `await`.
  /// 5. Wrap the (possibly behavior-replaced) fetchFn in a single [Retryer].
  Future<T?> fetch({FetchMeta? meta, dynamic behavior}) async {
    // ── 1. Synchronous dedup (mirrors React `fetchStatus !== 'idle'`) ─────
    if (_retryer != null && _retryer!.status() == 'pending') {
      // continueRetry() is a no-op when not paused, safe to call unconditionally.
      _retryer!.continueRetry();
      return _retryer!.start(); // returns in-flight promise (no new Retryer)
    }

    // ── 2. Build FetchContext and invoke behavior hook ────────────────────
    final prevEntry = client.queryCache[cacheKey];
    final context = FetchContext<T>(
      fetchFn: options.queryFn,
      meta: meta,
      options: options,
      currentEntry: prevEntry,
    );
    final effectiveBehavior =
        (behavior as QueryBehavior<T>?) ?? options.behavior;
    effectiveBehavior?.onFetch(context, this);

    // ── 3. Set fetchMeta synchronously ────────────────────────────────────
    _fetchMeta = meta;

    // ── 4. Write pending result and notify before any await ───────────────
    QueryResult<T>? prevRes;
    try {
      prevRes = prevEntry?.result as QueryResult<T>?;
    } catch (_) {
      // Ignore mismatched cached types (e.g. InfiniteQueryResult<Object>
      // when this Query is typed List<int>).
    }
    final hasPrevData = prevRes != null && prevRes.data != null;

    TrackedFuture<T>? running;

    _retryer = Retryer<T>(
      fn: context.fetchFn,
      // `?? 3` lives here, not in the client defaults, so that "nothing
      // configured retry" stays distinguishable from "retry is 3" — which is
      // what `fetchQuery` needs to default to `false` without overriding a
      // real default. Mirrors JS, where `createRetryer` does `retry ?? 3`.
      retry: options.retry ?? client.defaultOptions.queries.retry ?? 3,
      retryDelay:
          options.retryDelay ?? client.defaultOptions.queries.retryDelay,
      onFail: (failureCount, error) {
        final prevEntry2 = client.queryCache[cacheKey];
        QueryResult<T>? prevRes2;
        try {
          prevRes2 = prevEntry2?.result as QueryResult<T>?;
        } catch (_) {}
        final hasPrev2 = prevRes2 != null && prevRes2.data != null;

        final failRes = QueryResult<T>(
            cacheKey,
            hasPrev2 ? prevRes2.status : QueryStatus.pending,
            hasPrev2 ? prevRes2.data : null,
            error,
            isFetching: true,
            dataUpdatedAt: hasPrev2 ? prevRes2.dataUpdatedAt : null,
            isPlaceholderData: false,
            failureCount: failureCount,
            failureReason: error,
            fetchMeta: _fetchMeta);
        client.queryCache[cacheKey] = QueryCacheEntry<T>(
            failRes, DateTime.now(),
            queryFnRunning: running);
        _notifyObservers();
      },
    );

    final pending = QueryResult<T>(
        cacheKey,
        hasPrevData ? QueryStatus.success : QueryStatus.pending,
        hasPrevData ? prevRes.data : null,
        null,
        isFetching: true,
        dataUpdatedAt: hasPrevData ? prevRes.dataUpdatedAt : null,
        isPlaceholderData: false,
        failureCount: 0,
        failureReason: null,
        fetchMeta: _fetchMeta);

    running = TrackedFuture<T>(_retryer!.start());
    client.queryCache[cacheKey] =
        QueryCacheEntry<T>(pending, DateTime.now(), queryFnRunning: running);
    _notifyObservers();

    // ── 5. Await the single retryer ───────────────────────────────────────
    try {
      final value = await running;
      final settledFetchMeta = _fetchMeta;
      _fetchMeta = null; // clear before notify so createResult sees idle state
      _isInvalidated =
          false; // fresh data: no longer invalidated (React `success`)
      // Mirrors React's `Query.setData`, which runs new data through
      // `replaceData`: a refetch that brings back the same payload keeps the
      // previous instance, so observers compare equal and nothing rebuilds.
      final shared =
          replaceData<T>(prevRes?.data, value, options.structuralSharing);
      final queryResult = QueryResult<T>(
          cacheKey, QueryStatus.success, shared, null,
          isFetching: false,
          dataUpdatedAt: DateTime.now().millisecondsSinceEpoch,
          isPlaceholderData: false,
          failureCount: 0,
          failureReason: null,
          fetchMeta: settledFetchMeta);
      client.queryCache[cacheKey] =
          QueryCacheEntry<T>(queryResult, DateTime.now());
      client.queryCache.config.onSuccess?.call(value);
      _notifyObservers();
      _retryer = null;
      return value;
    } catch (e) {
      final failureCount = _retryer?.failureCount ?? 0;
      final settledFetchMeta = _fetchMeta;
      _fetchMeta = null; // clear before notify so createResult sees idle state
      final errorRes = QueryResult<T>(cacheKey, QueryStatus.error, null, e,
          isFetching: false,
          dataUpdatedAt: null,
          isPlaceholderData: false,
          failureCount: failureCount,
          failureReason: e,
          fetchMeta: settledFetchMeta);
      client.queryCache[cacheKey] =
          QueryCacheEntry<T>(errorRes, DateTime.now());
      client.queryCache.config.onError?.call(e);
      _notifyObservers();
      _retryer = null;
      rethrow;
    } finally {
      scheduleGc();
    }
  }

  void cancel() {
    _retryer?.cancel();
    clearGcTimeout();
  }

  /// Handle window/app focus events: find an observer that wants a refetch
  /// on focus and trigger it, then continue any paused retryer.
  void onFocus() {
    dynamic observer;
    for (var o in _observers) {
      try {
        if (o.shouldFetchOnWindowFocus != null) {
          observer = o;
          break;
        }
      } catch (_) {}
    }

    try {
      observer?.refetch();
    } catch (_) {}

    // Continue fetch if currently paused
    try {
      _retryer?.continueRetry();
    } catch (_) {}
  }

  /// Handle online events: find an observer that wants a refetch on reconnect
  /// and trigger it, then continue any paused retryer.
  void onOnline() {
    dynamic observer;
    for (var o in _observers) {
      try {
        if (o.shouldFetchOnReconnect != null) {
          observer = o;
          break;
        }
      } catch (_) {}
    }

    try {
      observer?.refetch();
    } catch (_) {}

    // Continue fetch if currently paused
    try {
      _retryer?.continueRetry();
    } catch (_) {}
  }

  /// Destroy this query: clear GC timer and cancel any in-flight retryer.
  /// Called by QueryCache.remove() — mirrors React's Query.destroy().
  @override
  void destroy() {
    super.destroy(); // clears GC timer
    _retryer?.cancel();
  }

  @override
  void optionalRemove() {
    if (hasObservers) return;
    // Mirror React: only GC when not actively fetching (fetchStatus === 'idle').
    if (_retryer != null) return;
    // Mirror React: pass `this` so QueryCache can do an identity check.
    // An orphaned Query (replaced after clear()) will find a different instance
    // registered and will be a no-op, preventing it from evicting the live entry.
    client.queryCache.remove(this);
  }
}
