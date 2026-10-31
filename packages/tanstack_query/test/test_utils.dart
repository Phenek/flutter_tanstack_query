/// Shared test helpers, mirroring `@tanstack/query-test-utils` on the JS side.
///
/// The JS test suite gives every test a unique query key and a single scaffold so
/// no cache leaks between tests. Before this file each test rebuilt its own
/// `QueryClient`, its own `QueryClientProvider > MaterialApp > HookBuilder` tree
/// and its own `ValueNotifier` to smuggle the hook result out of the widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

int _keyCounter = 0;

/// A key no other test has used, so a test can never read another's cache entry.
/// Port of `queryKey()` in `@tanstack/query-test-utils`.
List<Object> queryKey() => ['query_${_keyCounter++}'];

/// Resolves after [ms] milliseconds. Port of `sleep(ms)`.
Future<void> sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// A [QueryClient] configured for tests: GC disabled by default, so no test
/// leaves a pending timer behind unless it asks for one with `gcTime`.
QueryClient testQueryClient({
  QueryDefaultOptions queries = const QueryDefaultOptions(gcTime: -1),
  MutationDefaultOptions mutations = const MutationDefaultOptions(gcTime: -1),
  QueryCache? queryCache,
  MutationCache? mutationCache,
}) {
  final client = QueryClient(
    defaultOptions: DefaultOptions(queries: queries, mutations: mutations),
    queryCache: queryCache,
    mutationCache: mutationCache,
  );
  client.queryCache.clear();
  return client;
}

/// Every value a hook returned, in order, so a test can assert both the current
/// value and **how many times** the widget rebuilt.
class HookProbe<T> {
  final List<T> values = <T>[];

  /// The latest value the hook returned.
  T get value => values.last;

  /// How many times the builder ran. The baseline is 1 (the initial build):
  /// a notification that changes nothing should not move this number.
  int get rebuilds => values.length;

  /// Forget the history, keeping the current value as the new baseline.
  void reset() {
    final last = values.isEmpty ? null : values.last;
    values.clear();
    if (last != null) values.add(last);
  }

  @override
  String toString() =>
      'HookProbe(rebuilds: $rebuilds, value: ${values.isEmpty ? null : value})';
}

/// Mounts [hook] inside the standard provider scaffold and returns a probe on
/// its successive return values.
///
/// [wrap] inserts widgets between the provider and the hook (an `Overlay`, a
/// second subtree reading the same key, ...).
Future<HookProbe<T>> pumpHook<T>(
  WidgetTester tester,
  T Function() hook, {
  required QueryClient client,
  Widget Function(Widget child)? wrap,
}) async {
  final probe = HookProbe<T>();

  final hookWidget = HookBuilder(builder: (context) {
    probe.values.add(hook());
    return const SizedBox.shrink();
  });

  await tester.pumpWidget(QueryClientProvider(
    client: client,
    child: MaterialApp(home: wrap == null ? hookWidget : wrap(hookWidget)),
  ));

  return probe;
}

/// The cached [QueryResult] for [key], or `null` when nothing is cached.
QueryResult<T>? cachedResult<T>(QueryClient client, List<Object> key) {
  final entry = client.queryCache[queryKeyToCacheKey(key)];
  final result = entry?.result;
  return result is QueryResult<T> ? result : null;
}
