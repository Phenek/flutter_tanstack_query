---
id: useInfiniteQuery
title: useInfiniteQuery
---

```dart
/// QueryResult<T> (properties only)
class InfiniteQueryResult<T> {
  bool isFetchingNextPage;
  Function? fetchNextPage;
  ...result
}

/// Prototype of useQuery (properties only)
QueryResult<T> useQuery<T>({
  required int initialPageParam,
  int Function(T lastResult)? getNextPageParam,
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

**Returns (additional properties only)**

- `isFetchingNextPage: bool`
  - `true` while fetching the next page.
- `fetchNextPage: Function?`
  - Imperative function to trigger fetching the next page (behavior may vary between JS and Dart implementations).
- `...result`
  - The remaining properties are the standard `useQuery` result fields (e.g., `data`, `status`, `error`, `isFetching`, etc.).

Keep in mind that imperative fetch calls, such as `fetchNextPage`, may interfere with default refetch behaviour. Call these functions in response to user actions when possible.
