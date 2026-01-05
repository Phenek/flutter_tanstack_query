---
id: useQuery
title: useQuery
---

```dart
const {
  data,
  error,
  status,
  isFetching,
  isStale,
  isError,
  isSuccess,
  failureCount,
  failureReason,
  refetch,
} = useQuery(
  {
    queryKey,
    queryFn,
    staleTime,
    enabled,
    refetchOnRestart,
    refetchOnReconnect,
    gcTime,
    retry,
    retryOnMount,
    retryDelay,
  },
  queryClient,
)
```

**Parameter1 (Options)**

- `queryKey: List<Object>`
  - **Required**
  - The query key to use for this query.
  - The query key will be hashed into a stable hash. See [Query Keys](../03-Guides-&-Concepts/03-query-keys.md) for more information.
  - The query will automatically update when this key changes (as long as `enabled` is not set to `false`).
- `queryFn: Future<T> Function()`
  - **Required**
  - The function that the query will use to request data. Must return a `Future<T>`.
- `enabled: bool?`
  - Optional
  - Defaults to `queryClient.defaultOptions.queries.enabled` when not specified.
  - Set this to `false` to disable this query from automatically running (useful for dependent queries).
- `staleTime: double?`
  - Optional
  - The time in milliseconds after which data is considered stale. If `null`, the client's default `staleTime` is used.
- `refetchOnRestart: bool?`
  - Optional
  - When `true`, refetches on app restart.
- `refetchOnReconnect: bool?`
  - Optional
  - When `true`, refetches on reconnect.
- `gcTime: int?`
  - Optional
  - Garbage-collection time in milliseconds for this query's cache entry. When all observers are removed, the query will be removed from the cache after `gcTime` ms. A value `<= 0` disables GC. If unspecified, the client default is used.
- `retry: dynamic`
  - Optional
  - Controls retry behavior; accepts `false`, `true`, an `int`, or a function `(failureCount, error) => bool`.
- `retryOnMount: bool?`
  - Optional
  - If `false`, a query that currently has an error will not attempt to retry when mounted.
- `retryDelay: dynamic`
  - Optional
  - Milliseconds between retries, or a function `(attempt, error) => int` returning the delay in ms.

**Parameter2 (QueryClient)**

- `queryClient: QueryClient?`
  - Optional. Use this to provide a custom `QueryClient`; otherwise the one from the nearest context will be used.

**Returns**

- `key: String`
  - The internal cache key (string) for this query.
- `status: QueryStatus`
  - Will be:
    - `pending` if there's no cached data and no query attempt has finished yet.
    - `error` if the query attempt resulted in an error; the `error` property contains the error.
    - `success` if the query has received a response with no errors and is ready to display its data.
- `isPending: bool`
  - A derived boolean from `status`.
- `isSuccess: bool`
  - A derived boolean from `status`.
- `isError: bool`
  - A derived boolean from `status`.
- `data: T?`
  - Defaults to `null`.
  - The last successfully resolved data for the query.
- `error: Object?`
  - Defaults to `null`.
  - The error object for the query, if an error was thrown.
- `isFetching: bool`
  - `true` when the query function is currently executing (includes background refetches).
- `isStale: bool`
  - `true` when the cached data is considered stale.
- `failureCount: int`
  - The number of consecutive failures for the current fetch cycle.
- `failureReason: Object?`
  - The last failure reason, if any.
- `refetch: Future<QueryResult<T>> Function({bool? throwOnError})?`
  - A function to manually refetch the query. Pass `throwOnError: true` to throw on error instead of returning it in the result.
