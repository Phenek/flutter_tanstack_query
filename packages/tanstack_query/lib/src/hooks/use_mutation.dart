import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Hook to perform mutations (writes) and track mutation state.
///
/// Use this hook to execute a mutation function and observe its state
/// (`status`, `error`, `data`). It returns a [MutationResult<T, P>] which
/// exposes:
/// - `mutate(P params)`: triggers the mutation and swallows errors,
/// - `mutateAsync(P params, [MutateOptions<T>? options])`: returns the
///    Future of the mutation,
/// - `reset()`: resets the mutation state.
///
/// Parameters:
/// - [mutationFn] (required): Function that performs the mutation and returns
///   a `Future<T>` given parameters of type `P`.
/// - [onSuccess]: Called with the mutation result `T` when the mutation
///   completes successfully.
/// - [onError]: Called with the error object when the mutation fails.
/// - [onSettled]: Called when the mutation finishes either successfully or
///   with an error. Signature: `(T? data, Object? error)`.
/// - [retry]: Controls retry behavior. May be:
///   - `false` (no retry),
///   - `true` (retry indefinitely),
///   - an `int` (maximum attempts), or
///   - a function `(failureCount, error) => bool` that returns whether to retry.
/// - [retryDelay]: Delay between retries in milliseconds, or a function
///   `(attempt, error) => int` that returns the delay in ms.
/// - [gcTime]: Garbage-collection time in milliseconds for this mutation's
///   state; when <= 0 GC is disabled. If omitted, the client default is used.
/// - [mutationKey]: A `List<Object>` uniquely identifying the mutation (optional).
///
/// Returns:
/// A [MutationResult<T, P>] to trigger and observe the mutation.
MutationResult<T, P> useMutation<T, P>(
    {required Future<T> Function(P) mutationFn,
    List<Object>? mutationKey,
    void Function(T?, [MutationFunctionContext? context])? onSuccess,
    void Function(Object?, [MutationFunctionContext? context])? onError,
    void Function(T?, Object?, [MutationFunctionContext? context])? onSettled,
    dynamic retry,
    dynamic retryDelay,
    int? gcTime}) {
  final queryClient = useQueryClient();
  final cacheKey = mutationKey != null ? queryKeyToCacheKey(mutationKey) : null;

  final options = useMemoized(
      () => MutationOptions<T, P>(
            mutationFn: mutationFn,
            mutationKey: mutationKey,
            onSuccess: onSuccess,
            onError: onError,
            onSettled: onSettled,
            retry: retry,
            retryDelay: retryDelay,
            gcTime: gcTime,
          ),
      [
        mutationFn,
        mutationKey,
        onSuccess,
        onError,
        onSettled,
        retry,
        retryDelay,
        gcTime
      ]);

  // Observer follows the same pattern as useQuery: create once and
  // keep it in sync via setOptions to avoid complex lifecycle code in the hook.
  // Create the observer once for this cache key and keep it in sync via setOptions
  final observer = useMemoized<MutationObserver<T, P>>(
      () => MutationObserver<T, P>(queryClient, options),
      [queryClient, cacheKey]);

  // Keep observer options in sync when any option changes
  useEffect(() {
    observer.setOptions(options);
    return null;
  }, [observer, options]);

  // Local result state that mirrors the observer's current result
  final resultState =
      useState<MutationObserverResult<T, P>>(observer.getCurrentResult());

  useEffect(() {
    // subscribe updates
    final unsubscribe = observer.subscribe((res) {
      Future.microtask(() {
        try {
          resultState.value = res;
        } catch (_) {}
      });
    });

    return () => unsubscribe();
  }, [observer]);

  // Mutate function mirrors the observer mutate API and swallows errors
  void mutate(P params) {
    observer.mutate(params).then((_) {}, onError: (_) {});
  }

  // Async mutate that returns the future from the observer
  Future<T> mutateAsync(P params, [MutateOptions<T>? options]) {
    return observer.mutate(params, options);
  }

  // Reset mutation state
  void reset() {
    observer.reset();
  }

  return MutationResult<T, P>(
      mutate, mutateAsync, reset, () => resultState.value);
}
