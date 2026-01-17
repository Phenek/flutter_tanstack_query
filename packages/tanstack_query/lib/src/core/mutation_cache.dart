import 'subscribable.dart';
import 'mutation.dart';
import 'query_client.dart';

/// Configuration callbacks for mutation lifecycle events such as
/// `onMutate`, `onSuccess`, and `onError`.
class MutationCacheConfig {
  /// Called when a mutation fails with an error.
  ///
  /// Signature: `(dynamic error, [MutationFunctionContext? context])`.
  final void Function(dynamic error, [MutationFunctionContext? context])?
      onError;

  /// Called when a mutation succeeds with the returned data.
  ///
  /// Signature: `(dynamic data, [MutationFunctionContext? context])`.
  final void Function(dynamic data, [MutationFunctionContext? context])?
      onSuccess;

  /// Called when a query settles (either success or error).
  ///
  /// Signature: `(dynamic data, dynamic error, [MutationFunctionContext? context])`.
  final void Function(dynamic data, dynamic error,
      [MutationFunctionContext? context])? onSettled;

  /// Called just before a mutation is executed (useful for optimistic updates).
  ///
  /// Signature: `([MutationFunctionContext? context])`.
  final void Function([MutationFunctionContext? context])? onMutate;

  MutationCacheConfig(
      {this.onError, this.onSuccess, this.onMutate, this.onSettled});
}

/// Types of events emitted by the cache.
enum NotifyEventType {
  added,
  removed,
  updated,
}

/// Listener signature for cache-level notifications.
typedef MutationCacheListener = void Function(MutationCacheNotifyEvent event);

/// Notification event emitted by `MutationCache.subscribe`.
class MutationCacheNotifyEvent {
  final NotifyEventType type;
  final dynamic mutation;

  MutationCacheNotifyEvent(this.type, this.mutation);
}

/// Mutation cache that stores mutation instances and allows subscribing to
/// mutation lifecycle events. It mirrors the JS `MutationCache` API.
class MutationCache extends Subscribable<MutationCacheListener> {
  /// The configuration that contains callbacks invoked during mutation
  /// lifecycle events.
  final MutationCacheConfig config;

  final List<dynamic> _mutations = [];

  MutationCache({required this.config});

  /// Return all registered mutation instances.
  List<dynamic> getAll() => List.unmodifiable(_mutations);

  /// Add a mutation to the cache and notify subscribers.
  void add(dynamic mutation) {
    _mutations.add(mutation);
    _notifySubscribers(
        MutationCacheNotifyEvent(NotifyEventType.added, mutation));
  }

  /// Remove a mutation from the cache and notify subscribers.
  void remove(dynamic mutation) {
    // Cancel GC timers on the mutation if present
    try {
      if (mutation != null && mutation is Mutation) mutation.cancel();
    } catch (_) {}

    _mutations.remove(mutation);
    _notifySubscribers(
        MutationCacheNotifyEvent(NotifyEventType.removed, mutation));
  }

  /// Build a new [Mutation] and add it to the cache. The mutation will be
  /// owned by the cache and can notify observers.
  Mutation<T, P> build<T, P>(
      QueryClient client, MutationOptions<T, P> options) {
    final m = Mutation<T, P>(client, options);
    add(m);
    return m;
  }

  void _notifySubscribers(MutationCacheNotifyEvent event) {
    // Delegate to Subscribable to iterate and safely call subscribers.
    notifyAll((s) => s(event));
  }

  /// Clears the mutation cache entirely and notifies subscribers.
  void clear() {
    // Cancel any pending GC timers for stored mutations
    for (var m in _mutations) {
      try {
        if (m != null && m is Mutation) m.cancel();
      } catch (_) {}
    }

    _mutations.clear();
    _notifySubscribers(MutationCacheNotifyEvent(NotifyEventType.removed, null));
  }
}
