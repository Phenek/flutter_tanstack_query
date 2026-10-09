import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

/// Regression tests for `QueryClient.invalidateQueries`.
///
/// React parity: invalidation marks the query stale and refetches it in the
/// background. The previously cached data must remain visible (status
/// `success`, `isFetching: true`, `isStale: true`) until the fresh data lands.
/// Before 1.2.8 the Dart port removed the query from the cache, so observers
/// briefly rendered `status: pending, data: null` — a visible flicker.
void main() {
  late QueryClient queryClient;

  // With the default staleTime (0) data turns stale after 1 ms of real time,
  // which makes `isStale` assertions timing-dependent. A long staleTime means
  // any `isStale: true` below can only come from invalidation.
  const oneHour = 60.0 * 60 * 1000;

  setUp(() {
    queryClient = QueryClient(
        defaultOptions: const DefaultOptions(
            queries: QueryDefaultOptions(gcTime: -1),
            mutations: MutationDefaultOptions(gcTime: -1)));
    queryClient.queryCache.clear();
  });

  /// Mounts a `useQuery` for [key] and records every rendered result.
  Future<List<QueryResult<String>>> mount(
    WidgetTester tester,
    List<Object> key, {
    required Future<String> Function() queryFn,
    bool? enabled,
    double? staleTime,
  }) async {
    final renders = <QueryResult<String>>[];
    await tester.pumpWidget(QueryClientProvider(
      client: queryClient,
      child: MaterialApp(
        home: HookBuilder(builder: (context) {
          final r = useQuery<String>(
            queryKey: key,
            queryFn: queryFn,
            enabled: enabled,
            staleTime: staleTime,
          );
          renders.add(r);
          return Container();
        }),
      ),
    ));
    await tester.pumpAndSettle();
    return renders;
  }

  testWidgets('keeps previous data visible while refetching', (tester) async {
    var n = 0;
    final renders = await mount(tester, ['inv-keep'], staleTime: oneHour,
        queryFn: () async {
      n++;
      await Future.delayed(const Duration(milliseconds: 50));
      return 'data-$n';
    });
    expect(renders.last.status, QueryStatus.success);
    expect(renders.last.data, 'data-1');
    expect(renders.last.isStale, isFalse);
    final before = renders.length;

    queryClient.invalidateQueries(queryKey: ['inv-keep']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    // Mid-flight: old data still there, flagged fetching + stale.
    final inFlight = renders.sublist(before);
    expect(inFlight, isNotEmpty);
    for (final r in inFlight) {
      expect(r.status, QueryStatus.success,
          reason: 'must never drop to pending during invalidation');
      expect(r.data, 'data-1');
    }
    expect(inFlight.last.isFetching, isTrue);
    expect(inFlight.last.isStale, isTrue);

    await tester.pumpAndSettle();
    expect(renders.last.status, QueryStatus.success);
    expect(renders.last.data, 'data-2');
    expect(renders.last.isFetching, isFalse);
    expect(renders.last.isStale, isFalse);
    expect(n, 2, reason: 'exactly one background refetch');

    // Every render across the whole sequence had data.
    expect(renders.where((r) => r.data == null).skip(1), isEmpty,
        reason: 'only the very first render (initial load) may be pending');
  });

  testWidgets('invalidateQueries() with no key invalidates everything',
      (tester) async {
    var a = 0, b = 0;
    final rendersA = <QueryResult<String>>[];
    final rendersB = <QueryResult<String>>[];
    await tester.pumpWidget(QueryClientProvider(
      client: queryClient,
      child: MaterialApp(
        home: Column(children: [
          HookBuilder(builder: (_) {
            rendersA.add(useQuery<String>(
                queryKey: ['all', 'a'],
                queryFn: () async {
                  a++;
                  await Future.delayed(const Duration(milliseconds: 20));
                  return 'a-$a';
                }));
            return Container();
          }),
          HookBuilder(builder: (_) {
            rendersB.add(useQuery<String>(
                queryKey: ['all', 'b'],
                queryFn: () async {
                  b++;
                  await Future.delayed(const Duration(milliseconds: 20));
                  return 'b-$b';
                }));
            return Container();
          }),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(rendersA.last.data, 'a-1');
    expect(rendersB.last.data, 'b-1');

    queryClient.invalidateQueries();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));
    expect(rendersA.last.data, 'a-1');
    expect(rendersA.last.isFetching, isTrue);
    expect(rendersB.last.data, 'b-1');
    expect(rendersB.last.isFetching, isTrue);

    await tester.pumpAndSettle();
    expect(rendersA.last.data, 'a-2');
    expect(rendersB.last.data, 'b-2');
    expect(a, 2);
    expect(b, 2);
  });

  testWidgets('exact: true only touches the exact key', (tester) async {
    var parent = 0, child = 0;
    final rendersP = <QueryResult<String>>[];
    final rendersC = <QueryResult<String>>[];
    await tester.pumpWidget(QueryClientProvider(
      client: queryClient,
      child: MaterialApp(
        home: Column(children: [
          HookBuilder(builder: (_) {
            rendersP.add(useQuery<String>(
                queryKey: ['todos'], queryFn: () async => 'p-${++parent}'));
            return Container();
          }),
          HookBuilder(builder: (_) {
            rendersC.add(useQuery<String>(
                queryKey: ['todos', 1],
                staleTime: oneHour,
                queryFn: () async => 'c-${++child}'));
            return Container();
          }),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    queryClient.invalidateQueries(queryKey: ['todos'], exact: true);
    await tester.pumpAndSettle();
    expect(parent, 2);
    expect(child, 1, reason: 'exact match must not refetch the child key');
    expect(rendersC.last.isStale, isFalse);

    // Prefix match reaches the child too.
    queryClient.invalidateQueries(queryKey: ['todos']);
    await tester.pumpAndSettle();
    expect(parent, 3);
    expect(child, 2);
  });

  testWidgets('disabled query is marked stale but not refetched',
      (tester) async {
    var n = 0;
    // Seed the cache so the disabled observer has data to show.
    queryClient.setQueryData<String>(['inv-disabled'], (_) => 'seeded');
    final renders = await mount(tester, ['inv-disabled'],
        enabled: false,
        staleTime: oneHour,
        queryFn: () async => 'fetched-${++n}');
    expect(renders.last.data, 'seeded');
    expect(n, 0);

    queryClient.invalidateQueries(queryKey: ['inv-disabled']);
    await tester.pumpAndSettle();

    expect(n, 0, reason: 'disabled queries ignore invalidateQueries refetch');
    expect(renders.last.data, 'seeded');
    expect(renders.last.isStale, isTrue);
  });

  testWidgets(
      'invalidating a key with no observer makes the next mount refetch '
      'despite a long staleTime', (tester) async {
    queryClient.setQueryData<String>(['inv-orphan'], (_) => 'seeded');
    queryClient.invalidateQueries(queryKey: ['inv-orphan']);

    // Cache entry is kept, only flagged.
    expect(queryClient.queryCache.find(['inv-orphan'])?.result.data, 'seeded');

    var n = 0;
    final renders = await mount(tester, ['inv-orphan'], staleTime: oneHour,
        queryFn: () async {
      n++;
      await Future.delayed(const Duration(milliseconds: 20));
      return 'fresh-$n';
    });

    expect(n, 1, reason: 'invalidation overrides staleTime on mount');
    expect(renders.last.data, 'fresh-1');
    expect(renders.last.isStale, isFalse);
  });

  testWidgets('setQueryData after invalidation clears the stale flag',
      (tester) async {
    var n = 0;
    final renders = await mount(tester, ['inv-setdata'], staleTime: oneHour,
        queryFn: () async {
      n++;
      await Future.delayed(const Duration(milliseconds: 50));
      return 'data-$n';
    });
    expect(renders.last.data, 'data-1');

    queryClient.invalidateQueries(queryKey: ['inv-setdata']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));
    expect(renders.last.isStale, isTrue);
    expect(renders.last.data, 'data-1');

    queryClient.setQueryData<String>(['inv-setdata'], (_) => 'manual');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));
    expect(renders.last.data, 'manual');
    expect(renders.last.isStale, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('invalidating an infinite query keeps all loaded pages',
      (tester) async {
    var fetches = 0;
    final renders = <InfiniteQueryResult<int>>[];
    await tester.pumpWidget(QueryClientProvider(
      client: queryClient,
      child: MaterialApp(
        home: HookBuilder(builder: (_) {
          renders.add(useInfiniteQuery<int>(
            queryKey: ['inv-infinite'],
            queryFn: (page) async {
              fetches++;
              await Future.delayed(const Duration(milliseconds: 20));
              return page * 10;
            },
            initialPageParam: 1,
            getNextPageParam: (last) => last ~/ 10 + 1,
          ));
          return Container();
        }),
      ),
    ));
    await tester.pumpAndSettle();
    renders.last.fetchNextPage?.call();
    await tester.pumpAndSettle();
    expect(renders.last.data, [10, 20]);
    final fetchesBefore = fetches;

    queryClient.invalidateQueries(queryKey: ['inv-infinite']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));
    expect(renders.last.status, QueryStatus.success);
    expect(renders.last.data, [10, 20], reason: 'pages stay visible');
    expect(renders.last.isFetching, isTrue);

    await tester.pumpAndSettle();
    expect(renders.last.data, [10, 20]);
    expect(fetches - fetchesBefore, 2,
        reason: 'background refetch reloads every page, like React');
  });
}
