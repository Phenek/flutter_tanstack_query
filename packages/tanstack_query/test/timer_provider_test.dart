import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

import 'test_utils.dart';

/// Records every timer the library asks for, and lets the test fire them.
class RecordingTimeoutProvider implements TimeoutProvider {
  final List<int> timeouts = <int>[];
  final List<int> intervals = <int>[];
  final List<void Function()> _pending = <void Function()>[];

  /// Runs every callback scheduled so far, whatever its delay.
  void fireAll() {
    final callbacks = List<void Function()>.from(_pending);
    _pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  /// The real clock never drives these timers — the test fires the callbacks
  /// itself — and a live timer would trip the binding's "timer still pending"
  /// invariant, so the handle is cancelled before it is handed out.
  Timer _inertHandle() => Timer(Duration.zero, () {})..cancel();

  @override
  Timer setTimeout(TimeoutCallback callback, int delay) {
    timeouts.add(delay);
    _pending.add(callback);
    return _inertHandle();
  }

  @override
  Timer setInterval(TimeoutCallback callback, int delay) {
    intervals.add(delay);
    _pending.add(callback);
    return _inertHandle();
  }

  @override
  void clearTimeout(Timer? timeoutId) => timeoutId?.cancel();

  @override
  void clearInterval(Timer? intervalId) => intervalId?.cancel();
}

void main() {
  late RecordingTimeoutProvider provider;

  setUp(() {
    provider = RecordingTimeoutProvider();
    timeoutManager.setTimeoutProvider(provider);
  });

  tearDown(timeoutManager.reset);

  testWidgets('garbage collection is scheduled through the provider', (tester) async {
    // Routing GC through the manager is what lets a test drive the clock instead
    // of waiting out a real 5-minute timer.
    final client = testQueryClient(queries: const QueryDefaultOptions(gcTime: 1000));
    final key = queryKey();

    await pumpHook(
      tester,
      () => useQuery<String>(queryKey: key, queryFn: () async => 'ok', gcTime: 1000),
      client: client,
    );
    await tester.pumpAndSettle();

    final cacheKey = queryKeyToCacheKey(key);
    expect(client.queryCache.containsKey(cacheKey), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(provider.timeouts, contains(1000),
        reason: 'unmounting schedules the eviction with the configured gcTime');
    expect(client.queryCache.containsKey(cacheKey), isTrue,
        reason: 'nothing is evicted until the timer actually fires');

    provider.fireAll();
    expect(client.queryCache.containsKey(cacheKey), isFalse);
  });

  testWidgets('retry delays are scheduled through the provider', (tester) async {
    final client = testQueryClient();
    final key = queryKey();
    var calls = 0;

    await pumpHook(
      tester,
      () => useQuery<String>(
        queryKey: key,
        queryFn: () async {
          calls++;
          throw Exception('boom');
        },
        retry: 1,
        retryDelay: 3000,
      ),
      client: client,
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(provider.timeouts, contains(3000),
        reason: 'the retry waits on the manager, not on a raw Timer');

    provider.fireAll();
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
