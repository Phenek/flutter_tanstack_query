import 'query_types.dart';
import 'query_cache.dart';

/// A mutable context object passed to [QueryBehavior.onFetch].
///
/// The behavior replaces [fetchFn] with its own async closure; [Query] then
/// wraps that closure in a single [Retryer] — exactly like React's
/// `Query.#retryer` pattern.
class FetchContext<T> {
  /// The default fetch function (from [QueryOptions.queryFn]).
  /// A [QueryBehavior] replaces this to implement custom fetch logic.
  Future<T> Function() fetchFn;

  /// Metadata that describes WHY this fetch is happening (e.g. paginate forward).
  final FetchMeta? meta;

  /// The options associated with the query.
  final QueryOptions<T> options;

  /// The current cache entry (may be null for the first fetch).
  final QueryCacheEntry? currentEntry;

  FetchContext({
    required this.fetchFn,
    required this.meta,
    required this.options,
    required this.currentEntry,
  });
}

/// Flutter port of React's `infiniteQueryBehavior()`.
///
/// Replaces the default [QueryOptions.queryFn]-based fetch with page-aware
/// logic:
/// - `direction == null`    → refetch all existing pages in order (initial load
///   or background refetch).
/// - `direction == forward`  → append a new page at the end.
/// - `direction == backward` → prepend a new page at the start.
class InfiniteQueryBehavior<T> extends QueryBehavior<List<T>> {
  const InfiniteQueryBehavior();

  @override
  void onFetch(dynamic ctx, dynamic _query) {
    final context = ctx as FetchContext<List<T>>;
    final opts = context.options as InfiniteQueryOptions<T>;
    final direction = context.meta?.fetchMore?.direction;

    context.fetchFn = () async {
      // ── Existing pages ──────────────────────────────────────────────────
      // Use a safe cast: the cached result may have a mismatched generic type
      // (e.g. QueryResult<List<Object>> when we expect QueryResult<List<T>>).
      final rawResult = context.currentEntry?.result;
      List<T> currentData;
      try {
        final typed = rawResult as QueryResult<List<T>>?;
        currentData = typed?.data != null ? List<T>.from(typed!.data as List) : <T>[];
      } catch (_) {
        currentData = <T>[];
      }

      // ── Forward: append one page ────────────────────────────────────────
      if (direction == FetchDirection.forward) {
        if (opts.getNextPageParam == null || currentData.isEmpty) {
          return List<T>.from(currentData);
        }
        final nextParam = opts.getNextPageParam!(currentData.last);
        if (nextParam == null) {
          // No next page — return current data unchanged so the cache write
          // is a no-op (isFetchingNextPage will be cleared by Query after settle).
          return List<T>.from(currentData);
        }
        final page = await opts.pageQueryFn(nextParam);
        if (page == null) return List<T>.from(currentData);
        return [...currentData, page];
      }

      // ── Backward: prepend one page ──────────────────────────────────────
      if (direction == FetchDirection.backward) {
        if (opts.getPreviousPageParam == null || currentData.isEmpty) {
          return List<T>.from(currentData);
        }
        final prevParam = opts.getPreviousPageParam!(currentData.first);
        if (prevParam == null) return List<T>.from(currentData);
        final page = await opts.pageQueryFn(prevParam);
        if (page == null) return List<T>.from(currentData);
        return [page, ...currentData];
      }

      // ── Null direction: refetch all existing pages (or first page) ──────
      final int pageCount = currentData.isNotEmpty ? currentData.length : 1;
      int? pageParam = opts.initialPageParam;
      final result = <T>[];

      for (var i = 0; i < pageCount; i++) {
        final page = await opts.pageQueryFn(pageParam!);
        if (page == null) break;
        result.add(page);

        if (opts.getNextPageParam == null) break;
        final nextParam = opts.getNextPageParam!(page);
        if (nextParam == null) break;
        pageParam = nextParam;
      }

      return result;
    };
  }
}
