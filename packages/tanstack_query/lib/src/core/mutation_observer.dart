import 'package:tanstack_query/tanstack_query.dart';
import 'subscribable.dart';

/// The shape returned by an observer to listeners.
class MutationObserverResult<T, P> {
  final T? data;
  final MutationStatus status;
  final Object? error;
  final int failureCount;
  final Object? failureReason;
  final bool isPending;
  final bool isSuccess;
  final bool isError;
  final bool isIdle;

  final Future<T> Function(P variables, [MutateOptions<T>? options]) mutate;
  final void Function() reset;

  // Expose variables/context if available
  final P? variables;
  final dynamic context;

  MutationObserverResult({
    required this.data,
    required this.status,
    required this.error,
    required this.failureCount,
    required this.failureReason,
    required this.isPending,
    required this.isSuccess,
    required this.isError,
    required this.isIdle,
    required this.mutate,
    required this.reset,
    this.variables,
    this.context,
  });
}

/// Listener type for mutation observers.
typedef MutationObserverListener<T, P> = void Function(
    MutationObserverResult<T, P>);

/// Observer that mirrors the JS `MutationObserver`. It can be subscribed to by
/// multiple listeners and will reflect the state of the underlying active
/// `Mutation` instance.
class MutationObserver<T, P> extends Subscribable<Function> {
  MutationOptions<T, P> options;
  final QueryClient _client;

  MutationObserverResult<T, P>? _currentResult;
  Mutation<T, P>? _currentMutation;
  MutateOptions<T>? _mutateOptions;

  /// Cache unsubscribe function for mutation cache events
  void Function()? _cacheUnsubscribe;

  MutationObserver(this._client, this.options) {
    _updateResult();
    _subscribeToCache();
  }

  void setOptions(MutationOptions<T, P> options) {
    final prev = this.options;
    this.options = options;
    // If mutation key changed, reset the current mutation.
    if (prev.mutationKey != null &&
        options.mutationKey != null &&
        prev.mutationKey != options.mutationKey) {
      reset();
    } else if (_currentMutation?.state.isPending ?? false) {
      _currentMutation?.setOptions(options);
    }
  }

  /// Subscribe to mutation cache events so the observer can react to
  /// mutations being removed/updated externally.
  void _subscribeToCache() {
    _cacheUnsubscribe = _client.mutationCache.subscribe(_handleCacheEvent);
  }

  void _handleCacheEvent(MutationCacheNotifyEvent event) {
    // If the event mutation matches our current mutation, react accordingly
    if (_currentMutation == null) return;
    if (event.mutation != _currentMutation) return;

    if (event.type == NotifyEventType.removed) {
      // If our mutation was removed from cache, reset observer state
      reset();
    } else if (event.type == NotifyEventType.updated) {
      // Mutation updated -> refresh result
      _updateResult();
      _notify();
    }
  }

  @override
  void onUnsubscribe() {
    if (!hasListeners()) {
      _currentMutation?.removeObserver(this);
    }

    try {
      _cacheUnsubscribe?.call();
    } catch (_) {}
  }

  void onMutationUpdate(MutationAction<T> action) {
    _updateResult();
    _notify(action);
  }

  MutationObserverResult<T, P> getCurrentResult() => _currentResult!;

  void reset() {
    _currentMutation?.removeObserver(this);
    _currentMutation = null;
    _updateResult();
    _notify();
  }

  Future<T> mutate(P variables, [MutateOptions<T>? options]) {
    _mutateOptions = options;

    _currentMutation?.removeObserver(this);

    _currentMutation = _client.mutationCache.build<T, P>(_client, this.options);
    _currentMutation!.addObserver(this);

    return _currentMutation!.execute(variables);
  }

  void _updateResult() {
    final state = _currentMutation?.state ??
        MutationState<T>(null, MutationStatus.idle, null);

    _currentResult = MutationObserverResult<T, P>(
      data: state.data,
      status: state.status,
      error: state.error,
      failureCount: state.failureCount,
      failureReason: state.failureReason,
      isPending: state.isPending,
      isSuccess: state.isSuccess,
      isError: state.isError,
      isIdle: state.isIdle,
      mutate: mutate,
      reset: reset,
      variables: null,
      context: null,
    );
  }

  void _notify([MutationAction<T>? action]) {
    // First trigger mutate callbacks if present
    if (_mutateOptions != null && hasListeners()) {
      final onSuccess = _mutateOptions!.onSuccess;
      final onError = _mutateOptions!.onError;
      final onSettled = _mutateOptions!.onSettled;

      if (action != null && action.type == MutationActionType.success) {
        onSuccess?.call(action.data);
        onSettled?.call(action.data, null);
      } else if (action != null && action.type == MutationActionType.error) {
        onError?.call(action.error);
        onSettled?.call(null, action.error);
      }
    }

    // Then notify registered listeners
    notifyAll((listener) {
      try {
        final typed = listener as MutationObserverListener<T, P>;
        typed(_currentResult!);
      } catch (_) {
        // ignore
      }
    });
  }
}
