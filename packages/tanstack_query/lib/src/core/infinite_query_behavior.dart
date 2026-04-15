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

// ── maxPages helpers ────────────────────────────────────────────────────────
// Mirrors React's addToEnd / addToStart in utils.ts.

/// Appends [item] to [list] and trims the oldest entry when [maxPages] is
/// exceeded (keeps the *newest* pages).
List<E> addToEnd<E>(List<E> list, E item, int? maxPages) {
  final result = [...list, item];
  if (maxPages != null && result.length > maxPages) {
    return result.sublist(result.length - maxPages);
  }
  return result;
}

/// Prepends [item] to [list] and trims the newest entry when [maxPages] is
/// exceeded (keeps the *oldest* pages for backward pagination).
List<E> addToStart<E>(List<E> list, E item, int? maxPages) {
  final result = [item, ...list];
  if (maxPages != null && result.length > maxPages) {
    return result.sublist(0, maxPages);
  }
  return result;
}

/// Flutter port of React's `infiniteQueryBehavior()`.
///
/// Replaces the default [QueryOptions.queryFn]-based fetch with page-aware
/// logic:
/// - `direction == null`    → refetch all existing pages in order (initial load
///   or background refetch).
/// - `direction == forward`  → append a new page at the end.
/// - `direction == backward` → prepend a new page at the start.
///
/// [TPage] is the type of a single page result.
/// [TPageParam] is the type of the page parameter (int, String, cursor object…).
class InfiniteQueryBehavior<TPage, TPageParam>
    extends QueryBehavior<InfiniteData<TPage, TPageParam>> {
  const InfiniteQueryBehavior();

  @override
  void onFetch(dynamic ctx, dynamic _query) {
    final context = ctx as FetchContext<InfiniteData<TPage, TPageParam>>;
    final opts = context.options as InfiniteQueryOptions<TPage, TPageParam>;
    final direction = context.meta?.fetchMore?.direction;

    context.fetchFn = () async {
      // ── Existing InfiniteData from cache ───────────────────────────────
      final rawResult = context.currentEntry?.result;
      InfiniteData<TPage, TPageParam> current;
      try {
        final typed =
            rawResult as QueryResult<InfiniteData<TPage, TPageParam>>?;
        current = typed?.data ??
            InfiniteData<TPage, TPageParam>(pages: [], pageParams: []);
      } catch (_) {
        current = InfiniteData<TPage, TPageParam>(pages: [], pageParams: []);
      }
      final oldPages = current.pages;
      final oldParams = current.pageParams;

      // ── Forward: append one page ───────────────────────────────────────
      if (direction == FetchDirection.forward) {
        if (opts.getNextPageParam == null || oldPages.isEmpty) {
          return InfiniteData(pages: oldPages, pageParams: oldParams);
        }
        final lastIndex = oldPages.length - 1;
        final nextParam = opts.getNextPageParam!(
          oldPages[lastIndex],
          oldPages,
          oldParams[lastIndex],
          oldParams,
        );
        if (nextParam == null) {
          return InfiniteData(pages: oldPages, pageParams: oldParams);
        }
        final page = await opts.pageQueryFn(nextParam);
        if (page == null) {
          return InfiniteData(pages: oldPages, pageParams: oldParams);
        }
        return InfiniteData(
          pages: addToEnd(oldPages, page as TPage, opts.maxPages),
          pageParams: addToEnd(oldParams, nextParam, opts.maxPages),
        );
      }

      // ── Backward: prepend one page ─────────────────────────────────────
      if (direction == FetchDirection.backward) {
        if (opts.getPreviousPageParam == null || oldPages.isEmpty) {
          return InfiniteData(pages: oldPages, pageParams: oldParams);
        }
        final prevParam = opts.getPreviousPageParam!(
          oldPages[0],
          oldPages,
          oldParams[0],
          oldParams,
        );
        if (prevParam == null) {
          return InfiniteData(pages: oldPages, pageParams: oldParams);
        }
        final page = await opts.pageQueryFn(prevParam);
        if (page == null) {
          return InfiniteData(pages: oldPages, pageParams: oldParams);
        }
        return InfiniteData(
          pages: addToStart(oldPages, page as TPage, opts.maxPages),
          pageParams: addToStart(oldParams, prevParam, opts.maxPages),
        );
      }

      // ── Null direction: refetch all existing pages (or initial page) ───
      // Mirror React: use oldParams[0] as the starting param if pages exist,
      // otherwise fall back to initialPageParam.
      final int pageCount = oldPages.isNotEmpty ? oldPages.length : 1;
      TPageParam? pageParam =
          oldParams.isNotEmpty ? oldParams[0] : opts.initialPageParam;

      final resultPages = <TPage>[];
      final resultParams = <TPageParam>[];

      for (var i = 0; i < pageCount; i++) {
        if (pageParam == null) break;
        final page = await opts.pageQueryFn(pageParam);
        if (page == null) break;
        resultPages.add(page as TPage);
        resultParams.add(pageParam);

        if (opts.getNextPageParam == null) break;
        final nextParam = opts.getNextPageParam!(
          page,
          resultPages,
          pageParam,
          resultParams,
        );
        if (nextParam == null) break;
        pageParam = nextParam;
      }

      return InfiniteData(pages: resultPages, pageParams: resultParams);
    };
  }
}
