import 'dart:async';

/// A callback a timer fires.
typedef TimeoutCallback = void Function();

/// Backend for the library's timers.
///
/// Port of `TimeoutProvider` in `timeoutManager.ts`. Dart's [Timer] already
/// carries its own `cancel()`, so a `Timer` *is* the timer id — `clearTimeout`
/// and `clearInterval` are kept to mirror the JS surface and because a custom
/// provider may need to track what it handed out.
abstract class TimeoutProvider {
  /// Runs [callback] once after [delay] milliseconds.
  Timer setTimeout(TimeoutCallback callback, int delay);

  /// Cancels a timer returned by [setTimeout].
  void clearTimeout(Timer? timeoutId);

  /// Runs [callback] every [delay] milliseconds.
  Timer setInterval(TimeoutCallback callback, int delay);

  /// Cancels a timer returned by [setInterval].
  void clearInterval(Timer? intervalId);
}

/// Uses Dart's own [Timer].
///
/// The callbacks are wrapped rather than passed by reference so that replacing
/// the provider — or a test zone's clock — actually takes effect.
class DefaultTimeoutProvider implements TimeoutProvider {
  const DefaultTimeoutProvider();

  @override
  Timer setTimeout(TimeoutCallback callback, int delay) =>
      Timer(Duration(milliseconds: delay), () => callback());

  @override
  void clearTimeout(Timer? timeoutId) => timeoutId?.cancel();

  @override
  Timer setInterval(TimeoutCallback callback, int delay) =>
      Timer.periodic(Duration(milliseconds: delay), (_) => callback());

  @override
  void clearInterval(Timer? intervalId) => intervalId?.cancel();
}

/// The single seam through which the library creates timers.
///
/// Port of `TimeoutManager`. Everything time-based goes through it — garbage
/// collection, retry delays, and later `staleTime` and `refetchInterval` — so a
/// test can swap in a controllable clock instead of waiting in real time, and an
/// app with thousands of cache entries can coalesce timers.
class TimeoutManager implements TimeoutProvider {
  TimeoutProvider _provider = const DefaultTimeoutProvider();

  /// Replaces the backend.
  ///
  /// Timers already handed out by the previous provider keep their own
  /// `cancel()`, so unlike the JS version there is no risk of cancelling an
  /// unrelated timer after a switch.
  void setTimeoutProvider(TimeoutProvider provider) => _provider = provider;

  /// Restores [DefaultTimeoutProvider].
  void reset() => _provider = const DefaultTimeoutProvider();

  @override
  Timer setTimeout(TimeoutCallback callback, int delay) =>
      _provider.setTimeout(callback, delay);

  @override
  void clearTimeout(Timer? timeoutId) => _provider.clearTimeout(timeoutId);

  @override
  Timer setInterval(TimeoutCallback callback, int delay) =>
      _provider.setInterval(callback, delay);

  @override
  void clearInterval(Timer? intervalId) => _provider.clearInterval(intervalId);
}

/// The manager every library timer is created through.
final TimeoutManager timeoutManager = TimeoutManager();
