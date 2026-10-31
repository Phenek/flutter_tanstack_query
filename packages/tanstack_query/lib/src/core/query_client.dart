import 'package:tanstack_query/tanstack_query.dart';

/// Core client that owns the cache and provides utilities to invalidate,
/// set, and notify query data. Prefer obtaining the active client via
/// `useQueryClient()` (with `QueryClientProvider`) in hooks and widgets; a
class QueryClient {
  /// Global default options applied to queries and mutations.
  final DefaultOptions defaultOptions;

  /// Query cache instance owned by this client (never null).
  final QueryCache queryCache;

  /// Mutation cache for mutation lifecycles (owned by this client).
  final MutationCache mutationCache;

  /// A globally available reference to the last constructed `QueryClient`.
  static late QueryClient instance;

  QueryClient(
      {this.defaultOptions = const DefaultOptions(),
      QueryCache? queryCache,
      MutationCache? mutationCache})
      : queryCache = queryCache ?? QueryCache(config: QueryCacheConfig()),
        mutationCache =
            mutationCache ?? MutationCache(config: MutationCacheConfig()) {
    instance = this;
  }

  /// Trigger refetch behavior for queries configured to refetch on window/app focus.
  void refetchOnWindowFocus() {
    queryCache.refetchOnWindowFocus();
  }

  /// Trigger refetch behavior for queries configured to refetch on reconnect.
  void refetchOnReconnect() {
    queryCache.refetchOnReconnect();
  }

  // Tracking how many times the client was mounted (e.g. provider instances)
  int _mountCount = 0;
  void Function()? _unsubscribeFocus;
  void Function()? _unsubscribeOnline;

  /// Mount the client to start listening to focus/online events. The
  /// QueryClientProvider should call [mount] on mount and [unmount] on
  /// dispose.
  void mount() {
    _mountCount++;
    if (_mountCount != 1) return;

    _unsubscribeFocus = focusManager.subscribe((focused) async {
      if (focused) {
        await resumePausedMutations();
        queryCache.onFocus();
      }
    });

    _unsubscribeOnline = onlineManager.subscribe((online) async {
      if (online) {
        await resumePausedMutations();
        queryCache.onOnline();
      }
    });
  }

  /// Stop listening to global focus/online events when the client is
  /// unmounted (e.g. provider disposed).
  void unmount() {
    _mountCount--;
    if (_mountCount != 0) return;

    _unsubscribeFocus?.call();
    _unsubscribeFocus = null;

    _unsubscribeOnline?.call();
    _unsubscribeOnline = null;
  }

  /// Resume any paused mutations; placeholder for environments that persist
  /// mutations across app restarts or offline periods.
  Future<void> resumePausedMutations() async {
    // No-op for now; implement if mutation persistence is added.
    return;
  }

  /// Mark matching queries as stale and refetch the active ones in the
  /// background. Mirrors React's `QueryClient.invalidateQueries()`.
  ///
  /// The cached data is **kept** while the refetch is in flight: observers see
  /// `status: success`, their previous `data`, `isFetching: true` and
  /// `isStale: true`, then the fresh data once it lands. Queries with no
  /// enabled observer are only marked stale; they refetch on their next mount.
  ///
  /// - [queryKey] `null` invalidates every query.
  /// - [exact] `true` matches the serialized key exactly, otherwise any key
  ///   the given one is an element-wise prefix of — see [_matchingCacheKeys].
  void invalidateQueries({List<Object>? queryKey, bool exact = false}) {
    // One batch around invalidate + refetch, like the JS version: observers
    // notified in between would rebuild once per query instead of once.
    notifyManager.batch(() {
      final toRefetch = <Query>[];
      for (final key in _matchingCacheKeys(queryKey, exact)) {
        final q = queryCache.getQuery(key);
        if (q == null) {
          queryCache.markInvalidated(key);
          continue;
        }
        q.invalidate();
        if (q.isActive) toRefetch.add(q);
      }

      // Refetch in a second pass so every observer already sees isStale before
      // the first pending result is written (React: batch invalidate → refetch).
      for (final q in toRefetch) {
        q.notifyObserversRefetch();
      }
    });
  }

  /// Synchronously updates the cached query data for [keys] using [updateFn].
  ///
  /// The [updateFn] receives the previous cached value (or `null`) and returns
  /// the new data to store. Returning `null` writes **nothing** and creates no
  /// cache entry, mirroring React's `setQueryData`, which bails out when the
  /// updater returns `undefined`. To store a plain value, use [setQueryDataValue]
  /// (or `(_) => value`).
  ///
  /// The parameter stays a typed function rather than the JS `Updater` union
  /// (`value | function`): with an `Object?` parameter the closure would lose
  /// its contextual type and a record literal like `distanceMeters: 110_000`
  /// would infer `int` where `T` expects `double`.
  void setQueryData<T>(List<Object> keys, T? Function(T? oldData) updateFn) {
    final cacheKey = queryKeyToCacheKey(keys);
    final newData = updateFn(_dataOf<T>(cacheKey));
    if (newData == null) return;
    final queryResult = QueryResult<T>(
        cacheKey, QueryStatus.success, newData, null,
        isFetching: false,
        dataUpdatedAt: DateTime.now().millisecondsSinceEpoch,
        isPlaceholderData: false);

    queryCache[cacheKey] =
        QueryCacheEntry<T>(queryResult, DateTime.now(), queryKey: keys);
    // Mirrors React: setData dispatches `success`, which clears isInvalidated
    // and notifies observers directly through the Query object.
    queryCache.getQuery(cacheKey)
      ?..markFresh()
      ..notifyObservers();
  }

  /// Stores [value] directly for [keys] — the JS `setQueryData(key, value)`
  /// form, where the updater may be a plain value instead of a function.
  void setQueryDataValue<T>(List<Object> keys, T value) =>
      setQueryData<T>(keys, (_) => value);

  /// Synchronously updates cached infinite query data for [keys] using
  /// [updateFn]. The function receives the previous list of pages and must
  /// return the updated list to store in cache.
  void setQueryInfiniteData<T>(
      List<Object> keys, List<T> Function(List<T>? oldDatas) updateFn) {
    final cacheKey = queryKeyToCacheKey(keys);
    final oldEntry = queryCache[cacheKey];
    final oldDatas = oldEntry?.result.data as List<T>? ?? <T>[];
    final newDatas = updateFn(oldDatas);

    final queryResult = InfiniteQueryResult<T>(
      key: cacheKey,
      status: QueryStatus.success,
      data: newDatas,
      isFetching: false,
      error: null,
      isFetchingNextPage: false,
      fetchNextPage: () async {},
      dataUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      isPlaceholderData: false,
    );

    queryCache[cacheKey] =
        QueryCacheEntry<List<T>>(queryResult, DateTime.now(), queryKey: keys);
    // Mirrors React: setData dispatches `success`, which clears isInvalidated
    // and notifies observers directly through the Query object.
    queryCache.getQuery(cacheKey)
      ?..markFresh()
      ..notifyObservers();
  }

  /// Per-key default options registered with [setQueryDefaults], keyed by the
  /// hashed default key. Insertion order is preserved so [getQueryDefaults]
  /// merges in registration order, like the JS `Map`.
  final Map<String, _QueryDefaultEntry> _queryDefaults = {};

  /// Registers default options for every query whose key starts with
  /// [queryKey]. Port of `QueryClient.setQueryDefaults`.
  void setQueryDefaults(List<Object> queryKey, QueryDefaults defaults) {
    _queryDefaults[queryKeyToCacheKey(queryKey)] =
        _QueryDefaultEntry(queryKey, defaults);
  }

  /// The merged defaults applying to [queryKey]: every registered default whose
  /// key is an element-wise prefix of it, later registrations winning per field.
  /// Port of `QueryClient.getQueryDefaults`, matching with [partialMatchKey] as
  /// the JavaScript version does — so a default registered for `['todo']` does
  /// **not** leak onto `['todos', 1]`.
  ///
  /// Note that [invalidateQueries] and the other key-matching methods still
  /// compare serialized keys with a prefix, which is looser than this.
  QueryDefaults getQueryDefaults(List<Object> queryKey) {
    var result = const QueryDefaults();
    for (final entry in _queryDefaults.values) {
      if (partialMatchKey(queryKey, entry.queryKey)) {
        result = result.merge(entry.defaults);
      }
    }
    return result;
  }

  /// Clears every per-key default registered with [setQueryDefaults].
  void clearQueryDefaults() => _queryDefaults.clear();

  /// Fills [options] in with this client's defaults where it says nothing.
  ///
  /// Port of `QueryClient.defaultQueryOptions` — merge order is global
  /// `defaultOptions.queries` < [getQueryDefaults] for the key < [options]
  /// itself. Observers resolve the defaults themselves as they read them, so
  /// this only matters for the imperative methods below, which have no
  /// observer to fall back on.
  QueryOptions<T> defaultQueryOptions<T>(QueryOptions<T> options) {
    final queries = defaultOptions.queries;
    final defaults = getQueryDefaults(options.queryKey);
    return options.copyWith(
      staleTime: options.staleTime ?? defaults.staleTime ?? queries.staleTime,
      enabled: options.enabled ?? defaults.enabled ?? queries.enabled,
      retry: options.retry ?? defaults.retry ?? queries.retry,
      retryDelay: options.retryDelay ?? defaults.retryDelay ?? queries.retryDelay,
      retryOnMount:
          options.retryOnMount ?? defaults.retryOnMount ?? queries.retryOnMount,
      refetchOnMount:
          options.refetchOnMount ?? defaults.refetchOnMount ?? queries.refetchOnMount,
      gcTime: options.gcTime ?? defaults.gcTime ?? queries.gcTime,
      refetchOnWindowFocus: options.refetchOnWindowFocus ??
          defaults.refetchOnWindowFocus ??
          queries.refetchOnWindowFocus,
      refetchOnReconnect: options.refetchOnReconnect ??
          defaults.refetchOnReconnect ??
          queries.refetchOnReconnect,
    );
  }

  /// The data currently cached for [queryKey], or `null`.
  ///
  /// Reads the cache and never builds a query or starts a fetch, so it is safe
  /// to call from anywhere — including outside the widget tree.
  T? getQueryData<T>(List<Object> queryKey) =>
      _dataOf<T>(queryKeyToCacheKey(queryKey));

  /// The cached data for a cache key, tolerating entries written under another
  /// type argument (they read as `null` rather than throwing).
  T? _dataOf<T>(String cacheKey) {
    final result = queryCache[cacheKey]?.result;
    if (result is QueryResult<T>) return result.data;
    try {
      return result?.data as T?;
    } catch (_) {
      return null;
    }
  }

  /// Every cached entry matching [queryKey], as `[originalKey, data]` pairs.
  ///
  /// Port of `QueryClient.getQueriesData`. Like [invalidateQueries], a `null`
  /// [queryKey] matches everything and [exact] switches from prefix to exact
  /// matching. Entries written by [setQueryData] without a mounted query are
  /// included.
  List<QueryDataEntry<T>> getQueriesData<T>(
      {List<Object>? queryKey, bool exact = false}) {
    final keys = _matchingCacheKeys(queryKey, exact);

    return [
      for (final key in keys)
        QueryDataEntry<T>(queryCache.queryKeyOf(key), _dataOf<T>(key)),
    ];
  }

  /// The whole cached result for [queryKey] — status, error, timestamps — or `null`.
  QueryResult<T>? getQueryState<T>(List<Object> queryKey) {
    final result = queryCache[queryKeyToCacheKey(queryKey)]?.result;
    return result is QueryResult<T> ? result : null;
  }

  /// Fetches [queryKey] and returns its data, serving the cache when it is fresh.
  ///
  /// Port of `QueryClient.fetchQuery`. This is how a query is used from outside
  /// the widget tree — a service reacting to a notifier, a navigation side
  /// effect — while keeping deduplication and caching: a widget mounting the
  /// same key afterwards finds the data already there, and a fetch already in
  /// flight is joined instead of duplicated.
  ///
  /// Unlike a `useQuery`, [retry] defaults to `false`: an imperative caller
  /// awaits the answer and would rather see the error than wait out the retries.
  Future<T?> fetchQuery<T>({
    required List<Object> queryKey,
    required Future<T> Function() queryFn,
    double? staleTime,
    int? gcTime,
    dynamic retry,
    dynamic retryDelay,
    Object? structuralSharing,
  }) {
    var options = defaultQueryOptions<T>(QueryOptions<T>(
      queryKey: queryKey,
      queryFn: queryFn,
      staleTime: staleTime,
      gcTime: gcTime,
      retry: retry,
      retryDelay: retryDelay,
      structuralSharing: structuralSharing,
    ));
    // Applied *after* the merge, as in JS: `retry` falls back to `false` only
    // when nothing configured it, so `defaultOptions.queries.retry` and
    // `setQueryDefaults(retry:)` still reach an imperative fetch.
    if (options.retry == null) options = options.copyWith(retry: false);

    final query = queryCache.build<T>(this, options);
    if (!query.isStaleByTime(options.staleTime ?? 0)) {
      return Future<T?>.value(query.result?.data);
    }
    return query.fetch();
  }

  /// Fetches [queryKey] without returning or throwing anything.
  ///
  /// Port of `QueryClient.prefetchQuery`: warm the cache before a widget needs
  /// it, and leave the error handling to whoever mounts the query.
  Future<void> prefetchQuery<T>({
    required List<Object> queryKey,
    required Future<T> Function() queryFn,
    double? staleTime,
    int? gcTime,
    dynamic retry,
    dynamic retryDelay,
  }) async {
    try {
      await fetchQuery<T>(
        queryKey: queryKey,
        queryFn: queryFn,
        staleTime: staleTime,
        gcTime: gcTime,
        retry: retry,
        retryDelay: retryDelay,
      );
    } catch (_) {
      // Prefetching is best-effort by design.
    }
  }

  /// Returns the cached data for [queryKey], fetching only when there is none.
  ///
  /// Port of `QueryClient.ensureQueryData`. With [revalidateIfStale], stale data
  /// is returned right away and a refetch runs in the background.
  Future<T?> ensureQueryData<T>({
    required List<Object> queryKey,
    required Future<T> Function() queryFn,
    double? staleTime,
    int? gcTime,
    dynamic retry,
    dynamic retryDelay,
    bool revalidateIfStale = false,
  }) {
    final options = defaultQueryOptions<T>(QueryOptions<T>(
      queryKey: queryKey,
      queryFn: queryFn,
      staleTime: staleTime,
      gcTime: gcTime,
      retry: retry,
      retryDelay: retryDelay,
    ));
    final query = queryCache.build<T>(this, options);
    final cached = query.result?.data;
    if (cached == null) {
      return fetchQuery<T>(
        queryKey: queryKey,
        queryFn: queryFn,
        staleTime: staleTime,
        gcTime: gcTime,
        retry: retry,
        retryDelay: retryDelay,
      );
    }

    if (revalidateIfStale && query.isStaleByTime(options.staleTime ?? 0)) {
      // Fire and forget: the caller already has something to show.
      prefetchQuery<T>(
        queryKey: queryKey,
        queryFn: queryFn,
        staleTime: staleTime,
        gcTime: gcTime,
        retry: retry,
        retryDelay: retryDelay,
      );
    }

    return Future<T?>.value(cached);
  }

  /// Fetches the first page of an infinite query and returns its pages.
  ///
  /// Port of `QueryClient.fetchInfiniteQuery`: it is [fetchQuery] with
  /// `InfiniteQueryBehavior` injected, which is also what
  /// `InfiniteQueryObserver` does.
  Future<List<T>?> fetchInfiniteQuery<T>({
    required List<Object> queryKey,
    required Future<T?> Function(int pageParam) queryFn,
    required int initialPageParam,
    int? Function(T lastResult)? getNextPageParam,
    int? Function(T firstResult)? getPreviousPageParam,
    double? staleTime,
    int? gcTime,
    dynamic retry,
    dynamic retryDelay,
  }) {
    // `InfiniteQueryOptions` cannot go through `defaultQueryOptions` (its
    // `copyWith` would hand back a plain `QueryOptions` and drop the page
    // params), so the same merge order is applied by hand: call < key defaults
    // < global defaults, and `retry` down to `false` only once nothing else
    // claimed it — exactly what `fetchQuery` does in JS, which is where
    // `fetchInfiniteQuery` delegates.
    final queries = defaultOptions.queries;
    final keyDefaults = getQueryDefaults(queryKey);
    final options = InfiniteQueryOptions<T>(
      queryKey: queryKey,
      queryFn: queryFn,
      initialPageParam: initialPageParam,
      getNextPageParam: getNextPageParam,
      getPreviousPageParam: getPreviousPageParam,
      staleTime: staleTime ?? keyDefaults.staleTime ?? queries.staleTime,
      gcTime: gcTime ?? keyDefaults.gcTime ?? queries.gcTime,
      retry: retry ?? keyDefaults.retry ?? queries.retry ?? false,
      retryDelay:
          retryDelay ?? keyDefaults.retryDelay ?? queries.retryDelay,
    );

    final query = queryCache.build<List<T>>(this, options);
    if (!query.isStaleByTime(options.staleTime ?? 0)) {
      return Future<List<T>?>.value(query.result?.data);
    }
    return query.fetch(behavior: InfiniteQueryBehavior<T>());
  }

  /// Fetches an infinite query without returning or throwing anything.
  /// Port of `QueryClient.prefetchInfiniteQuery`.
  Future<void> prefetchInfiniteQuery<T>({
    required List<Object> queryKey,
    required Future<T?> Function(int pageParam) queryFn,
    required int initialPageParam,
    int? Function(T lastResult)? getNextPageParam,
    int? Function(T firstResult)? getPreviousPageParam,
    double? staleTime,
    int? gcTime,
    dynamic retry,
    dynamic retryDelay,
  }) async {
    try {
      await fetchInfiniteQuery<T>(
        queryKey: queryKey,
        queryFn: queryFn,
        initialPageParam: initialPageParam,
        getNextPageParam: getNextPageParam,
        getPreviousPageParam: getPreviousPageParam,
        staleTime: staleTime,
        gcTime: gcTime,
        retry: retry,
        retryDelay: retryDelay,
      );
    } catch (_) {
      // Prefetching is best-effort by design.
    }
  }

  /// Returns the cached pages for [queryKey], fetching only when there are none.
  ///
  /// Port of `QueryClient.ensureInfiniteQueryData`, which delegates to
  /// `ensureQueryData`: only the *absence* of cached pages triggers a fetch, so
  /// an empty list that the server really returned is served as it is. With
  /// [revalidateIfStale], stale pages are returned right away and a refetch
  /// runs in the background.
  Future<List<T>?> ensureInfiniteQueryData<T>({
    required List<Object> queryKey,
    required Future<T?> Function(int pageParam) queryFn,
    required int initialPageParam,
    int? Function(T lastResult)? getNextPageParam,
    int? Function(T firstResult)? getPreviousPageParam,
    double? staleTime,
    int? gcTime,
    dynamic retry,
    dynamic retryDelay,
    bool revalidateIfStale = false,
  }) {
    final cached = getQueryData<List<T>>(queryKey);
    if (cached == null) {
      return fetchInfiniteQuery<T>(
        queryKey: queryKey,
        queryFn: queryFn,
        initialPageParam: initialPageParam,
        getNextPageParam: getNextPageParam,
        getPreviousPageParam: getPreviousPageParam,
        staleTime: staleTime,
        gcTime: gcTime,
        retry: retry,
        retryDelay: retryDelay,
      );
    }

    if (revalidateIfStale) {
      final resolvedStaleTime = staleTime ??
          getQueryDefaults(queryKey).staleTime ??
          defaultOptions.queries.staleTime ??
          0;
      final query = queryCache.getQuery(queryKeyToCacheKey(queryKey));
      if (query?.isStaleByTime(resolvedStaleTime) ?? true) {
        // Fire and forget: the caller already has something to show.
        prefetchInfiniteQuery<T>(
          queryKey: queryKey,
          queryFn: queryFn,
          initialPageParam: initialPageParam,
          getNextPageParam: getNextPageParam,
          getPreviousPageParam: getPreviousPageParam,
          staleTime: staleTime,
          gcTime: gcTime,
          retry: retry,
          retryDelay: retryDelay,
        );
      }
    }

    return Future<List<T>?>.value(cached);
  }

  /// Removes matching queries from the cache entirely, data and all.
  ///
  /// Port of `QueryClient.removeQueries`. Unlike [invalidateQueries] nothing is
  /// refetched: observers still mounted fall back to `pending`.
  ///
  /// - [queryKey] `null` removes every query.
  /// - [exact] `true` matches the serialized key exactly, otherwise any key
  ///   the given one is an element-wise prefix of — see [_matchingCacheKeys].
  void removeQueries({List<Object>? queryKey, bool exact = false}) {
    notifyManager.batch(() {
      for (final key in _matchingCacheKeys(queryKey, exact)) {
        final query = queryCache.getQuery(key);
        if (query == null) {
          queryCache.removeEntry(key);
          continue;
        }
        queryCache.remove(query);
        // Notify through the *removed* instance, which still holds its
        // observers: each of them recomputes, finds no cache entry and falls
        // back to `pending`. React gets there on its next render, through
        // `getOptimisticResult`; here a rebuild only happens on notification.
        query.notifyObservers();
      }
    });
  }

  /// Clears matching queries, then refetches the active ones.
  /// Port of `QueryClient.resetQueries`.
  void resetQueries({List<Object>? queryKey, bool exact = false}) {
    notifyManager.batch(() {
      for (final key in _matchingCacheKeys(queryKey, exact)) {
        final query = queryCache.getQuery(key);
        if (query == null) {
          // Data written by `setQueryData` with nothing mounted: there is no
          // observer to refetch, so clearing the entry is the whole reset.
          queryCache.removeEntry(key);
          continue;
        }
        final wasActive = query.isActive;
        queryCache.remove(query);
        // Notify through the *removed* instance: it still holds its observers,
        // and each of them rebuilds a fresh `Query` through `updateQuery()` on
        // the way to refetching. Notifying a newly built query instead would
        // reach nobody, since the observers still point at the old one.
        //
        // React resets the query in place with `Query.reset()`, which needs the
        // `QueryState` machinery this port does not have yet.
        if (wasActive) {
          query.notifyObserversRefetch();
        } else {
          // Nothing will refetch, so at least let the observers see the cleared
          // state instead of keeping the removed data on screen.
          query.notifyObservers();
        }
      }
    });
  }

  /// Every cache key matching [queryKey], over the union of cache entries and
  /// built `Query` instances.
  ///
  /// Port of `QueryCache.findAll` + `matchQuery`: a `null` [queryKey] matches
  /// everything, [exact] compares the serialized key, and a prefix match goes
  /// through [partialMatchKey] — element by element, not character by
  /// character, so `['todos', 1]` no longer matches `['todos', 11]`.
  ///
  /// The union is this port's equivalent of React's single map: a cache entry
  /// written by [setQueryData] has no `Query` until something mounts the key,
  /// and a `Query` whose fetch never settled has no entry — React's `findAll`
  /// sees both.
  List<String> _matchingCacheKeys(List<Object>? queryKey, bool exact) {
    final keys = <String>{
      ...queryCache.keys,
      ...queryCache.getAllQueries().map((q) => q.cacheKey),
    };
    if (queryKey == null) return keys.toList(growable: false);

    final hash = queryKeyToCacheKey(queryKey);
    return keys
        .where((key) => exact
            ? key == hash
            : partialMatchKey(queryCache.queryKeyOf(key), queryKey))
        .toList(growable: false);
  }

  /// Clears the entire in-memory cache and notifies listeners that cached
  /// values have been removed so widgets can react accordingly.
  void clear() {
    queryCache.clear();
  }
}

/// One `[key, data]` pair returned by [QueryClient.getQueriesData].
class QueryDataEntry<T> {
  /// The original (unhashed) query key of the cached entry.
  final List<Object> key;

  /// The cached data, or `null` when the entry holds none.
  final T? data;

  const QueryDataEntry(this.key, this.data);

  @override
  String toString() => 'QueryDataEntry($key, $data)';
}

class _QueryDefaultEntry {
  final List<Object> queryKey;
  final QueryDefaults defaults;

  _QueryDefaultEntry(this.queryKey, this.defaults);
}
