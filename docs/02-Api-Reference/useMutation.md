---
id: useMutation
title: useMutation
---

```dart
class MutationResult<T, P> {
  final T? data;
  final Object? error;
  final bool isError;
  final bool isIdle;
  final bool isPending;
  final bool isSuccess;
  final int failureCount;
  final Object? failureReason;
  final void Function(P variables) mutate;
  final Future<T> Function(P variables, [MutateOptions<T>? options]) mutateAsync;
  final void Function() reset;
  final MutationStatus status;
}

MutationResult<T, P> useMutation<T, P>({
  required Future<T> Function(P) mutationFn,
  void Function(T?)? onSuccess,
  void Function(Object?)? onError,
  void Function(T?, Object?)? onSettled,
  dynamic retry,
  dynamic retryDelay,
  int? gcTime,
})
```

**Parameter1 (Options)**

- `mutationFn: Future<T> Function(P)`
  - **Required**
  - A function that performs the mutation and returns a `Future<T>`.
  - Receives a `P` value (the mutation variables) and should return the mutation result.
- `onSuccess: void Function(T?)?`
  - Optional
  - Called with the mutation result when the mutation succeeds.
- `onError: void Function(Object?)?`
  - Optional
  - Called with the error when the mutation fails.
- `onSettled: void Function(T?, Object?)?`
  - Optional
  - Called when the mutation finishes either successfully or with an error.
- `retry: dynamic`
  - Optional
  - Retry configuration: `bool` (true = infinite), `int` (max attempts), or a function `(failureCount, error) => bool`.
- `retryDelay: dynamic`
  - Optional
  - Delay between retries in milliseconds or a function `(attempt, error) => int`.
- `gcTime: int?`
  - Optional
  - Garbage collection time in milliseconds for the mutation's cache entry. When `<= 0`, GC is disabled. If omitted, the client default is used.

**Parameter2 (QueryClient)**

- `queryClient: QueryClient?`
  - Optional. Use this to provide a custom `QueryClient`; otherwise the one from the nearest context will be used.

**Returns**

- `data: T?`
  - Defaults to `null`.
  - The last successfully resolved data for the mutation.
- `error: Object?`
  - Defaults to `null`.
  - The error object for the mutation, if an error occurred.
- `isError: bool`
  - Whether the last mutation finished with an error.
- `isIdle: bool`
  - Whether the mutation is currently idle.
- `isPending: bool`
  - Whether the mutation is in progress.
- `isSuccess: bool`
  - Whether the last mutation finished successfully.
- `failureCount: int`
  - The failure count for the current retry cycle.
- `failureReason: Object?`
  - The last failure reason, if any.
- `mutate: void Function(P variables)`
  - Triggers the mutation and swallows errors (does not throw). Accepts an optional per-call `MutateOptions<T>` when used via the lower-level observer API.
- `mutateAsync: Future<T> Function(P variables, [MutateOptions<T>? options])`
  - Triggers the mutation and returns a `Future` that resolves with the mutation result or throws on error.
- `reset: void Function()`
  - Resets the mutation state to its initial state.
- `status: MutationStatus`
  - One of `idle`, `pending`, `error`, or `success`.

Notes:
- The hook exposes a small wrapper (`MutationResult`) around the underlying observer. Use `mutate` for fire-and-forget semantics or `mutateAsync` when you need a `Future`.
- The `variables` and `submittedAt` properties from some JS docs are not currently surfaced in the Dart observer result.
