## 2.0.0 (unreleased)

### New hooks

- `usePrefetchQuery` — warms a key while a widget builds, without subscribing to it.
- `usePrefetchInfiniteQuery` — the same, for an infinite query's first page.

### New `QueryClient` methods

- `fetchQuery` — fetch a key from outside the widget tree, deduplicated and cached (`retry: false` unless something else configures it).
- `prefetchQuery` — `fetchQuery` that returns nothing and throws nothing.
- `ensureQueryData` — the cached data, fetching only when there is none; `revalidateIfStale` refetches behind it.
- `fetchInfiniteQuery` / `prefetchInfiniteQuery` / `ensureInfiniteQueryData` — the same three, for infinite queries.
- `getQueryData` / `getQueryState` — read the cache without building a query or starting a fetch.
- `getQueriesData` — every cached entry matching a key, as `(queryKey, data)` pairs.
- `setQueryDataValue` — store a value directly, the JavaScript `setQueryData(key, value)` form.
- `setQueryDefaults` / `getQueryDefaults` — default options per key, matched element by element.
- `removeQueries` / `resetQueries` — drop matching queries; `resetQueries` refetches the active ones.

### React Query parity fixes

- Fix: key filters (`invalidateQueries`, `removeQueries`, `resetQueries`, `getQueriesData`) match element by element through `partialMatchKey`, not by `String.startsWith` on the serialized key — `['todos', 1]` no longer matches `['todos', 11]`.
- Fix: `removeQueries` / `resetQueries` also reach cache entries written by `setQueryData` before any observer mounted, like React's `queryCache.findAll`.
- Fix: a mounted `useQuery` falls back to `pending` after its entry is removed, instead of showing the removed data for good.
- Fix: a `structuralSharing` merge function written inline is used. Being declared as `Object?` (so it can also hold `false`), the option left an inline closure typed `dynamic Function(dynamic, dynamic)`, which the typed check missed and silently ignored.
- Fix: `fetchQuery` / `prefetchQuery` / `ensureQueryData` and their infinite variants apply `retry: false` only when nothing else configured it, so `defaultOptions.queries.retry` and `setQueryDefaults(retry:)` reach them. `QueryDefaultOptions.retry` now defaults to `null` ("not configured"); the retryer still falls back to 3, as `createRetryer` does in JavaScript.
- Fix: `QueryResult.isStale` comes from `Query.isStaleByTime`, the single implementation — an errored query (no data) now reports `isStale: true` and refetches on focus/reconnect.
- Fix: an invalidated query is stale even with `staleTime: double.infinity`, so `fetchQuery` refetches it.
- Fix: `InfiniteQueryResult` equality covers its own fields, so a change confined to e.g. `hasNextPage` is no longer swallowed by the "result unchanged" guard; the cached page list keeps its identity across recomputations.
- Fix: `ensureInfiniteQueryData` fetches only when there are no cached pages (an empty list is data) and accepts `revalidateIfStale`, like the JS version delegating to `ensureQueryData`.
- Fix: `invalidateQueries`, `removeQueries` and `resetQueries` run inside `notifyManager.batch`, so one call over N queries rebuilds once.

## 1.2.8 (05/10/26)

- Fix: `invalidateQueries` now keeps cached data while refetching in the background, like React Query. Previously the UI briefly showed `pending` with `data: null`.
- Fix: `invalidateQueries` only refetches active queries. Disabled or unmounted ones are marked stale and refetch on next mount.
- Fix: Invalidated infinite queries keep and refetch all loaded pages.
- Fix: A disabled `useQuery` with cached data no longer stays `pending` on mount.
- Feat: `Query.isInvalidated`. An invalidated query is stale regardless of `staleTime` until new data lands.
- Chore: Fix unused catch variable lint.

## 1.2.7 (15/04/26)

- Fix: `gcTime: 0` now evicts the cache immediately on unmount (next event loop tick), matching React Query's `setTimeout(..., 0)` behaviour. Previously `gcTime: 0` was silently treated as "GC disabled".
- Fix: `gcTime` semantics clarified — negative values disable GC, `0` means immediate eviction, positive values delay eviction by N ms.
- Fix: `MutationDefaultOptions.gcTime` default changed to `5 minutes` (300 000 ms), matching React Query's default for both queries and mutations.
- Fix: Cached `InfiniteQuery` pages are now shown immediately on remount (matching React behaviour) instead of being hidden behind `status: pending` and re-fetched all at once.

## 1.2.6 (15/04/26)

- Fix: Garbage collection bug where active `Query` could be evicted after `invalidateQueries()` or `clear()` — mirrors React's GC lifecycle exactly.
- Arch: `QueryObserver` mirrors React's GC lifecycle exactly by rebuilding the underlying `Query` reference after cache invalidation.
- Arch: Rework `useInfiniteQuery` internals to mirror React's architecture exactly — extract `InfiniteQueryBehavior` (port of `infiniteQueryBehavior.ts`), rewrite `InfiniteQueryObserver` (port of `InfiniteQueryObserver.ts`), and hook behavior into `Query.fetch()` for React-parity dedup, direction tracking, and page management.
- Fix: `isFetchingNextPage` incorrectly `true` on remount after `fetchNextPage`.
- Fix: Rapid `fetchNextPage` calls no longer cause stuck `isFetchingNextPage` state.
- Fix: Mismatched generic cache entries (e.g. `InfiniteQueryResult<Object>` for a `useInfiniteQuery<int>`) are now safely detected and discarded, triggering a fresh fetch.

## 1.2.5 (23/01/26)

- Fix: Prevent infinite widget rebuilds when passing inline (non-const) `mutationKey` to `useMutation`.

## 1.2.4 (18/01/26)

- Correct default GC Time to 5 minutes

## 1.2.3 (18/01/26)

- refactor queryObservers
- add useInfiniteQuery properties result (isFetchingPreviousPage, isFetchNextPageError, hasNextPage, ...)

## 1.2.2 (17/01/26)

- add context to mutation callbacks
- bug fixes and performance improvements

## 1.2.1 (14/01/26)

- upgrade sdk requirement
- fix analysis

## 1.2.0 (14/01/26)

- add refetchOnMount, initialData & placeholderData features
- rework refetchOnWindowFocus refetchOnReconnect

## 1.1.1 (04/01/26)

- Clean dart format

## 1.1.0 (04/01/26)

- Rework internals: move hook logic into core `QueryObserver` / `Query` and `MutationObserver` / `Mutation`.
- Move `QueryCache` into `QueryClient` and remove legacy `QueryClient.Instance`.
- Implement `gcTime` and garbage collection scheduling for inactive queries.
- Add `retry` / `retryDelay` support (exponential backoff) and `Retryer`; add fixes/tests for retry behavior (including `useInfiniteQuery`).
- Expose `mutateAsync` and `resetMutation` APIs.
- Fix observer subscriber management and refactor with `Removable`.
- Update docs, changelogs, dartdoc and add tests.

## 1.0.2 (30/12/25)

- Add dartdoc comments.

## 1.0.1 (28/12/25)

- Add `useQueryClient` hook to retrieve the active `QueryClient` from widget context.

## 1.0.0 (18/12/25)

- First version with primary hooks (useQuery, useMutation, useInfiniteQuery)