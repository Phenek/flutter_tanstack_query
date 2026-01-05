import 'dart:async';

/// Base class that provides garbage-collection helpers for cache-managed
/// objects such as `Query` and `Mutation`.
///
/// Subclasses must implement [optionalRemove] to perform the actual
/// removal from their owning cache when GC triggers.
abstract class Removable {
  /// The configured GC time in milliseconds. If null or <=0, GC is disabled.
  int? gcTime;

  Timer? _gcTimer;

  /// Destroy hooks and cancel timers.
  void destroy() {
    clearGcTimeout();
  }

  /// Schedule garbage collection using the current `gcTime` value.
  void scheduleGc() {
    clearGcTimeout();
    final gc = gcTime;
    if (gc == null || gc <= 0) return;

    _gcTimer = Timer(Duration(milliseconds: gc), () {
      try {
        optionalRemove();
      } catch (_) {}
    });
  }

  /// Update the configured GC time. The `defaultGcTime` should be provided by
  /// the caller (e.g., from client defaults). The stored `gcTime` is set to
  /// the maximum of the current value and the provided value.
  void updateGcTime(int? newGcTime, {required int defaultGcTime}) {
    final base = newGcTime ?? defaultGcTime;
    final current = gcTime ?? 0;
    gcTime = base > current ? base : current;
  }

  /// Cancel any pending GC timers.
  void clearGcTimeout() {
    _gcTimer?.cancel();
    _gcTimer = null;
  }

  /// Subclasses implement this to optionally remove themselves from the
  /// owning cache when GC fires (and there are no observers).
  void optionalRemove();
}
