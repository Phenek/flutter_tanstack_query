---
id: useQuery
title: useQuery
---

```dart
/// QueryResult<T> (properties only)
class QueryResult<T> {
  final T? data;
  final int dataUpdatedAt;
  final Object? error;
  final int failureCount;
  final Object? failureReason;
  final bool isError;
  final bool isFetching;
  final bool isPending;
  final bool isPlaceholderData;
  final bool isStale;
  final bool isSuccess;
  final Future<QueryResult<T>> Function({bool? throwOnError})? refetch;
  final QueryStatus status;
}

/// Prototype of useQuery (properties only)
QueryResult<T> useQuery<T>({
  required List<Object> queryKey,
  required Future<T> Function() queryFn,
  int? gcTime,
  bool? enabled,
  T? initialData,
  int? initialDataUpdatedAt,
  T Function(T? previousValue, Query? previousQuery)? placeholderData,
  bool? refetchOnMount,
  bool? refetchOnReconnect,
  bool? refetchOnWindowFocus,
  dynamic retry,
  bool? retryOnMount,
  dynamic retryDelay,
  double? staleTime,
})
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
- `gcTime: int?`
  - Optional
  - Garbage-collection time in milliseconds for this query's cache entry. When all observers are removed, the query will be removed from the cache after `gcTime` ms. A value `<= 0` disables GC. If unspecified, the client default is used.
- `enabled: bool?`
  - Optional
  - Defaults to `queryClient.defaultOptions.queries.enabled` when not specified.
  - Set this to `false` to disable this query from automatically running (useful for dependent queries).
- `initialData: TData | () => TData`
  - Optional
  - If set, this value will be used as the initial data for the query cache (as long as the query hasn't been created or cached yet)
  - If set to a function, the function will be called once during the shared/root query initialization, and be expected to synchronously return the initialData
  - Initial data is considered stale by default unless a staleTime has been set.
  - `initialData` is persisted to the cache
- `initialDataUpdatedAt: number | (() => number | undefined)`
  - Optional
  - If set, this value will be used as the time (in milliseconds) of when the initialData itself was last updated.
- `placeholderData: TData | (previousValue: TData | undefined, previousQuery: Query | undefined) => TData`
  - Optional
  - If set, this value will be used as the placeholder data for this particular query observer while the query is still in the pending state.
  - `placeholderData` is not persisted to the cache
  - If you provide a function for `placeholderData`, as a first argument you will receive previously watched query data if available, and the second argument will be the complete `previousQuery` instance.
- `refetchOnMount: bool?`
  - Optional
  - When `true`, refetches when the observer mounts/subscribes.
- `refetchOnReconnect: bool?`
  - Optional
  - When `true`, refetches on reconnect.
- `refetchOnWindowFocus: bool?`
  - Optional
  - When `true`, refetches on window/app focus.
- `retry: dynamic`
  - Optional
  - Controls retry behavior; accepts `false`, `true`, an `int`, or a function `(failureCount, error) => bool`.
- `retryOnMount: bool?`
  - Optional
  - If `false`, a query that currently has an error will not attempt to retry when mounted.
- `retryDelay: dynamic`
  - Optional
  - Milliseconds between retries, or a function `(attempt, error) => int` returning the delay in ms.
- `staleTime: double?`
  - Optional
  - The time in milliseconds after which data is considered stale. If `null`, the client's default `staleTime` is used.

**Returns**

- `data: T?`
  - Defaults to `null`.
  - The last successfully resolved data for the query.
- `dataUpdatedAt: number`
  - The timestamp for when the query most recently returned the status as "success" (milliseconds since epoch).
- `error: Object?`
  - Defaults to `null`.
  - The error object for the query, if an error was thrown.
- `failureCount: int`
  - The number of consecutive failures for the current fetch cycle.
- `failureReason: Object?`
  - The last failure reason, if any.
- `isError: bool`
  - A derived boolean from `status`.
- `isFetching: bool`
  - `true` when the query function is currently executing (includes background refetches).
- `isPending: bool`
  - A derived boolean from `status`.
- `isPlaceholderData: boolean`
  - Will be true if the data shown is the placeholder data (placeholder results are observer-only and not persisted).
- `isStale: bool`
  - `true` when the cached data is considered stale.
- `isSuccess: bool`
  - A derived boolean from `status`.
- `refetch: Future<QueryResult<T>> Function({bool? throwOnError})?`
  - A function to manually refetch the query. Pass `throwOnError: true` to throw on error instead of returning it in the result.
- `status: QueryStatus`
  - Will be:
    - `pending` if there's no cached data and no query attempt has finished yet.
    - `error` if the query attempt resulted in an error; the `error` property contains the error.
    - `success` if the query has received a response with no errors and is ready to display its data.
