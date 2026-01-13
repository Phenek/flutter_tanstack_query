import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';
// Avoid pulling the real package dependency in tests; use a local enum to simulate connectivity events.

enum _InternetStatus { connected }

void main() {
  late QueryClient queryClient;

  setUp(() {
    queryClient = QueryClient(
        defaultOptions:
            const DefaultOptions(queries: QueryDefaultOptions(gcTime: 0)));
    queryClient.queryCache.clear();
    focusManager.setFocused(false);
    onlineManager.setOnline(false);
  });

  testWidgets('connectivity mapping sets onlineManager and triggers refetch',
      (WidgetTester tester) async {
    final key = ['mapping-reconnect'];
    final cacheKey = queryKeyToCacheKey(key);

    // ensure a stale cache entry is present
    queryClient.queryCache[cacheKey] = QueryCacheEntry(
        QueryResult<String>(cacheKey, QueryStatus.success, 'old', null),
        DateTime.now().subtract(const Duration(minutes: 5)));

    var calls = 0;
    final holder = ValueNotifier<QueryResult<String>?>(null);

    // create a controller to simulate connectivity changes
    final controller = StreamController<_InternetStatus>();

    // wiring code like in example: listen and map to onlineManager
    controller.stream.listen((status) {
      onlineManager.setOnline(status == _InternetStatus.connected);
    });

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final q = useQuery<String>(
              queryKey: key,
              queryFn: () async {
                calls++;
                await Future.delayed(const Duration(milliseconds: 1));
                return 'fresh';
              },
              refetchOnReconnect: true,
              refetchOnMount: false,
              staleTime: 0,
            );

            holder.value = q;
            return Container();
          }),
        )));

    // initial mount should not have called the query
    await tester.pump();
    expect(calls, equals(0));

    // simulate reconnect
    controller.add(_InternetStatus.connected);

    await tester.pump();
    await tester.pumpAndSettle();

    expect(calls, greaterThanOrEqualTo(1));
    expect(holder.value!.data, equals('fresh'));

    await controller.close();
  });

  testWidgets('app lifecycle callbacks set focusManager and trigger refetch',
      (WidgetTester tester) async {
    final key = ['mapping-focus'];
    final cacheKey = queryKeyToCacheKey(key);

    // put stale entry
    queryClient.queryCache[cacheKey] = QueryCacheEntry(
        QueryResult<String>(cacheKey, QueryStatus.success, 'old', null),
        DateTime.now().subtract(const Duration(minutes: 5)));

    var calls = 0;
    final holder = ValueNotifier<QueryResult<String>?>(null);

    // wiring functions like AppLifecycleListener callbacks
    void onResume() => focusManager.setFocused(true);

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final q = useQuery<String>(
              queryKey: key,
              queryFn: () async {
                calls++;
                await Future.delayed(const Duration(milliseconds: 1));
                return 'fresh';
              },
              refetchOnWindowFocus: true,
              refetchOnMount: false,
              staleTime: 0,
            );

            holder.value = q;
            return Container();
          }),
        )));

    // initial mount should not call refetch
    await tester.pump();
    expect(calls, equals(0));

    // simulate resume (focus)
    onResume();

    await tester.pump();
    await tester.pumpAndSettle();

    expect(calls, greaterThanOrEqualTo(1));
    expect(holder.value!.data, equals('fresh'));
  });
}
