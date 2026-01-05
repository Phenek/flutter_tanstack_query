import 'dart:async';
import 'package:tanstack_query/tanstack_query.dart';
import 'removable.dart';

/// Action emitted by a [Mutation] to observers.
enum MutationActionType { pending, success, error }

class MutationAction<T> {
  final MutationActionType type;
  final T? data;
  final Object? error;

  MutationAction._(this.type, {this.data, this.error});

  factory MutationAction.pending() =>
      MutationAction._(MutationActionType.pending);
  factory MutationAction.success(T data) =>
      MutationAction._(MutationActionType.success, data: data);
  factory MutationAction.error(Object error) =>
      MutationAction._(MutationActionType.error, error: error);
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

  /// Retry configuration: can be `bool` (true = infinite), `int` (max attempts),
  /// or a function `(failureCount, error) => bool`.
  final dynamic retry;

  /// Delay between retries in ms or a function `(attempt, error) => int`.
  final dynamic retryDelay;

  /// Garbage collection time (milliseconds) after which unused mutations are removed.
  final int? gcTime;

  MutationOptions({
    required this.mutationFn,
    this.mutationKey,
    this.onMutate,
    this.onSuccess,
    this.onError,
    this.onSettled,
    this.retry,
    this.retryDelay,
    this.gcTime,
  });
}

/// A single mutation instance that holds its state and notifies observers on
/// lifecycle events.
class Mutation<T, P> extends Removable {
  final QueryClient client;
  MutationOptions<T, P> options;

  MutationState<T> state = MutationState<T>(null, MutationStatus.idle, null);
  final Set<dynamic> _observers = <dynamic>{};

  Mutation(this.client, this.options) {
    // Initialize gc timing and schedule initial GC
    updateGcTime(options.gcTime,
        defaultGcTime: client.defaultOptions.mutations.gcTime);
    scheduleGc();
  }

  void addObserver(dynamic observer) {
    _observers.add(observer);
    // Cancel GC when an observer attaches
    clearGcTimeout();
  }

  void removeObserver(dynamic observer) {
    _observers.remove(observer);
    if (_observers.isEmpty) {
      scheduleGc();
    }
  }

  void _notifyObservers(MutationAction<T> action) {
    for (var o in List.from(_observers)) {
      try {
        o.onMutationUpdate(action);
      } catch (e) {
        // ignore listener errors
      }
    }
  }

  @override
  void optionalRemove() {
    if (_observers.isEmpty) {
      if (state.status == MutationStatus.pending) {
        // If pending, reschedule GC for later
        scheduleGc();
        return;
      }
      client.mutationCache.remove(this);
    }
  }

  /// Cancel any pending GC timers
  void cancel() {
    clearGcTimeout();
  }

  /// Execute the mutation with [variables]. This updates internal state and
  /// calls cache-level lifecycle hooks from [QueryClient.mutationCache.config].
  Future<T> execute(P variables) async {
    // onMutate hook
    try {
      options.onMutate?.call();
    } catch (_) {}

    // Reset failure tracking when starting
    state = MutationState<T>(null, MutationStatus.pending, null,
        failureCount: 0, failureReason: null);
    _notifyObservers(MutationAction.pending());

    // Build retryer
    final retryValue = options.retry ?? client.defaultOptions.mutations.retry;
    final retryDelayValue =
        options.retryDelay ?? client.defaultOptions.mutations.retryDelay;

    // debug logs removed

    final retryer = Retryer<T>(
      fn: () async => options.mutationFn(variables),
      retry: retryValue,
      retryDelay: retryDelayValue,
      onFail: (failureCount, error) {
        // Update state while retrying so observers can read failureCount / reason
        state = MutationState<T>(null, MutationStatus.pending, null,
            failureCount: failureCount, failureReason: error);
        _notifyObservers(MutationAction.pending());
      },
    );

    try {
      final data = await retryer.start();

      state = MutationState<T>(data, MutationStatus.success, null,
          failureCount: 0, failureReason: null);
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
      // final failure
      final failureCount = retryer.failureCount;
      state = MutationState<T>(null, MutationStatus.error, e,
          failureCount: failureCount, failureReason: e);
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
    // Re-evaluate GC timing when options change
    updateGcTime(options.gcTime,
        defaultGcTime: client.defaultOptions.mutations.gcTime);
    scheduleGc();
  }
}
