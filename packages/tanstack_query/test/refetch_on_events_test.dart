import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

void main() {
  late QueryClient queryClient;

  setUp(() {
    queryClient = QueryClient(
        defaultOptions:
            const DefaultOptions(queries: QueryDefaultOptions(gcTime: 0)));
    queryClient.queryCache.clear();

    // ensure managers are in a default state
    focusManager.setFocused(false);
    onlineManager.setOnline(false);
  });

  testWidgets('refetchOnMount: true triggers refetch on mount when stale',
      (WidgetTester tester) async {
    final key = ['mount-refetch'];
    final cacheKey = queryKeyToCacheKey(key);

    // put an old cache entry so the observer considers it stale
    queryClient.queryCache[cacheKey] = QueryCacheEntry(
        QueryResult<String>(cacheKey, QueryStatus.success, 'old', null),
        DateTime.now().subtract(const Duration(minutes: 10)));

    var calls = 0;
    final holder = ValueNotifier<QueryResult<String>?>(null);

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
              refetchOnMount: true,
              staleTime: 0,
            );

            holder.value = q;
            return Container();
          }),
        )));

    // allow any fetch to run
    await tester.pump();
    await tester.pumpAndSettle();

    expect(calls, greaterThanOrEqualTo(1));
    expect(holder.value!.data, equals('fresh'));
  });

  testWidgets('refetchOnMount: false does not refetch on mount',
      (WidgetTester tester) async {
    final key = ['mount-no-refetch'];
    final cacheKey = queryKeyToCacheKey(key);

    queryClient.queryCache[cacheKey] = QueryCacheEntry(
        QueryResult<String>(cacheKey, QueryStatus.success, 'old', null),
        DateTime.now().subtract(const Duration(minutes: 10)));

    var calls = 0;

    await tester.pumpWidget(QueryClientProvider(
        client: queryClient,
        child: MaterialApp(
          home: HookBuilder(builder: (context) {
            useQuery<String>(
              queryKey: key,
              queryFn: () async {
                calls++;
                return 'fresh';
              },
              refetchOnMount: false,
              staleTime: 0,
            );
            return Container();
          }),
        )));

    await tester.pump();

    expect(calls, equals(0));
  });

  testWidgets('refetchOnWindowFocus triggers refetch when focusManager fires',
      (WidgetTester tester) async {
    final key = ['focus-refetch'];
    final cacheKey = queryKeyToCacheKey(key);

    queryClient.queryCache[cacheKey] = QueryCacheEntry(
        QueryResult<String>(cacheKey, QueryStatus.success, 'old', null),
        DateTime.now().subtract(const Duration(minutes: 10)));

    var calls = 0;
    final holder = ValueNotifier<QueryResult<String>?>(null);

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

    // initial mount should not have triggered the refetch (we left refetchOnMount default)
    await tester.pump();
    expect(calls, equals(0));

    // simulate gaining focus
    focusManager.setFocused(true);

    await tester.pump();
    await tester.pumpAndSettle();

    expect(calls, greaterThanOrEqualTo(1));
    expect(holder.value!.data, equals('fresh'));
  });

  testWidgets('refetchOnReconnect triggers refetch when onlineManager fires',
      (WidgetTester tester) async {
    final key = ['reconnect-refetch'];
    final cacheKey = queryKeyToCacheKey(key);

    queryClient.queryCache[cacheKey] = QueryCacheEntry(
        QueryResult<String>(cacheKey, QueryStatus.success, 'old', null),
        DateTime.now().subtract(const Duration(minutes: 10)));

    var calls = 0;
    final holder = ValueNotifier<QueryResult<String>?>(null);

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

    await tester.pump();
    expect(calls, equals(0));

    // simulate reconnect
    onlineManager.setOnline(true);

    await tester.pump();
    await tester.pumpAndSettle();

    expect(calls, greaterThanOrEqualTo(1));
    expect(holder.value!.data, equals('fresh'));
  });
}
