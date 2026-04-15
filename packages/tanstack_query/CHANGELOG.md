## 1.3.0 (15/04/26)

**Breaking:** Full React parity for `useInfiniteQuery` — mirrors `useInfiniteQuery` from `@tanstack/react-query` exactly in types, signatures, and behavior.

- **Breaking:** Introduced `InfiniteData<TData, TPageParam>` struct with `pages: List<TData>` and `pageParams: List<TPageParam>` fields. `data` on `InfiniteQueryResult` is now `InfiniteData<T, TPageParam>?` instead of `List<T>?`. Access pages via `result.data!.pages`.
- **Breaking:** `useInfiniteQuery`, `InfiniteQueryOptions`, and `InfiniteQueryResult` now require a second type parameter `TPageParam` (e.g. `useInfiniteQuery<MyPage, int>`).
- **Breaking:** `getNextPageParam` and `getPreviousPageParam` now accept 4 arguments — `(lastPage, allPages, lastPageParam, allPageParams)` — matching the React signature exactly.
- **Breaking:** `setQueryInfiniteData` now takes `InfiniteData<T, TPageParam>` in its updater function instead of `List<T>`.
- **Feat:** `pageParams` are tracked in parallel with `pages` inside `InfiniteData`, enabling full page-param history (mirrors React's `InfiniteData<TData, TPageParam>`).
- **Feat:** Added `maxPages` option to `InfiniteQueryOptions` and `useInfiniteQuery`. Oldest pages (and their params) are trimmed when the limit is exceeded, mirroring React's `addToStart`/`addToEnd` utilities.
- **Feat:** `Retryer` now supports `onPause` and `onContinue` callbacks and pauses the retry loop when the app loses focus or goes offline (`focusManager.isFocused()` + `onlineManager.isOnline()`), mirroring React's `canContinue` / `pause()` logic.
- **Feat:** `defaultRetryDelay` now uses exponential backoff — `min(1000 * 2^attempt, 30000)` — matching React's formula exactly. This is the new default for `QueryDefaultOptions.retryDelay`.

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