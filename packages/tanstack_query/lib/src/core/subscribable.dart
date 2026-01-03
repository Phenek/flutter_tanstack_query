import 'package:meta/meta.dart';

/// A reusable subscriber container similar to the JS `Subscribable` helper.
///
/// TListener is expected to be a function type (e.g. `void Function(Event)`).
class Subscribable<TListener extends Function> {
  final Set<TListener> _listeners = <TListener>{};

  Subscribable();

  /// Subscribe with [listener]. Returns an unsubscribe function.
  void Function() subscribe(TListener listener) {
    _listeners.add(listener);
    onSubscribe();

    return () {
      _listeners.remove(listener);
      onUnsubscribe();
    };
  }

  /// Returns true when there is at least one listener.
  bool hasListeners() => _listeners.isNotEmpty;

  /// Invoked when the first subscription is added. Subclasses may override.
  @protected
  void onSubscribe() {}

  /// Invoked when a subscription is removed. Subclasses may override.
  @protected
  void onUnsubscribe() {}

  /// Iterate over a safe copy and invoke [fn] for every listener.
  void notifyAll(void Function(TListener) fn) {
    final listeners = List<TListener>.from(_listeners);
    // Debug: show notify count during tests (disabled in production)
    for (var l in listeners) {
      try {
        fn(l);
      } catch (e, _) {
        // Swallow errors from listeners to avoid disrupting other listeners.
      }
    }
  }

  /// Expose a read-only view of listeners when needed.
  Iterable<TListener> get listeners => _listeners;
}
