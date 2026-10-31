import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

import 'test_utils.dart';

/// Builds [child] into a fresh `OverlayEntry`, i.e. outside the provider's
/// subtree — the situation a dragged `ReorderableListView` item is in.
class _InOverlay extends StatelessWidget {
  final Widget Function(BuildContext outerContext) builder;

  const _InOverlay({required this.builder});

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(builder: (_) => builder(context)),
      ],
    );
  }
}

void main() {
  late QueryClient queryClient;

  setUp(() => queryClient = testQueryClient());

  testWidgets(
      'QueryClientProvider.portal re-exposes the client to that overlay',
      (tester) async {
    QueryClient? seen;

    await tester.pumpWidget(QueryClientProvider(
      client: queryClient,
      child: MaterialApp(
        home: _InOverlay(
          builder: (outerContext) => QueryClientProvider.portal(
            outerContext,
            child: HookBuilder(builder: (context) {
              seen = useQueryClient();
              return const SizedBox.shrink();
            }),
          ),
        ),
      ),
    ));

    expect(seen, same(queryClient));
  });

  testWidgets('portal does not mount the client a second time', (tester) async {
    // A duplicated mount would double every focus/online subscription, so the
    // first unmount would stop refetching for the whole app.
    final focusNotifications = <bool>[];
    final unsubscribe = focusManager.subscribe(focusNotifications.add);
    addTearDown(unsubscribe);

    await tester.pumpWidget(QueryClientProvider(
      client: queryClient,
      child: MaterialApp(
        home: _InOverlay(
          builder: (outerContext) => QueryClientProvider.portal(
            outerContext,
            child: HookBuilder(builder: (context) {
              useQueryClient();
              return const SizedBox.shrink();
            }),
          ),
        ),
      ),
    ));

    final key = queryKey();
    var calls = 0;
    final observer = QueryObserver<String, Object?, String>(
      queryClient,
      QueryOptions<String>(
        queryKey: key,
        queryFn: () async {
          calls++;
          return 'ok';
        },
        refetchOnWindowFocus: true,
      ),
    );
    addTearDown(observer.destroy);
    addTearDown(() => observer.subscribe((_) {})());

    final unsub = observer.subscribe((_) {});
    await tester.pump(const Duration(milliseconds: 10));
    calls = 0;

    focusManager.setFocused(false);
    focusManager.setFocused(true);
    await tester.pump(const Duration(milliseconds: 10));
    unsub();

    expect(calls, lessThanOrEqualTo(1),
        reason: 'a doubled mount would refetch twice for a single focus event');
  });
}
