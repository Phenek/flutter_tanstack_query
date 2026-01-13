import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

void main() {
  testWidgets('QueryClientProvider mounts and unmounts the client',
      (WidgetTester tester) async {
    final initialFocusHas = focusManager.hasListeners();
    final initialOnlineHas = onlineManager.hasListeners();

    final client = QueryClient(
        defaultOptions:
            const DefaultOptions(queries: QueryDefaultOptions(gcTime: 0)));

    // Mount the provider
    await tester.pumpWidget(QueryClientProvider(
      client: client,
      child: const MaterialApp(home: SizedBox()),
    ));

    await tester.pump();

    // After mounting, the managers should have listeners
    expect(focusManager.hasListeners(), isTrue);
    expect(onlineManager.hasListeners(), isTrue);

    // Now unmount the provider
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // After unmount, manager listener presence should be restored to initial
    expect(focusManager.hasListeners(), equals(initialFocusHas));
    expect(onlineManager.hasListeners(), equals(initialOnlineHas));
  });
}
