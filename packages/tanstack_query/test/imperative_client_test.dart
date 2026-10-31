import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

import 'test_utils.dart';

void main() {
  late QueryClient client;

  setUp(() => client = testQueryClient());

  group('getQueryData / getQueryState', () {
    test('return null for a key nothing ever touched', () {
      expect(client.getQueryData<String>(queryKey()), isNull);
      expect(client.getQueryState<String>(queryKey()), isNull);
    });

    test('read what setQueryData wrote, without building a query', () {
      final key = queryKey();
      client.setQueryData<String>(key, (_) => 'written');

      expect(client.getQueryData<String>(key), 'written');
      expect(client.getQueryState<String>(key)?.status, QueryStatus.success);
      expect(client.queryCache.getQuery(queryKeyToCacheKey(key)), isNull,
          reason: 'reading must never build a query');
    });
  });

  group('setQueryData', () {
    test('an updater returning null writes nothing', () {
      final key = queryKey();
      client.setQueryData<String>(key, (_) => null);

      expect(client.queryCache.containsKey(queryKeyToCacheKey(key)), isFalse);
      expect(client.getQueryData<String>(key), isNull);
    });

    test('setQueryDataValue stores a plain value, like the JS updater', () {
      final key = queryKey();
      client.setQueryDataValue<String>(key, 'direct');

      expect(client.getQueryData<String>(key), 'direct');
      expect(client.getQueryState<String>(key)?.status, QueryStatus.success);
    });

    test('the updater receives the previous value', () {
      final key = queryKey();
      client.setQueryDataValue<int>(key, 1);
      client.setQueryData<int>(key, (old) => (old ?? 0) + 1);

      expect(client.getQueryData<int>(key), 2);
    });
  });

  group('setQueryDefaults / getQueryDefaults', () {
    test('defaults apply to keys under the registered prefix only', () {
      client.setQueryDefaults(
          ['api'], const QueryDefaults(staleTime: 60000, retry: 0));

      expect(client.getQueryDefaults(['api', 'stations']).staleTime, 60000);
      expect(client.getQueryDefaults(['api', 'stations']).retry, 0);
      expect(client.getQueryDefaults(['other']).staleTime, isNull);
    });

    test('later registrations win per field', () {
      client.setQueryDefaults(['api'], const QueryDefaults(staleTime: 1000));
      client.setQueryDefaults(
          ['api', 'v2'], const QueryDefaults(staleTime: 2000, retry: 5));

      final merged = client.getQueryDefaults(['api', 'v2', 7]);
      expect(merged.staleTime, 2000);
      expect(merged.retry, 5);
      // The broader default still fills the fields the narrower one leaves out.
      expect(client.getQueryDefaults(['api', 'v1']).staleTime, 1000);
    });

    testWidgets('fetchQuery picks up per-key defaults, options still win',
        (tester) async {
      client.setQueryDefaults(
          ['svc'], const QueryDefaults(staleTime: double.infinity));
      var calls = 0;
      Future<String> fetch() async {
        calls++;
        return 'ok';
      }

      await client.fetchQuery<String>(queryKey: ['svc', 1], queryFn: fetch);
      await tester.pump(const Duration(milliseconds: 10));
      await client.fetchQuery<String>(queryKey: ['svc', 1], queryFn: fetch);
      await tester.pump(const Duration(milliseconds: 10));
      expect(calls, 1, reason: 'the key default made the cached data fresh');

      // An explicit staleTime on the call beats the registered default.
      await client.fetchQuery<String>(
          queryKey: ['svc', 1], queryFn: fetch, staleTime: 0);
      await tester.pump(const Duration(milliseconds: 10));
      expect(calls, 2);
    });
  });

  group('getQueriesData', () {
    test('returns original keys and data for matching entries', () {
      client.setQueryDataValue<String>(['api', 'a'], 'A');
      client.setQueryDataValue<String>(['api', 'b'], 'B');
      client.setQueryDataValue<String>(['other'], 'C');

      final all = client.getQueriesData<String>();
      expect(all.map((e) => e.data).toSet(), {'A', 'B', 'C'});

      final apiOnly = client.getQueriesData<String>(queryKey: ['api']);
      expect(apiOnly.length, 2);
      expect(apiOnly.map((e) => e.key.first), everyElement('api'));
      expect(apiOnly.map((e) => e.data).toSet(), {'A', 'B'});

      final exact =
          client.getQueriesData<String>(queryKey: ['api', 'a'], exact: true);
      expect(exact.length, 1);
      expect(exact.single.key, ['api', 'a']);
      expect(exact.single.data, 'A');
    });

    test('does not match a key that merely starts with the same text', () {
      client.setQueryDataValue<String>(['todos', 1], 'one');

      expect(client.getQueriesData<String>(queryKey: ['todo']), isEmpty);
      expect(client.getQueriesData<String>(queryKey: ['todos']).single.data,
          'one');
    });
  });

  group('query defaults', () {
    test('a default applies to keys it is an element-wise prefix of', () {
      client.setQueryDefaults(['todos'], const QueryDefaults(staleTime: 5000));

      expect(client.getQueryDefaults(['todos']).staleTime, 5000);
      expect(client.getQueryDefaults(['todos', 1]).staleTime, 5000);
    });

    test(
        'a default does not leak onto a key that merely starts with the same text',
        () {
      // Matching serialized keys with `String.startsWith` would let ['todo']
      // capture ['todos', 1]; `partialMatchKey` compares element by element.
      client.setQueryDefaults(['todo'], const QueryDefaults(staleTime: 5000));

      expect(client.getQueryDefaults(['todos', 1]).staleTime, isNull);
      expect(client.getQueryDefaults(['todo', 1]).staleTime, 5000);
    });

    test('later registrations win per field', () {
      client.setQueryDefaults(
          ['todos'], const QueryDefaults(staleTime: 5000, gcTime: 1));
      client
          .setQueryDefaults(['todos', 1], const QueryDefaults(staleTime: 9000));

      final merged = client.getQueryDefaults(['todos', 1]);
      expect(merged.staleTime, 9000);
      expect(merged.gcTime, 1,
          reason: 'a field the later default says nothing about is kept');
    });

    testWidgets('fetchQuery honours a key default', (tester) async {
      final key = queryKey();
      var calls = 0;
      client.setQueryDefaults(
          key, const QueryDefaults(staleTime: double.infinity));

      Future<String> fetch() async {
        calls++;
        return 'ok';
      }

      await client.fetchQuery<String>(queryKey: key, queryFn: fetch);
      await tester.pump(const Duration(milliseconds: 10));
      await client.fetchQuery<String>(queryKey: key, queryFn: fetch);
      await tester.pump(const Duration(milliseconds: 10));

      expect(calls, 1,
          reason: 'the infinite staleTime came from the key default');
    });
  });

  group('fetchQuery', () {
    testWidgets('fetches, caches, and returns the data', (tester) async {
      final key = queryKey();
      var calls = 0;

      final pending = client.fetchQuery<String>(
        queryKey: key,
        queryFn: () async {
          calls++;
          await sleep(10);
          return 'ok';
        },
      );
      await tester.pump(const Duration(milliseconds: 20));

      expect(await pending, 'ok');
      expect(calls, 1);
      expect(client.getQueryData<String>(key), 'ok');
    });

    testWidgets('serves fresh cached data without calling the queryFn',
        (tester) async {
      final key = queryKey();
      var calls = 0;

      Future<String> fetch() async {
        calls++;
        return 'ok';
      }

      await client.fetchQuery<String>(
          queryKey: key, queryFn: fetch, staleTime: double.infinity);
      await tester.pump(const Duration(milliseconds: 10));
      expect(calls, 1);

      await client.fetchQuery<String>(
          queryKey: key, queryFn: fetch, staleTime: double.infinity);
      await tester.pump(const Duration(milliseconds: 10));
      expect(calls, 1, reason: 'the cached value is still fresh');
    });

    testWidgets('joins a fetch already in flight instead of duplicating it',
        (tester) async {
      // This is the whole point for a service running outside the widget tree:
      // it gets the same deduplication a mounted query would.
      final key = queryKey();
      var calls = 0;

      Future<String> fetch() async {
        calls++;
        await sleep(20);
        return 'ok';
      }

      final a = client.fetchQuery<String>(queryKey: key, queryFn: fetch);
      final b = client.fetchQuery<String>(queryKey: key, queryFn: fetch);
      await tester.pump(const Duration(milliseconds: 30));

      expect(await a, 'ok');
      expect(await b, 'ok');
      expect(calls, 1);
    });

    testWidgets('a useQuery mounted afterwards finds the data already there',
        (tester) async {
      final key = queryKey();
      var calls = 0;

      Future<String> fetch() async {
        calls++;
        await sleep(10);
        return 'ok';
      }

      final warm = client.fetchQuery<String>(
          queryKey: key, queryFn: fetch, staleTime: double.infinity);
      await tester.pump(const Duration(milliseconds: 20));
      await warm;

      final probe = await pumpHook(
        tester,
        () => useQuery<String>(
            queryKey: key, queryFn: fetch, staleTime: double.infinity),
        client: client,
      );
      await tester.pumpAndSettle();

      expect(calls, 1, reason: 'the imperative fetch already filled the cache');
      expect(probe.value.status, QueryStatus.success);
      expect(probe.value.data, 'ok');
    });

    testWidgets('does not retry by default, unlike a useQuery', (tester) async {
      final key = queryKey();
      var calls = 0;

      // Nothing configures `retry`, so the imperative caller sees the error
      // instead of waiting out the attempts a useQuery would make.
      await expectLater(
        client.fetchQuery<String>(
          queryKey: key,
          queryFn: () async {
            calls++;
            throw Exception('boom');
          },
        ),
        throwsA(isA<Exception>()),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(calls, 1);
    });

    testWidgets('a configured retry default still reaches fetchQuery',
        (tester) async {
      // JS applies `retry: false` only when `retry` is still undefined *after*
      // the merge, so a client default or a `setQueryDefaults` entry wins.
      var calls = 0;
      final client = testQueryClient(
          queries:
              const QueryDefaultOptions(gcTime: -1, retry: 1, retryDelay: 1));

      Object? caught;
      final pending = client
          .fetchQuery<String>(
        queryKey: queryKey(),
        queryFn: () async {
          calls++;
          throw Exception('boom');
        },
      )
          .catchError((Object e) {
        caught = e;
        return null;
      });
      await tester.pump(const Duration(milliseconds: 50));
      await pending;

      expect(caught, isA<Exception>());
      expect(calls, 2, reason: 'one attempt, then the single configured retry');
    });

    testWidgets('refetches an invalidated query despite an infinite staleTime',
        (tester) async {
      final key = queryKey();
      var calls = 0;
      Future<String> fetch() async {
        calls++;
        return 'v$calls';
      }

      await client.fetchQuery<String>(
          queryKey: key, queryFn: fetch, staleTime: double.infinity);
      await tester.pump(const Duration(milliseconds: 10));
      expect(calls, 1);

      client.invalidateQueries(queryKey: key);
      final data = await client.fetchQuery<String>(
          queryKey: key, queryFn: fetch, staleTime: double.infinity);
      await tester.pump(const Duration(milliseconds: 10));

      // `isStaleByTime` checks `isInvalidated` before the staleTime, as in JS.
      expect(calls, 2);
      expect(data, 'v2');
    });
  });

  group('prefetchQuery', () {
    testWidgets('swallows the error and still fills nothing', (tester) async {
      final key = queryKey();

      await client.prefetchQuery<String>(
        queryKey: key,
        queryFn: () async => throw Exception('boom'),
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(client.getQueryState<String>(key)?.status, QueryStatus.error);
    });
  });

  group('ensureQueryData', () {
    testWidgets('returns cached data without fetching', (tester) async {
      final key = queryKey();
      var calls = 0;
      client.setQueryData<String>(key, (_) => 'cached');

      final data = await client.ensureQueryData<String>(
        queryKey: key,
        queryFn: () async {
          calls++;
          return 'fetched';
        },
      );

      expect(data, 'cached');
      expect(calls, 0);
    });

    testWidgets('fetches when there is nothing cached', (tester) async {
      final key = queryKey();

      final pending = client.ensureQueryData<String>(
        queryKey: key,
        queryFn: () async {
          await sleep(10);
          return 'fetched';
        },
      );
      await tester.pump(const Duration(milliseconds: 20));

      expect(await pending, 'fetched');
    });

    testWidgets(
        'revalidateIfStale serves the stale data and refetches behind it',
        (tester) async {
      final key = queryKey();
      var calls = 0;
      client.setQueryData<String>(key, (_) => 'stale');

      // Staleness is measured against `DateTime.now()`, which the test binding
      // does not fake — only timers are faked. So let real time pass, otherwise
      // data written microseconds ago is not stale even at `staleTime: 0`.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));

      final data = await client.ensureQueryData<String>(
        queryKey: key,
        queryFn: () async {
          calls++;
          await sleep(10);
          return 'fresh';
        },
        staleTime: 0,
        revalidateIfStale: true,
      );
      expect(data, 'stale', reason: 'the caller is not made to wait');

      await tester.pump(const Duration(milliseconds: 20));
      expect(calls, 1);
      expect(client.getQueryData<String>(key), 'fresh');
    });
  });

  group('ensureInfiniteQueryData', () {
    testWidgets('serves cached pages, even an empty page list', (tester) async {
      // JS delegates to `ensureQueryData`, which only fetches when the cached
      // data is *absent*: an empty list the server really returned is served.
      final key = queryKey();
      var calls = 0;
      client.setQueryInfiniteData<String>(key, (_) => <String>[]);

      final pages = await client.ensureInfiniteQueryData<String>(
        queryKey: key,
        queryFn: (pageParam) async {
          calls++;
          return 'page$pageParam';
        },
        initialPageParam: 0,
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(pages, isEmpty);
      expect(calls, 0);
    });

    testWidgets('fetches the first page when nothing is cached',
        (tester) async {
      final key = queryKey();

      final pending = client.ensureInfiniteQueryData<String>(
        queryKey: key,
        queryFn: (pageParam) async => 'page$pageParam',
        initialPageParam: 0,
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(await pending, ['page0']);
    });

    testWidgets(
        'revalidateIfStale serves the cached pages and refetches behind',
        (tester) async {
      final key = queryKey();
      var calls = 0;
      client.setQueryInfiniteData<String>(key, (_) => <String>['stale']);

      // Staleness is measured against `DateTime.now()`, which the binding does
      // not fake — let real time pass so data written now is stale at 0.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));

      final pages = await client.ensureInfiniteQueryData<String>(
        queryKey: key,
        queryFn: (pageParam) async {
          calls++;
          return 'fresh';
        },
        initialPageParam: 0,
        staleTime: 0,
        revalidateIfStale: true,
      );
      expect(pages, ['stale'], reason: 'the caller is not made to wait');

      await tester.pump(const Duration(milliseconds: 20));
      expect(calls, 1);
      expect(client.getQueryData<List<String>>(key), ['fresh']);
    });
  });

  group('removeQueries / resetQueries', () {
    testWidgets('removeQueries drops the data and refetches nothing',
        (tester) async {
      final key = queryKey();
      await client.fetchQuery<String>(queryKey: key, queryFn: () async => 'ok');
      await tester.pump(const Duration(milliseconds: 10));
      expect(client.getQueryData<String>(key), 'ok');

      client.removeQueries(queryKey: key);

      expect(client.getQueryData<String>(key), isNull);
      expect(client.queryCache.getQuery(queryKeyToCacheKey(key)), isNull);
    });

    test('removeQueries drops data written by setQueryData alone', () {
      // Nothing mounted this key, so the cache entry has no `Query` behind it —
      // React has a single map and `findAll` sees it all the same.
      final key = queryKey();
      client.setQueryDataValue<String>(key, 'written');

      client.removeQueries(queryKey: key);

      expect(client.getQueryData<String>(key), isNull);
      expect(client.queryCache.containsKey(queryKeyToCacheKey(key)), isFalse);
    });

    test('removeQueries() with no filter clears cache-only entries too', () {
      client.setQueryDataValue<String>(['a'], 'A');
      client.setQueryDataValue<String>(['b'], 'B');

      client.removeQueries();

      expect(client.getQueriesData<String>(), isEmpty);
    });

    test('a key is matched element by element, not as text', () {
      // Comparing serialized keys with `startsWith` would let ['todos', 1]
      // match ['todos', 11]; `partialMatchKey` compares element by element.
      client.setQueryDataValue<String>(['todos', 1], 'one');
      client.setQueryDataValue<String>(['todos', 11], 'eleven');

      client.removeQueries(queryKey: ['todos', 1]);

      expect(client.getQueryData<String>(['todos', 1]), isNull);
      expect(client.getQueryData<String>(['todos', 11]), 'eleven');
    });

    test('resetQueries clears an entry nothing observes', () {
      final key = queryKey();
      client.setQueryDataValue<String>(key, 'written');

      client.resetQueries(queryKey: key);

      expect(client.getQueryData<String>(key), isNull);
    });

    testWidgets('a mounted query falls back to pending after removeQueries',
        (tester) async {
      final key = queryKey();

      final probe = await pumpHook(
        tester,
        () => useQuery<String>(
          queryKey: key,
          queryFn: () async => 'ok',
          staleTime: double.infinity,
        ),
        client: client,
      );
      await tester.pumpAndSettle();
      expect(probe.value.data, 'ok');

      client.removeQueries(queryKey: key);
      await tester.pumpAndSettle();

      // React recomputes from the query's initial state on its next render; the
      // removed data must not stay on screen.
      expect(probe.value.status, QueryStatus.pending);
      expect(probe.value.data, isNull);
    });

    testWidgets('resetQueries refetches a mounted query', (tester) async {
      final key = queryKey();
      var calls = 0;

      final probe = await pumpHook(
        tester,
        () => useQuery<String>(
          queryKey: key,
          queryFn: () async {
            calls++;
            return 'ok-$calls';
          },
          staleTime: double.infinity,
        ),
        client: client,
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(probe.value.data, 'ok-1');

      client.resetQueries(queryKey: key);
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(probe.value.data, 'ok-2');
    });
  });

  group('usePrefetchQuery', () {
    testWidgets('warms the cache for a query mounted later', (tester) async {
      final key = queryKey();
      var calls = 0;

      Future<String> fetch() async {
        calls++;
        await sleep(10);
        return 'ok';
      }

      await tester.pumpWidget(QueryClientProvider(
        client: client,
        child: HookBuilder(builder: (context) {
          usePrefetchQuery<String>(queryKey: key, queryFn: fetch);
          return const SizedBox.shrink();
        }),
      ));
      await tester.pump(const Duration(milliseconds: 20));

      expect(calls, 1);
      expect(client.getQueryData<String>(key), 'ok');
    });

    testWidgets('does nothing when the key is already cached', (tester) async {
      final key = queryKey();
      var calls = 0;
      client.setQueryData<String>(key, (_) => 'cached');

      await tester.pumpWidget(QueryClientProvider(
        client: client,
        child: HookBuilder(builder: (context) {
          usePrefetchQuery<String>(
              queryKey: key,
              queryFn: () async {
                calls++;
                return 'fetched';
              });
          return const SizedBox.shrink();
        }),
      ));
      await tester.pump(const Duration(milliseconds: 20));

      expect(calls, 0);
      expect(client.getQueryData<String>(key), 'cached');
    });
  });
}
