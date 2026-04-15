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

  QueryCacheEntry<T>? get entry =>
      client.queryCache[cacheKey] as QueryCacheEntry<T>?;

  QueryResult<T>? get result => entry?.result as QueryResult<T>?;

  bool get hasObservers => _observers.isNotEmpty;

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
      retry: options.retry ?? client.defaultOptions.queries.retry,
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
      final queryResult = QueryResult<T>(
          cacheKey, QueryStatus.success, value, null,
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
