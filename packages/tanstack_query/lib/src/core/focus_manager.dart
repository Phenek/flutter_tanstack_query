import 'subscribable.dart';

typedef FocusListener = void Function(bool focused);

/// FocusManager mirrors the JS `focusManager` behavior: it is subscribable and
/// allows registering a platform-specific event listener which calls
/// `setFocused` to notify subscribers of focus changes.
class FocusManager extends Subscribable<FocusListener> {
  bool? _focused;
  void Function()? _cleanup;

  /// Default no-op setup which callers may override via `setEventListener`.
  dynamic Function(void Function([bool? focused]) setFocused)? _setup;

  FocusManager();

  @override
  void onSubscribe() {
    if (_cleanup == null && _setup != null) {
      setEventListener(_setup!);
    }
  }

  @override
  void onUnsubscribe() {
    if (!hasListeners()) {
      try {
        _cleanup?.call();
      } catch (_) {}
      _cleanup = null;
    }
  }

  /// Register a platform-specific setup function. The [setup] receives a
  /// `setFocused` callback which may be called with a boolean or without
  /// arguments to indicate a generic focus event.
  void setEventListener(
      dynamic Function(void Function([bool? focused]) setFocused) setup) {
    _setup = setup;
    try {
      _cleanup?.call();
    } catch (_) {}
    // If the setup returns a cleanup function, store it.
    try {
      final cleanup = setup(([bool? focused]) {
        if (focused is bool) {
          setFocused(focused);
        } else {
          onFocus();
        }
      });
      if (cleanup is void Function()) {
        _cleanup = cleanup;
      }
    } catch (_) {
      _cleanup = null;
    }
  }

  void setFocused(bool? focused) {
    final changed = _focused != focused;
    if (changed) {
      _focused = focused;
      onFocus();
    }
  }

  void onFocus() {
    final isFocused = isFocusedState();
    for (var l in List<FocusListener>.from(listeners)) {
      try {
        l(isFocused);
      } catch (_) {}
    }
  }

  bool isFocusedState() {
    if (_focused != null) return _focused!;
    // Fallback to assuming focused in non-web environments.
    return true;
  }

  bool isFocused() => isFocusedState();
}

final focusManager = FocusManager();
