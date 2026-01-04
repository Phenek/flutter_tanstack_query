---
id: useInfiniteQuery
title: useInfiniteQuery
---

```dart
const {
  fetchNextPage,
  isFetchingNextPage,
  ...result
} = useInfiniteQuery({
  queryKey,
  queryFn: (pageParam) => fetchPage(pageParam),
  initialPageParam: 1,
  // optional: getNextPageParam: (lastPage) => nextPageIndex,
  // optional: debounceTime: Duration(milliseconds: 200),
})
```

**Options**

- `queryKey: List<Object>`
  - **Required**
  - Unique key identifying this infinite query.
- `queryFn: Future<T?> Function(int pageParam)`
  - **Required**
  - The page-aware query function. Receives a page index and should return the page data (or `null` when not available).
- `initialPageParam: int`
  - **Required**
  - The initial page index to start fetching from.
- `getNextPageParam: int Function(T lastResult)?`
  - Optional
  - Computes the next page index given the last page result. If it returns a value less than or equal to the current page index, no next page will be fetched.
- `debounceTime: Duration?`
  - Optional
  - If set, delays the initial fetch by the provided duration to debounce rapid key changes.
- `staleTime: double?`
  - Optional
  - Staleness duration (milliseconds) for cached pages.
- `enabled: bool?`
  - Optional
  - Whether the query is enabled.
- `refetchOnRestart: bool?`
  - Optional
  - When `true`, refetches pages on app restart.
- `refetchOnReconnect: bool?`
  - Optional
  - When `true`, refetches pages on reconnect.
- `gcTime: int?`
  - Optional
  - Garbage-collection time in milliseconds for this query's cache entry.
- `retry: dynamic`
  - Optional
  - Retry behavior (same as `useQuery`): `bool`, `int`, or a function `(failureCount, error) => bool`.
- `retryOnMount: bool?`
  - Optional
  - Whether to retry on mount when in an error state.
- `retryDelay: dynamic`
  - Optional
  - Milliseconds between retries or a function `(attempt, error) => int` returning the delay in ms.

**Returns**

- `data: List<T>`
  - The accumulated list of page results (defaults to an empty list when pending).
- `isFetching: bool`
  - `true` when any fetch is in-flight (including background refetches).
- `isFetchingNextPage: bool`
  - `true` while fetching the next page with `fetchNextPage`.
- `fetchNextPage: void Function()?`
  - Trigger fetching the next page. Note: this is an imperative trigger and does not return a completion `Future` in the current implementation.
- `failureCount: int`
  - Number of consecutive failures for the current fetch attempt.
- `failureReason: Object?`
  - The last failure reason, if any.

Keep in mind that imperative fetch calls, such as `fetchNextPage`, may interfere with default refetch behaviour. Call these functions in response to user actions when possible.
