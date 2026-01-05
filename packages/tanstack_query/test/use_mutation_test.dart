import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

void main() {
  late QueryClient client;

  setUp(() {
    // Ensure a fresh QueryClient instance between tests
    // Disable default GC in tests to avoid scheduling timers unless a test
    // explicitly sets `gcTime` on the query options.
    client = QueryClient(defaultOptions: const DefaultOptions(queries: QueryDefaultOptions(gcTime: 0)));
    client.mutationCache.clear();
  });

// (setUp is declared above)
  testWidgets('should mutate and succeed when mutate is called', (WidgetTester tester) async {
    String? successData;
    final holder = ValueNotifier<MutationResult<String, String>?>(null);

    await tester.pumpWidget(QueryClientProvider(
        client: client,
        child: MaterialApp(
          home: HookBuilder(
            builder: (context) {
              final result = useMutation<String, String>(
                mutationFn: (params) async {
                  // simulate async operation
                  await Future.delayed(Duration(milliseconds: 10));
                  return 'ok';
                },
                onSuccess: (data) => successData = data,
              );

              holder.value = result;
              return Container();
            },
          ),
        )));
    // initial state is idle
    expect(holder.value!.status, equals(MutationStatus.idle));

    // start mutation
    holder.value!.mutate('p');
    await tester.pump(); // start async

    // should be pending while in-flight
    expect(holder.value!.status, equals(MutationStatus.pending));

    // finish the async mutation
    await tester.pumpAndSettle();

    // should end as success and data should be available via the result and callback
    expect(holder.value!.status, equals(MutationStatus.success));
    expect(holder.value!.data, equals('ok'));
    expect(successData, equals('ok'));
  });

  testWidgets('should mutate and fail when mutate is called', (WidgetTester tester) async {
    Object? errorObj;
    final holder = ValueNotifier<MutationResult<String, String>?>(null);

    await tester.pumpWidget(QueryClientProvider(
        client: client,
        child: MaterialApp(
          home: HookBuilder(
            builder: (context) {
              final result = useMutation<String, String>(
                mutationFn: (params) async {
                  // simulate async error
                  await Future.delayed(Duration(milliseconds: 10));
                  throw Exception('boom');
                },
                onError: (e) => errorObj = e,
              );

              holder.value = result;
              return Container();
            },
          ),
        )));
    // initial state is idle
    expect(holder.value!.status, equals(MutationStatus.idle));

    holder.value!.mutate('p');
    await tester.pump(); // start async

    // should be pending while in-flight
    expect(holder.value!.status, equals(MutationStatus.pending));

    // finish the async mutation which should throw
    await tester.pumpAndSettle();

    // should end as error; result should include the error
    expect(holder.value!.status, equals(MutationStatus.error));
    expect(holder.value!.error, isNotNull);
    expect(holder.value!.error.toString(), contains('boom'));
    expect(errorObj, isNotNull);
  });

  testWidgets('should garbage collect mutation after gcTime when unmounted', (WidgetTester tester) async {
    final holder = ValueNotifier<MutationResult<String, String>?>(null);

    await tester.pumpWidget(QueryClientProvider(
        client: client,
        child: MaterialApp(
          home: HookBuilder(
            builder: (context) {
              final result = useMutation<String, String>(
                mutationFn: (params) async {
                  await Future.delayed(Duration(milliseconds: 5));
                  return 'ok';
                },
                gcTime: 50,
              );

              holder.value = result;
              return Container();
            },
          ),
        )));

    // trigger a mutation which adds it to the cache
    holder.value!.mutate('p');
    await tester.pump();
    await tester.pumpAndSettle();

    // ensure cache contains a mutation
    expect(client.mutationCache.getAll().isNotEmpty, isTrue);

    // unmount the hook
    await tester.pumpWidget(Container());

    // wait for GC to run and remove the mutation
    var tries = 0;
    while (client.mutationCache.getAll().isNotEmpty && tries < 50) {
      await tester.pump(Duration(milliseconds: 20));
      tries++;
    }

    expect(client.mutationCache.getAll().isEmpty, isTrue);
  });

  testWidgets('should retry failed mutation according to retry settings', (WidgetTester tester) async {
    final holder = ValueNotifier<MutationResult<String, int>?>(null);
    var attempts = 0;

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(builder: (context) {
        final mutation = useMutation<String, int>(
          mutationFn: (i) async {
            attempts++;
            await Future.delayed(Duration(milliseconds: 5));
            if (attempts < 3) throw Exception('try-$attempts');
            return 'finally';
          },
          retry: 3,
          retryDelay: 5,
        );

        holder.value = mutation;

        return Container();
      }),
    )));

    await tester.runAsync(() async {
      await holder.value!.mutateAsync(1);
    });

    expect(attempts, greaterThanOrEqualTo(3));
    expect(holder.value!.status, equals(MutationStatus.success));
    expect(holder.value!.data, equals('finally'));
  });

  testWidgets('should expose failureCount and failureReason on final error', (WidgetTester tester) async {
    final holder = ValueNotifier<MutationResult<String, int>?>(null);

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(builder: (context) {
        final mutation = useMutation<String, int>(
          mutationFn: (i) async {
            await Future.delayed(Duration(milliseconds: 5));
            throw Exception('boom');
          },
          retry: 2,
          retryDelay: 5,
        );

        holder.value = mutation;

        return Container();
      }),
    )));

    await tester.runAsync(() async {
      try {
        await holder.value!.mutateAsync(1);
      } catch (_) {}
    });

    expect(holder.value!.status, equals(MutationStatus.error));
    expect(holder.value!.failureCount, greaterThanOrEqualTo(1));
    expect(holder.value!.failureReason, isNotNull);
  });
}

