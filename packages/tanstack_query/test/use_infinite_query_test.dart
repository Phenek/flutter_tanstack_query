import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

void main() {
  late QueryClient client;

  setUp(() {
    // Ensure a fresh QueryClient instance and clear cache between tests
    // Disable default GC in tests to avoid scheduling timers unless a test
    // explicitly sets `gcTime` on the query options.
    client = QueryClient(defaultOptions: const DefaultOptions(queries: QueryDefaultOptions(gcTime: 0)));
    client.queryCache.clear();
  });

  testWidgets('should fetch initial page and succeed',
      (WidgetTester tester) async {
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(
        builder: (context) {
          final result = useInfiniteQuery<int>(
            queryKey: ['infinite', 'init-success'],
            queryFn: (page) async {
              await Future.delayed(Duration(milliseconds: 10));
              return page;
            },
            initialPageParam: 1,
          );

          holder.value = result;
          return Container();
        },
      ),
    )));

    // initial state is pending
    expect(holder.value, isNotNull);
    expect(holder.value!.status, equals(QueryStatus.pending));

    // wait async fetch to complete
    await tester.pumpAndSettle();

    // should succeed and data contains the first page
    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals([1]));
    // verify the cache contains the initial page result
    final key = queryKeyToCacheKey(['infinite', 'init-success']);
    final cached = (client.queryCache[key]!.result as InfiniteQueryResult<int>);
    expect(cached.data, equals([1]));
  });

  testWidgets('should fetch next page when fetchNextPage is called',
      (WidgetTester tester) async {
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(
        builder: (context) {
          final result = useInfiniteQuery<int>(
            queryKey: ['infinite', 'next-page'],
            queryFn: (page) async {
              await Future.delayed(Duration(milliseconds: 10));
              return page;
            },
            initialPageParam: 1,
            getNextPageParam: (last) => last + 1,
          );

          holder.value = result;
          return Container();
        },
      ),
    )));

    // wait initial fetch
    await tester.pumpAndSettle();
    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals([1]));

    // request next page
    holder.value!.fetchNextPage?.call();
    await tester.pump(); // kick off fetch
    await tester.pumpAndSettle();

    // should have two pages now
    expect(holder.value!.data, equals([1, 2]));
  });

  testWidgets('should set error state when initial fetch fails',
      (WidgetTester tester) async {
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(
        builder: (context) {
          final result = useInfiniteQuery<int>(
            queryKey: ['infinite', 'init-error'],
            queryFn: (page) async {
              await Future.delayed(Duration(milliseconds: 10));
              throw Exception('boom');
            },
            initialPageParam: 1,
            retry: 0,
            retryDelay: 1,
          );

          holder.value = result;
          return Container();
        },
      ),
    )));

    // pending then settle to error
    expect(holder.value!.status,
        anyOf(equals(QueryStatus.pending), equals(QueryStatus.error)));
    await tester.pumpAndSettle();
    expect(holder.value!.status, equals(QueryStatus.error));
    // the hook reports the error in the cache
    final key = queryKeyToCacheKey(['infinite', 'init-error']);
    expect(
        (client.queryCache[key]!.result as InfiniteQueryResult<int>).error.toString(),
        contains('boom'));
  });

  testWidgets('should fetch and fail with retry configuration', (WidgetTester tester) async {
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(
        builder: (context) {
          final result = useInfiniteQuery<int>(
            queryKey: ['infinite', 'fetch-fail'],
            queryFn: (page) async {
              await Future.delayed(Duration(milliseconds: 10));
              throw Exception('boom');
            },
            initialPageParam: 1,
            retry: 0,
            retryDelay: 1,
          );

          holder.value = result;
          return Container();
        },
      ),
    )));

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
    final cacheKey = queryKeyToCacheKey(['infinite', 'fetch-fail']);
    if (client.queryCache.containsKey(cacheKey)) {
      final cached = client.queryCache[cacheKey]!.result as InfiniteQueryResult<int>;
      expect(cached.status, equals(QueryStatus.error));
      expect(cached.error.toString(), contains('boom'));
      expect(cached.failureCount, greaterThanOrEqualTo(1));
      expect(cached.failureReason, isNotNull);
    }
  });

  testWidgets('should retry up to retry count and succeed (infinite)', (WidgetTester tester) async {
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);
    var attempts = 0;

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(
        builder: (context) {
          final result = useInfiniteQuery<int>(
            queryKey: ['infinite', 'retry-success'],
            queryFn: (page) async {
              attempts++;
              await Future.delayed(Duration(milliseconds: 5));
              if (attempts < 3) throw Exception('try-$attempts');
              return page;
            },
            initialPageParam: 1,
            retry: 3,
            retryDelay: 5,
          );

          holder.value = result;

          return Container();
        },
      ),
    )));

    // let retries happen
    await tester.pump();
    await tester.pumpAndSettle();

    expect(attempts, greaterThanOrEqualTo(3));
    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals([1]));
  });

  testWidgets('should not retry on mount if retryOnMount is false (infinite)', (WidgetTester tester) async {
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);
    var called = false;
    final keyList = ['infinite-no-retry-on-mount'];
    final cacheKey = queryKeyToCacheKey(keyList);

    // place an errored entry in cache
    final errored = InfiniteQueryResult<int>(
      key: cacheKey,
      status: QueryStatus.error,
      data: <int>[],
      isFetching: false,
      error: Exception('old-error'),
      isFetchingNextPage: false,
    );
    errored.failureCount = 1;
    errored.failureReason = Exception('old-error');
    client.queryCache[cacheKey] = QueryCacheEntry(errored, DateTime.now());

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(builder: (context) {
        final result = useInfiniteQuery<int>(
          queryKey: keyList,
          queryFn: (page) async {
            called = true;
            return page;
          },
          retryOnMount: false,
          initialPageParam: 1,
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

  testWidgets('should set error state when fetching next page fails',
      (WidgetTester tester) async {
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(
        builder: (context) {
          final result = useInfiniteQuery<int>(
            queryKey: ['infinite', 'next-error'],
            queryFn: (page) async {
              await Future.delayed(Duration(milliseconds: 10));
              if (page == 1) return 1;
              throw Exception('boom-next');
            },
            initialPageParam: 1,
            retry: 0,
            retryDelay: 1,
            getNextPageParam: (last) => last + 1,
          );

          holder.value = result;
          return Container();
        },
      ),
    )));

    // wait initial success
    await tester.pumpAndSettle();
    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals([1]));

    // attempt to load next page which will throw
    holder.value!.fetchNextPage?.call();
    await tester.pump(); // start
    await tester.pumpAndSettle(); // finish

    // After next-page error the hook sets status error and clears data
    expect(holder.value!.status, equals(QueryStatus.error));
    expect(holder.value!.data, equals(<int>[]));
    // cache should reflect the error
    final nextKey = queryKeyToCacheKey(['infinite', 'next-error']);
    final nextCached = client.queryCache[nextKey]!.result as InfiniteQueryResult<int>;
    expect(nextCached.status, equals(QueryStatus.error));
    expect(nextCached.data, equals(<int>[]));
  });

  testWidgets('should debounce when queryKey changes and debounceTime is set',
      (WidgetTester tester) async {
    bool toggled = false;

    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        return HookBuilder(builder: (ctx) {
          final result = useInfiniteQuery<int>(
            queryKey: ['infinite', 'debounce', toggled ? 'b' : 'a'],
            queryFn: (page) async {
              await Future.delayed(Duration(milliseconds: 10));
              return page;
            },
            initialPageParam: 1,
            debounceTime: toggled ? Duration(milliseconds: 50) : null,
          );

          holder.value = result;
          return Column(
            children: [
              ElevatedButton(
                  onPressed: () => setState(() => toggled = true),
                  child: Text('toggle')),
            ],
          );
        });
      }),
    )));

    // initial run: immediate fetch (no debounce)
    await tester.pumpAndSettle();
    expect(holder.value!.status, equals(QueryStatus.success));

    // toggle to new queryKey with debounce enabled
    await tester.tap(find.text('toggle'));
    await tester.pump(); // begin rebuild + debounce timer set

    // immediately after toggle it should reflect loading (pending) and empty data
    expect(
        holder.value!.status,
        anyOf(equals(QueryStatus.pending), equals(QueryStatus.error),
            equals(QueryStatus.success)));
    // For the pending case we expect the data to be empty
    if (holder.value!.status == QueryStatus.pending) {
      expect(holder.value!.data, equals(<int>[]));
    }

    // wait longer than debounce + query delay to let fetch finish
    await tester.pump(Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    // should now have fetched the new key
    expect(holder.value!.status, equals(QueryStatus.success));
    expect(holder.value!.data, equals([1]));
  });

  testWidgets(
      'should not crash if widget unmounts during in-flight next-page fetch',
      (WidgetTester tester) async {
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(
        builder: (context) {
          final result = useInfiniteQuery<int>(
            queryKey: ['infinite', 'unmount-during-fetch'],
            queryFn: (page) async {
              // initial page quick
              if (page == 1) {
                await Future.delayed(Duration(milliseconds: 10));
                return 1;
              }
              // next page intentionally delayed so we can unmount mid-flight
              await Future.delayed(Duration(milliseconds: 100));
              return page;
            },
            initialPageParam: 1,
            getNextPageParam: (last) => last + 1,
          );

          holder.value = result;
          return Container();
        },
      ),
    )));

    // wait initial fetch
    await tester.pumpAndSettle();
    expect(holder.value!.status, equals(QueryStatus.success));

    // start loading next page, then unmount immediately
    holder.value!.fetchNextPage?.call();
    await tester.pump(); // begin network request

    // unmount the widget before the in-flight future completes
    await tester.pumpWidget(Container());

    // wait longer than the delayed next-page future, make sure no unhandled exceptions occur
    await tester.pump(Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  });

  testWidgets('should refetch when data is stale', (WidgetTester tester) async {
    final keyList = ['infinite', 'stale-key'];
    final cacheKey = queryKeyToCacheKey(keyList);
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    // populate cache with old timestamp
    client.queryCache[cacheKey] = QueryCacheEntry(
        InfiniteQueryResult<int>(key: cacheKey, status: QueryStatus.success, data: <int>[0], isFetching: false, error: null, isFetchingNextPage: false),
        DateTime.now().subtract(Duration(milliseconds: 200)));

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(builder: (context) {
        final result = useInfiniteQuery<int>(
          queryKey: keyList,
          queryFn: (page) async {
            await Future.delayed(Duration(milliseconds: 5));
            return 1;
          },
          initialPageParam: 1,
          staleTime: 100, // ms -> cached entry older than this
        );

        holder.value = result;

        return Container();
      }),
    )));

    // initial state should detect stale and fetch
    await tester.pump();
    await tester.pumpAndSettle();

    expect(holder.value!.data, equals([1]));
    // cache should be updated with fresh value
    final cached = client.queryCache[cacheKey]!.result as InfiniteQueryResult<int>;
    expect(cached.data, equals([1]));
  });

  testWidgets('staleTime 0 should consider cached data stale immediately and refetch', (WidgetTester tester) async {
    final keyList = ['infinite', 'stale-zero'];
    final cacheKey = queryKeyToCacheKey(keyList);
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    // populate cache with a fresh timestamp, but staleTime = 0 should force refetch
    client.queryCache[cacheKey] = QueryCacheEntry(
      InfiniteQueryResult<int>(key: cacheKey, status: QueryStatus.success, data: <int>[1], isFetching: false, error: null, isFetchingNextPage: false),
      DateTime.now(),
    );

    var called = false;

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(builder: (context) {
        final result = useInfiniteQuery<int>(
          queryKey: keyList,
          queryFn: (page) async {
            called = true;
            await Future.delayed(Duration(milliseconds: 5));
            return 2;
          },
          initialPageParam: 1,
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
    expect(holder.value!.data, equals([2]));
    expect((client.queryCache[cacheKey]!.result as InfiniteQueryResult<int>).data, equals([2]));
  });

  testWidgets('staleTime Infinity should never consider data stale', (WidgetTester tester) async {
    final keyList = ['infinite', 'stale-infinite'];
    final cacheKey = queryKeyToCacheKey(keyList);
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    // populate cache with an old timestamp
    client.queryCache[cacheKey] = QueryCacheEntry(
      InfiniteQueryResult<int>(key: cacheKey, status: QueryStatus.success, data: <int>[9], isFetching: false, error: null, isFetchingNextPage: false),
      DateTime.now().subtract(Duration(days: 1)),
    );

    var called = false;

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(builder: (context) {
        final result = useInfiniteQuery<int>(
          queryKey: keyList,
          queryFn: (page) async {
            called = true;
            await Future.delayed(Duration(milliseconds: 5));
            return page;
          },
          initialPageParam: 1,
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
    expect(holder.value!.data, equals([9]));
  });

  testWidgets('should not refetch when data is not null and not stale', (WidgetTester tester) async {
    final keyList = ['infinite', 'fresh-key'];
    final cacheKey = queryKeyToCacheKey(keyList);

    // populate cache with recent timestamp
    client.queryCache[cacheKey] = QueryCacheEntry(
        InfiniteQueryResult<int>(key: cacheKey, status: QueryStatus.success, data: <int>[7], isFetching: false, error: null, isFetchingNextPage: false),
        DateTime.now());

    var called = false;

    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);

    await tester.pumpWidget(QueryClientProvider(
        client: client,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            final result = useInfiniteQuery<int>(
              queryKey: keyList,
              queryFn: (page) async {
                called = true;
                return 99;
              },
              initialPageParam: 1,
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
    expect(holder.value!.data, equals([7]));
  });

  testWidgets('should refetch when previous fetch is fulfilled (retryer not blocking)', (WidgetTester tester) async {
    final keyList = ['infinite', 'fulfilled-retryer'];
    final cacheKey = queryKeyToCacheKey(keyList);
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);
    var called = 0;

    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(builder: (context) {
        final result = useInfiniteQuery<int>(
          queryKey: keyList,
          queryFn: (page) async {
            called++;
            await Future.delayed(Duration(milliseconds: 5));
            return called; // return the call count so we can assert change
          },
          initialPageParam: 1,
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
    expect(holder.value!.data, equals([1]));

    // Trigger a cache-level refetch event (simulate external invalidation)
    client.queryCache.refetchByCacheKey(cacheKey);
    await tester.pump();
    await tester.pumpAndSettle();

    // ensure queryFn ran again and the data updated
    expect(called, equals(2));
    expect(holder.value!.data, equals([2]));
  });

  testWidgets('should garbage collect infinite query after gcTime when unmounted', (WidgetTester tester) async {
    final holder = ValueNotifier<InfiniteQueryResult<int>?>(null);
    final keyList = ['infinite-gc-test'];
    final cacheKey = queryKeyToCacheKey(keyList);

    // mount a widget that runs an infinite query with a short gcTime
    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(
      home: HookBuilder(
        builder: (context) {
          final result = useInfiniteQuery<int>(
            queryKey: keyList,
            queryFn: (page) async {
              await Future.delayed(Duration(milliseconds: 5));
              return 1;
            },
            initialPageParam: 1,
            gcTime: 50, // ms
          );

          holder.value = result;
          return Container();
        },
      ),
    )));

    // let the query complete and ensure the cache has the entry
    await tester.pump();
    await tester.pumpAndSettle();

    expect(client.queryCache.containsKey(cacheKey), isTrue);

    // unmount the hook (no observers should remain)
    await tester.pumpWidget(QueryClientProvider(client: client, child: MaterialApp(home: Container())));

    // wait for the gc timer to fire (max ~500ms to avoid flakiness)
    var tries = 0;
    while (client.queryCache.containsKey(cacheKey) && tries < 50) {
      await tester.pump(Duration(milliseconds: 20));
      tries++;
    }

    expect(client.queryCache.containsKey(cacheKey), isFalse);
  });
}
