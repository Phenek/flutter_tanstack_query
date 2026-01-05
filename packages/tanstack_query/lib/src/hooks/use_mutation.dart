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
/// - `resetMutation()`: resets the mutation state,
/// - `result()`: getter for the current [MutationObserverResult<T, P>].
///
/// Parameters:
/// - [mutationFn] (required): Function that performs the mutation and returns
///   a `Future<T>` given parameters of type `P`.
/// - [onSuccess]: Called with the mutation result `T` when the mutation
///   completes successfully.
/// - [onError]: Called with the error object when the mutation fails.
/// - [onSettle]: Called when the mutation finishes either successfully or
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
///
/// Returns:
/// A [MutationResult<T, P>] to trigger and observe the mutation.
MutationResult<T, P> useMutation<T, P>(
    {required Future<T> Function(P) mutationFn,
    void Function(T?)? onSuccess,
    void Function(Object?)? onError,
    void Function(T?, Object?)? onSettle,
    dynamic retry,
    dynamic retryDelay,
    int? gcTime}) {
  final queryClient = useQueryClient();

  // Create observer once per hook instance
  final observer =
      useMemoized<MutationObserver<T, P>>(() => MutationObserver<T, P>(
            queryClient,
            MutationOptions<T, P>(
              mutationFn: mutationFn,
              onSuccess: onSuccess,
              onError: onError,
              onSettled: onSettle,
              retry: retry,
              retryDelay: retryDelay,
              gcTime: gcTime,
            ),
          ));

  // Keep observer options in sync when parameters change
  useEffect(() {
    observer.setOptions(MutationOptions<T, P>(
      mutationFn: mutationFn,
      onSuccess: onSuccess,
      onError: onError,
      onSettled: onSettle,
      retry: retry,
      retryDelay: retryDelay,
      gcTime: gcTime,
    ));
    return null;
  }, [
    observer,
    mutationFn,
    onSuccess,
    onError,
    onSettle,
    retry,
    retryDelay,
    gcTime
  ]);

  // Local result state that mirrors the observer's current result
  final resultState =
      useState<MutationObserverResult<T, P>>(observer.getCurrentResult());

  useEffect(() {
    // subscribe updates
    final unsubscribe = observer.subscribe((res) {
      resultState.value = res;
    });
    // initialize
    resultState.value = observer.getCurrentResult();
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
  void resetMutation() {
    observer.reset();
  }

  return MutationResult<T, P>(
      mutate, mutateAsync, resetMutation, () => resultState.value);
}
