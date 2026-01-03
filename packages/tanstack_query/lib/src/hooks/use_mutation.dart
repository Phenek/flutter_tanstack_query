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
  final state = useState<MutationState<T>>(
      MutationState<T>(null, MutationStatus.idle, null));
  var isMounted = true;

  useEffect(() {
    state.value = MutationState<T>(null, MutationStatus.idle, null);
    return () {
      isMounted = false;
    };
  }, []);

  void mutate(P params) async {
    if (!isMounted) return;
    state.value = MutationState<T>(null, MutationStatus.pending, null);
    try {
      final data = await mutationFn(params);
      if (!isMounted) return;
      state.value = MutationState<T>(data, MutationStatus.success, null);
      onSuccess?.call(data);
      onSettle?.call(data, null);
      QueryClient.instance.mutationCache.config.onSuccess?.call(data);
    } catch (e) {
      if (!isMounted) return;
      state.value = MutationState<T>(null, MutationStatus.error, e);
      onError?.call(e);
      onSettle?.call(null, e);
      QueryClient.instance.mutationCache.config.onError?.call(e);
    }
  }

  return MutationResult<T, P>(
      mutate, state.value.data, state.value.status, state.value.error);
}
