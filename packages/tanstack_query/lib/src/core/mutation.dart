import 'package:tanstack_query/tanstack_query.dart';

/// Action emitted by a [Mutation] to observers.
enum MutationActionType { pending, success, error }

class MutationAction<T> {
  final MutationActionType type;
  final T? data;
  final Object? error;

  MutationAction._(this.type, {this.data, this.error});

  factory MutationAction.pending() => MutationAction._(MutationActionType.pending);
  factory MutationAction.success(T data) => MutationAction._(MutationActionType.success, data: data);
  factory MutationAction.error(Object error) => MutationAction._(MutationActionType.error, error: error);
}

/// Per-mutation call options passed to `mutate`.
class MutateOptions<T> {
  final void Function(T?)? onSuccess;
  final void Function(Object?)? onError;
  final void Function(T?, Object?)? onSettled;

  MutateOptions({this.onSuccess, this.onError, this.onSettled});
}

/// Options used to create a Mutation/Observer.
class MutationOptions<T, P> {
  final Future<T> Function(P) mutationFn;
  final dynamic mutationKey;
  final void Function()? onMutate;
  final void Function(T?)? onSuccess;
  final void Function(Object?)? onError;
  final void Function(T?, Object?)? onSettled;

  MutationOptions({
    required this.mutationFn,
    this.mutationKey,
    this.onMutate,
    this.onSuccess,
    this.onError,
    this.onSettled,
  });
}

/// A single mutation instance that holds its state and notifies observers on
/// lifecycle events.
class Mutation<T, P> {
  final QueryClient client;
  MutationOptions<T, P> options;

  MutationState<T> state = MutationState<T>(null, MutationStatus.idle, null);
  final Set<dynamic> _observers = <dynamic>{};

  Mutation(this.client, this.options);

  void addObserver(dynamic observer) {
    _observers.add(observer);
  }

  void removeObserver(dynamic observer) {
    _observers.remove(observer);
  }

  void _notifyObservers(MutationAction<T> action) {
    for (var o in List.from(_observers)) {
      try {
        o.onMutationUpdate(action);
      } catch (_) {
        // ignore listener errors
      }
    }
  }

  /// Execute the mutation with [variables]. This updates internal state and
  /// calls cache-level lifecycle hooks from [QueryClient.mutationCache.config].
  Future<T> execute(P variables) async {
    // onMutate hook
    try {
      options.onMutate?.call();
    } catch (_) {}

    state = MutationState<T>(null, MutationStatus.pending, null);
    _notifyObservers(MutationAction.pending());

    try {
      final data = await options.mutationFn(variables);

      state = MutationState<T>(data, MutationStatus.success, null);
      _notifyObservers(MutationAction.success(data));

      // Per-mutation hooks
      try {
        options.onSuccess?.call(data);
        options.onSettled?.call(data, null);
      } catch (_) {}

      // Global cache hooks
      client.mutationCache.config.onSuccess?.call(data);
      client.mutationCache.config.onSettled?.call(data, null);

      return data;
    } catch (e) {
      state = MutationState<T>(null, MutationStatus.error, e);
      _notifyObservers(MutationAction.error(e));

      try {
        options.onError?.call(e);
        options.onSettled?.call(null, e);
      } catch (_) {}

      client.mutationCache.config.onError?.call(e);
      client.mutationCache.config.onSettled?.call(null, e);

      rethrow;
    }
  }

  void setOptions(MutationOptions<T, P> newOptions) {
    options = newOptions;
  }
}
