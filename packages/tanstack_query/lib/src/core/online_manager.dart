import 'subscribable.dart';

typedef OnlineListener = void Function(bool online);

/// OnlineManager mirrors the JS `onlineManager` behavior: subscribable with
/// custom event listener and `setOnline` / `isOnline` helpers.
class OnlineManager extends Subscribable<OnlineListener> {
  bool _online = true;
  void Function()? _cleanup;
  void Function(void Function(bool))? _setup;

  OnlineManager();

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

  void setEventListener(dynamic Function(void Function(bool) setOnline) setup) {
    _setup = setup;
    try {
      _cleanup?.call();
    } catch (_) {}
    try {
      final cleanup = setup(setOnline);
      if (cleanup is void Function()) _cleanup = cleanup;
    } catch (_) {
      _cleanup = null;
    }
  }

  void setOnline(bool online) {
    final changed = _online != online;
    if (changed) {
      _online = online;
      for (var l in List<OnlineListener>.from(listeners)) {
        try {
          l(online);
        } catch (_) {}
      }
    }
  }

  bool isOnline() => _online;
}

final onlineManager = OnlineManager();
