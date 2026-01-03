import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Hook to perform mutations (writes). Returns a [MutationResult] that exposes
/// `mutate(params)` and mutation state (`status`, `error`, `data`).
///
/// Parameters:
/// - [mutationFn]: Required function that performs the mutation and returns
///   the result as a `Future<T>`.
/// - [onSuccess]: Called when the mutation completes successfully.
/// - [onError]: Called when the mutation fails with an error.
/// - [onSettle]: Called when the mutation finishes either successfully or with
///   an error. Receives `(data, error)`.
///
/// Returns a [MutationResult<T, P>] with a `mutate` function to trigger the
/// mutation and fields to observe the current mutation state.
MutationResult<T, P> useMutation<T, P>(
    {required Future<T> Function(P) mutationFn,
    void Function(T?)? onSuccess,
    void Function(Object?)? onError,
    void Function(T?, Object?)? onSettle}) {
  final queryClient = useQueryClient();

  // Create observer once per hook instance
  final observer = useMemoized<MutationObserver<T, P>>(() => MutationObserver<T, P>(
        queryClient,
        MutationOptions<T, P>(
          mutationFn: mutationFn,
          onSuccess: onSuccess,
          onError: onError,
          onSettled: onSettle,
        ),
      ));

  // Keep observer options in sync when parameters change
  useEffect(() {
    observer.setOptions(MutationOptions<T, P>(
      mutationFn: mutationFn,
      onSuccess: onSuccess,
      onError: onError,
      onSettled: onSettle,
    ));
    return null;
  }, [observer, mutationFn, onSuccess, onError, onSettle]);

  // Local result state that mirrors the observer's current result
  final resultState = useState<MutationObserverResult<T, P>>(observer.getCurrentResult());

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

  return MutationResult<T, P>(
      mutate, resultState.value.data, resultState.value.status, resultState.value.error);
}
