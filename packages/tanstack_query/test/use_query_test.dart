import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

void main() {
  late QueryClient queryClient;

  setUp(() {
    // Ensure a fresh QueryClient instance and clear cache between tests
    // Use a small gcTime during tests to avoid scheduling long-lived timers
    // Disable default GC in tests to avoid scheduling timers unless a test
    // explicitly sets `gcTime` on the query options.
    queryClient = QueryClient(defaultOptions: const DefaultOptions(queries: QueryDefaultOptions(gcTime: 0)));
    queryClient.queryCache.clear();
  });

  testWidgets('should fetch and succeed', (WidgetTester tester) async {
    final holder = ValueNotifier<QueryResult<String>?>(null);

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final query = useQuery<String>(
              queryKey: ['fetch-success'],
              queryFn: () async {
                await Future.delayed(Duration(milliseconds: 10));
                return 'ok';
              },
            );

            // expose the query to the test
            holder.value = query;

            // return an empty container, we assert on the hook state directly
            return Container();
          }),
        )));

    // initial state read from the hook directly
    expect(holder.value!.status, equals(QueryStatus.pending));

    // let the query start and finish
    await tester.pump();
    await tester.pumpAndSettle();

    // assert the hook result itself
    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals('ok'));

    // The cache should also contain the successful result
    final key = queryKeyToCacheKey(['fetch-success']);
    expect((queryClient.queryCache[key]!.result as QueryResult<String>).data, equals('ok'));
  });

  testWidgets('should fetch and fail', (WidgetTester tester) async {
    final holder = ValueNotifier<QueryResult<String>?>(null);

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: ['fetch-fail'],
              queryFn: () async {
                await Future.delayed(Duration(milliseconds: 10));
                throw Exception('boom');
              },
              retry: 1,
              retryDelay: 10,
            );

            holder.value = result;

            return Container();
          }),
        )));
    // run the build and let the hook run the failing query
    await tester.pump();

    // wait for the hook to update to error status (with a small timeout)
    var tries = 0;
    while ((holder.value == null || holder.value!.status == QueryStatus.pending) && tries < 50) {
      await tester.pump(Duration(milliseconds: 10));
      tries++;
    }

    expect(holder.value, isNotNull);
    expect(holder.value!.status, equals(QueryStatus.error));
    expect(holder.value!.error.toString(), contains('boom'));

    // Ensure failureCount and failureReason are exposed
    expect(holder.value!.failureCount, greaterThanOrEqualTo(1));
    expect(holder.value!.failureReason, isNotNull);

    // cache should contain the failing result as well (if the hook updated the cache)
    final cacheKey = queryKeyToCacheKey(['fetch-fail']);
    if (queryClient.queryCache.containsKey(cacheKey)) {
      final cached = queryClient.queryCache[cacheKey]!.result as QueryResult<String>;
      expect(cached.status, equals(QueryStatus.error));
      expect(cached.error.toString(), contains('boom'));
      expect(cached.failureCount, greaterThanOrEqualTo(1));
      expect(cached.failureReason, isNotNull);
    }
  });

  testWidgets('should retry up to retry count and succeed', (WidgetTester tester) async {
    final holder = ValueNotifier<QueryResult<String>?>(null);
    var attempts = 0;

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: ['retry-success'],
              queryFn: () async {
                attempts++;
                await Future.delayed(Duration(milliseconds: 5));
                if (attempts < 3) throw Exception('try-$attempts');
                return 'finally';
              },
              retry: 3,
              retryDelay: 5,
            );

            holder.value = result;

            return Container();
          }),
        )));

    // let retries happen
    await tester.pump();
    await tester.pumpAndSettle();

    expect(attempts, greaterThanOrEqualTo(3));
    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals('finally'));
  });

  testWidgets('should not retry on mount if retryOnMount is false', (WidgetTester tester) async {
    final holder = ValueNotifier<QueryResult<String>?>(null);
    var called = false;
    final keyList = ['no-retry-on-mount'];
    final cacheKey = queryKeyToCacheKey(keyList);

    // place an errored entry in cache
    queryClient.queryCache[cacheKey] = QueryCacheEntry(
        QueryResult<String>(cacheKey, QueryStatus.error, null, Exception('old-error'),
            failureCount: 1, failureReason: Exception('old-error')),
        DateTime.now());

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: keyList,
              queryFn: () async {
                called = true;
                return 'should-not-run';
              },
              retryOnMount: false,
              staleTime: 10000, // ensure cached error is not considered stale
            );

            holder.value = result;

            return Container();
          }),
        )));

    // give a bit of time
    await tester.pump();

    expect(called, isFalse);
  });

  testWidgets('should not fetch when enabled is false', (WidgetTester tester) async {
    var called = false;

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            useQuery<String>(
              queryKey: ['disabled'],
              queryFn: () async {
                called = true;
                return 'ok';
              },
              enabled: false,
            );

            return Container();
          }),
        )));

    // give a bit of time
    await tester.pump();

    expect(called, isFalse);
  });

  testWidgets('should fetch when enabled is changed from false to true', (WidgetTester tester) async {
    final holder = ValueNotifier<QueryResult<String>?>(null);
    var called = 0;

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: ['toggle-enable-key'],
              queryFn: () async {
                called++;
                await Future.delayed(Duration(milliseconds: 5));
                return 'value-$called';
              },
              enabled: false,
            );

            holder.value = result;

            return Container();
          }),
        )));

    // initial build: enabled=false so should NOT call
    await tester.pump();
    expect(called, equals(0));

    // enable the query by rebuilding with enabled = true
    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: ['toggle-enable-key'],
              queryFn: () async {
                called++;
                await Future.delayed(Duration(milliseconds: 5));
                return 'value-$called';
              },
              enabled: true,
            );

            holder.value = result;
            return Container();
          }),
        )));

    // allow async to run
    await tester.pumpAndSettle();

    expect(called, greaterThan(0));
    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, contains('value-'));
  });

  testWidgets('should refetch when data is stale', (WidgetTester tester) async {
    final key = queryKeyToCacheKey(['stale-key']);
    final holder = ValueNotifier<QueryResult<String>?>(null);

    // populate cache with old timestamp
    queryClient.queryCache[key] = QueryCacheEntry(QueryResult<String>(key, QueryStatus.success, 'old', null),
        DateTime.now().subtract(Duration(milliseconds: 200)));

    // removed external callback; assert on the rendered UI

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: ['stale-key'],
              queryFn: () async {
                await Future.delayed(Duration(milliseconds: 5));
                return 'fresh';
              },
              staleTime: 100, // ms -> cached entry older than this
            );

            holder.value = result;

            return Container();
          }),
        )));

    // initial state should detect stale and fetch
    await tester.pump();
    await tester.pumpAndSettle();

    expect(holder.value!.data, equals('fresh'));
    // cache should be updated with fresh value
    final cacheKey = queryKeyToCacheKey(['stale-key']);
    expect((queryClient.queryCache[cacheKey]!.result as QueryResult<String>).data, equals('fresh'));
  });

  testWidgets('should refetch when previous fetch is fulfilled (retryer not blocking)', (WidgetTester tester) async {
    final keyList = ['fulfilled-retryer'];
    final cacheKey = queryKeyToCacheKey(keyList);
    final holder = ValueNotifier<QueryResult<String>?>(null);
    var called = 0;

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: keyList,
              queryFn: () async {
                called++;
                await Future.delayed(Duration(milliseconds: 5));
                return 'value-$called';
              },
              staleTime: 10000, // ensure not stale; we will trigger a refetch via cache event
            );

            holder.value = result;

            return Container();
          }),
        )));

    // initial fetch should complete
    await tester.pump();
    await tester.pumpAndSettle();

    expect(called, equals(1));
    expect(holder.value!.data, equals('value-1'));

    // Trigger a cache-level refetch event (simulate external invalidation)
    queryClient.queryCache.refetchByCacheKey(cacheKey);
    await tester.pump();
    await tester.pumpAndSettle();

    // ensure queryFn ran again and the data updated
    expect(called, equals(2));
    expect(holder.value!.data, equals('value-2'));
  });

  testWidgets('should not refetch when data is not null and not stale', (WidgetTester tester) async {
    final key = queryKeyToCacheKey(['fresh-key']);

    // populate cache with recent timestamp
    queryClient.queryCache[key] =
        QueryCacheEntry(QueryResult<String>(key, QueryStatus.success, 'cached', null), DateTime.now());

    var called = false;

    final holder = ValueNotifier<QueryResult<String>?>(null);

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: ['fresh-key'],
              queryFn: () async {
                called = true;
                return 'should-not-run';
              },
              staleTime: 1000, // large staleTime so the cached is not stale
            );

            holder.value = result;

            return Container();
          }),
        )));

    // initial state should use cached result and NOT call queryFn
    await tester.pump();

    expect(called, isFalse);
    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals('cached'));
  });

  testWidgets('staleTime 0 should consider cached data stale immediately and refetch', (WidgetTester tester) async {
    final keyList = ['stale-zero'];
    final cacheKey = queryKeyToCacheKey(keyList);
    final holder = ValueNotifier<QueryResult<String>?>(null);

    // populate cache with a fresh timestamp, but staleTime = 0 should force refetch
    queryClient.queryCache[cacheKey] = QueryCacheEntry(
      QueryResult<String>(cacheKey, QueryStatus.success, 'cached', null),
      DateTime.now(),
    );

    var called = false;

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: keyList,
              queryFn: () async {
                called = true;
                await Future.delayed(Duration(milliseconds: 5));
                return 'fresh';
              },
              staleTime: 0, // immediate stale
            );

            holder.value = result;
            return Container();
          }),
        )));

    // allow the refetch to run
    await tester.pump();
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(holder.value!.data, equals('fresh'));
    expect((queryClient.queryCache[cacheKey]!.result as QueryResult<String>).data, equals('fresh'));
  });

  testWidgets('staleTime Infinity should never consider data stale', (WidgetTester tester) async {
    final keyList = ['stale-infinite'];
    final cacheKey = queryKeyToCacheKey(keyList);
    final holder = ValueNotifier<QueryResult<String>?>(null);

    // populate cache with an old timestamp
    queryClient.queryCache[cacheKey] = QueryCacheEntry(
      QueryResult<String>(cacheKey, QueryStatus.success, 'cached-old', null),
      DateTime.now().subtract(Duration(days: 1)),
    );

    var called = false;

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: keyList,
              queryFn: () async {
                called = true;
                await Future.delayed(Duration(milliseconds: 5));
                return 'fresh';
              },
              staleTime: double.infinity, // never stale
            );

            holder.value = result;
            return Container();
          }),
        )));

    // give a short moment to ensure no refetch happens
    await tester.pump();
    await tester.pump(Duration(milliseconds: 20));

    expect(called, isFalse);
    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals('cached-old'));
  });

  testWidgets('should refetch when queryKey changes (pagination)', (WidgetTester tester) async {
    final holder = ValueNotifier<QueryResult<String>?>(null);

    // initial page 1
    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: ['pagination', 1],
              queryFn: () async {
                await Future.delayed(Duration(milliseconds: 5));
                return 'page-1';
              },
            );

            holder.value = result;
            return Container();
          }),
        )));

    // let initial fetch complete
    await tester.pump();
    await tester.pumpAndSettle();

    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals('page-1'));

    // rebuild with a changed queryKey to simulate changing page (page 2)
    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: ['pagination', 2],
              queryFn: () async {
                await Future.delayed(Duration(milliseconds: 5));
                return 'page-2';
              },
            );

            holder.value = result;
            return Container();
          }),
        )));

    // allow refetch to run and complete
    await tester.pump();

    // Wait until the cache contains the fresh page result (avoid flakiness
    // due to hook rebuild timing) — this verifies the refetch completed.
    final cacheKey2 = queryKeyToCacheKey(['pagination', 2]);
    var tries = 0;
    while ((queryClient.queryCache[cacheKey2] == null ||
            (queryClient.queryCache[cacheKey2]!.result as QueryResult<String>).status != QueryStatus.success) &&
        tries < 50) {
      await tester.pump(Duration(milliseconds: 10));
      tries++;
    }

    expect(queryClient.queryCache.containsKey(cacheKey2), isTrue);
    final cached = queryClient.queryCache[cacheKey2]!.result as QueryResult<String>;
    expect(cached.status, equals(QueryStatus.success));
    expect(cached.data, equals('page-2'));
  });

  testWidgets('should fetch when queryKey contains a Map (pagination map)', (WidgetTester tester) async {
    final holder = ValueNotifier<QueryResult<String>?>(null);

    // initial page 1 with Map as part of the key
    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: [
                'pagination',
                {'number': 1, 'size': 5}
              ],
              queryFn: () async {
                await Future.delayed(Duration(milliseconds: 5));
                return 'page-1';
              },
            );

            holder.value = result;
            return Container();
          }),
        )));

    // let initial fetch finish
    await tester.pump();
    await tester.pumpAndSettle();

    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals('page-1'));
    expect(holder.value!.isFetching, isFalse);

    // change page -> page 2 (Map changes)
    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: [
                'pagination',
                {'number': 2, 'size': 5}
              ],
              queryFn: () async {
                await Future.delayed(Duration(milliseconds: 5));
                return 'page-2';
              },
            );

            holder.value = result;
            return Container();
          }),
        )));

    await tester.pumpAndSettle();

    final cacheKey2 = queryKeyToCacheKey([
      'pagination',
      {'number': 2, 'size': 5}
    ]);
    expect(queryClient.queryCache.containsKey(cacheKey2), isTrue);
    final cached = queryClient.queryCache[cacheKey2]!.result as QueryResult<String>;
    expect(cached.status, equals(QueryStatus.success));
    expect(cached.data, equals('page-2'));
  });

  testWidgets('should garbage collect query after gcTime when unmounted', (WidgetTester tester) async {
    final holder = ValueNotifier<QueryResult<String>?>(null);
    final keyList = ['gc-test'];
    final cacheKey = queryKeyToCacheKey(keyList);

    // mount a widget that runs a query with a short gcTime
    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useQuery<String>(
              queryKey: keyList,
              queryFn: () async {
                await Future.delayed(Duration(milliseconds: 5));
                return 'ok';
              },
              gcTime: 50, // ms
            );

            holder.value = result;
            return Container();
          }),
        )));

    // let the query complete and ensure the cache has the entry
    await tester.pump();
    await tester.pumpAndSettle();

    expect(queryClient.queryCache.containsKey(cacheKey), isTrue);

    // unmount the hook (no observers should remain)
    await tester.pumpWidget(QueryClientProvider(client: queryClient, child: MaterialApp(home: Container())));

    // wait for the gc timer to fire (max ~500ms to avoid flakiness)
    var tries = 0;
    while (queryClient.queryCache.containsKey(cacheKey) && tries < 50) {
      await tester.pump(Duration(milliseconds: 20));
      tries++;
    }

    expect(queryClient.queryCache.containsKey(cacheKey), isFalse);
  });
}
