import 'subscribable.dart';

/// Configuration callbacks for mutation lifecycle events such as
/// `onMutate`, `onSuccess`, and `onError`.
class MutationCacheConfig {
  /// Called when a mutation fails with an error.
  final dynamic Function(dynamic error)? onError;

  /// Called when a mutation succeeds with the returned data.
  final dynamic Function(dynamic data)? onSuccess;

    /// Called when a query settles (either success or error).
  final void Function(dynamic data, dynamic error)? onSettled;

  /// Called just before a mutation is executed (useful for optimistic updates).
  final dynamic Function()? onMutate;

  MutationCacheConfig({this.onError, this.onSuccess, this.onMutate, this.onSettled});
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
    _notifySubscribers(MutationCacheNotifyEvent(NotifyEventType.added, mutation));
  }

  /// Remove a mutation from the cache and notify subscribers.
  void remove(dynamic mutation) {
    _mutations.remove(mutation);
    _notifySubscribers(MutationCacheNotifyEvent(NotifyEventType.removed, mutation));
  }


  void _notifySubscribers(MutationCacheNotifyEvent event) {
    // Delegate to Subscribable to iterate and safely call subscribers.
    notifyAll((s) => s(event));
  }

  /// Clears the mutation cache entirely and notifies subscribers.
  void clear() {
    _mutations.clear();
    _notifySubscribers(MutationCacheNotifyEvent(NotifyEventType.removed, null));
  }
}