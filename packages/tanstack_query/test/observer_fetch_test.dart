import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

import 'test_utils.dart';

void main() {
  late QueryClient queryClient;

  setUp(() => queryClient = testQueryClient());

  testWidgets('observer.fetch awaits a queryFn slower than 4 seconds', (tester) async {
    // `QueryObserver.fetch` used to wrap `Query.fetch` in a hardcoded
    // `.timeout(Duration(seconds: 4))`, so any slower request resolved the
    // awaited result as still-pending while the fetch kept running. An
    // imperative `fetchQuery` built on top of it could never be trusted.
    final key = queryKey();
    final observer = QueryObserver<String, Object?, String>(
      queryClient,
      QueryOptions<String>(
        queryKey: key,
        queryFn: () async {
          await sleep(5000);
          return 'slow';
        },
      ),
    );
    addTearDown(observer.destroy);

    final pending = observer.fetch();
    await tester.pump(const Duration(seconds: 6));
    final result = await pending;

    expect(result.status, QueryStatus.success);
    expect(result.data, 'slow');
    expect(result.isFetching, isFalse);
    expect(cachedResult<String>(queryClient, key)?.data, 'slow');
  });

  testWidgets('an infinite observer reads the client it was built with, not the last one',
      (tester) async {
    // `InfiniteQueryObserver` used to reach for the `QueryClient.instance`
    // singleton, so building a second client silently rerouted the first
    // client's observers to the second one's cache.
    final first = testQueryClient();
    final key = queryKey();
    final observer = InfiniteQueryObserver<String>(
      first,
      InfiniteQueryOptions<String>(
        queryKey: key,
        initialPageParam: 0,
        queryFn: (pageParam) async => 'page-$pageParam',
      ),
    );
    addTearDown(observer.destroy);

    // Built last, so it owns `QueryClient.instance` from here on.
    final second = testQueryClient();

    final pending = observer.fetch();
    await tester.pump(const Duration(milliseconds: 10));
    await pending;

    final cacheKey = queryKeyToCacheKey(key);
    expect(first.queryCache.containsKey(cacheKey), isTrue,
        reason: 'the pages belong to the client the observer was built with');
    expect(second.queryCache.containsKey(cacheKey), isFalse);
  });
}
