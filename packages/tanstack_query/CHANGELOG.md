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