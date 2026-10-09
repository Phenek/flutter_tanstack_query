---
id: useInfiniteQuery
title: useInfiniteQuery
---

```dart
/// QueryResult<List<T>> (properties only)
class InfiniteQueryResult<T> {
  bool isFetchingNextPage;
  bool isFetchingPreviousPage;
  bool isFetchNextPageError;
  bool isFetchPreviousPageError;
  bool isRefetching;
  bool isRefetchError;
  bool hasNextPage;
  bool hasPreviousPage;
  Function? fetchNextPage;
  Function? fetchPreviousPage;
  ...result
}

/// Prototype of useQuery (properties only)
InfiniteQueryResult<T> useInfiniteQuery<T>({
  required int initialPageParam,
  int Function(T lastResult)? getNextPageParam,
  int Function(T firstResult)? getPreviousPageParam,
  ...options,
})
```

**Options**

- `initialPageParam: int`
  - **Required**
  - The initial page index to start fetching from.
- `getNextPageParam: int Function(T lastResult)?`
  - **Optional**
  - Given the last page (and the full pages array), returns the next page param to fetch, or `null`/`undefined` to indicate there is no next page.
- `getPreviousPageParam: int Function(T firstResult)?`
  - **Optional**
  - Given the first page (and the full pages array), returns the previous page param to fetch, or `null`/`undefined` to indicate there is no previous page.

**Returns (additional properties only)**

- `data: List<T>?`
  - Pages accumulated so far, where each entry corresponds to a single page result.
- `isFetchingNextPage: bool`
  - `true` while fetching the next page.
- `isFetchingPreviousPage: bool`
  - `true` while fetching the previous page.
- `isFetchNextPageError: bool`
  - `true` when the last `fetchNextPage` attempt failed.
- `isFetchPreviousPageError: bool`
  - `true` when the last `fetchPreviousPage` attempt failed.
- `isRefetching: bool`
  - `true` while refetching the full infinite query.
- `isRefetchError: bool`
  - `true` when the last refetch attempt failed.
- `hasNextPage: bool`
  - `true` when `getNextPageParam` returns a non-null page param based on the last page.
- `hasPreviousPage: bool`
  - `true` when `getPreviousPageParam` returns a non-null page param based on the first page.
- `fetchNextPage: Function?`
  - Imperative function to trigger fetching the next page.
- `fetchPreviousPage: Function?`
  - Imperative function to trigger fetching the previous page.
- `...result`
  - The remaining properties are the standard `useQuery` result fields (e.g., `status`, `error`, `isFetching`, etc.).

Keep in mind that imperative fetch calls, such as `fetchNextPage`, may interfere with default refetch behaviour. Call these functions in response to user actions when possible.
