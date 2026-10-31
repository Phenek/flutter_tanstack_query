import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

import 'test_utils.dart';

void main() {
  tearDown(notifyManager.reset);

  group('batch', () {
    test('returns the value of its callback', () {
      // fetchQuery, refetchQueries and invalidateQueries all hand a Future back
      // out of a batch, so the return value must survive the flush.
      final value = notifyManager.batch<int>(() => 42);
      expect(value, 42);
    });

    test('holds notifications until the outermost batch ends', () async {
      final seen = <String>[];
      notifyManager.batch(() {
        notifyManager.schedule(() => seen.add('a'));
        notifyManager.batch(() {
          notifyManager.schedule(() => seen.add('b'));
          expect(seen, isEmpty, reason: 'an inner batch must not flush');
        });
        expect(seen, isEmpty, reason: 'still inside the outer batch');
      });

      await Future<void>.delayed(Duration.zero);
      expect(seen, ['a', 'b']);
    });

    test('flushes even when the callback throws', () async {
      final seen = <String>[];
      expect(
        () => notifyManager.batch(() {
          notifyManager.schedule(() => seen.add('a'));
          throw StateError('boom');
        }),
        throwsStateError,
      );

      await Future<void>.delayed(Duration.zero);
      expect(seen, ['a'],
          reason: 'the transaction counter must unwind in a finally');
    });

    test('a scheduled callback outside a batch is deferred, never synchronous',
        () async {
      final seen = <String>[];
      notifyManager.schedule(() => seen.add('a'));
      expect(seen, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['a']);
    });
  });

  group('notification guard', () {
    testWidgets('a single fetch rebuilds once past the initial build',
        (tester) async {
      final client = testQueryClient();
      final key = queryKey();

      final probe = await pumpHook(
        tester,
        () => useQuery<String>(
          queryKey: key,
          queryFn: () async {
            await sleep(10);
            return 'ok';
          },
        ),
        client: client,
      );
      await tester.pumpAndSettle();

      expect(probe.value.data, 'ok');
      expect(probe.rebuilds, 2,
          reason:
              'initial pending build, then one build for the settled result');
    });

    testWidgets('recomputing an identical result does not wake listeners',
        (tester) async {
      final client = testQueryClient();
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
      final settled = probe.rebuilds;

      // Nothing changed in the cache, so every observer recomputes the result it
      // already has: React Query's `shallowEqualObjects` guard drops the notify.
      client.queryCache.getQuery(queryKeyToCacheKey(key))!.notifyObservers();
      await tester.pumpAndSettle();

      expect(probe.rebuilds, settled);
    });

    testWidgets('two observers on one key rebuild once each per fetch',
        (tester) async {
      final client = testQueryClient();
      final key = queryKey();
      var calls = 0;

      QueryResult<String> hook() => useQuery<String>(
            queryKey: key,
            queryFn: () async {
              calls++;
              await sleep(10);
              return 'ok';
            },
          );

      final probe =
          await pumpHook(tester, () => [hook(), hook()].last, client: client);
      await tester.pumpAndSettle();

      expect(calls, 1, reason: 'the fetch is deduped by key');
      expect(probe.value.data, 'ok');
      expect(probe.rebuilds, 2);
    });
  });
}
