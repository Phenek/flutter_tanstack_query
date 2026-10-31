import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

import 'test_utils.dart';

/// Stands in for the record a Dart 3 consumer would use — the package itself
/// targets `sdk >=2.19.4`, which predates records.
class Summary {
  final double km;
  final int minutes;

  const Summary(this.km, this.minutes);

  @override
  bool operator ==(Object other) =>
      other is Summary && other.km == km && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(km, minutes);

  @override
  String toString() => 'Summary($km, $minutes)';
}

class Route {
  final double meters;
  final double seconds;

  const Route(this.meters, this.seconds);
}

Summary _toSummary(Route route) =>
    Summary(route.meters / 1000, (route.seconds / 60).round());

void main() {
  group('replaceEqualDeep', () {
    test('keeps the previous instance when the value is deeply equal', () {
      final a = [1, 2, 3];
      final b = [1, 2, 3];
      expect(replaceEqualDeep(a, b), same(a));
    });

    test('keeps equal sub-lists inside a changed list', () {
      final inner = [1, 2];
      final a = [
        inner,
        [3]
      ];
      final b = [
        [1, 2],
        [4]
      ];
      final result = replaceEqualDeep(a, b);

      expect(result, isNot(same(a)));
      expect(result[0], same(inner),
          reason: 'the untouched page keeps its identity');
      expect(result[1], [4]);
    });

    test('preserves the reified element type', () {
      // `List<Object?>` copies used to fail the cast back to `List<int>`, which
      // surfaced as a query error instead of data.
      final result = replaceEqualDeep<List<int>>([1, 2], [1, 3]);
      expect(result, isA<List<int>>());
      expect(result, [1, 3]);
    });

    test('recognises value-equal objects as unchanged', () {
      // A deliberate improvement over the JS version, which compares with `===`:
      // a Freezed model or a Dart 3 record is kept instead of being replaced.
      final a = Summary(1.0, 2);
      final b = Summary(1.0, 2);
      expect(replaceEqualDeep(a, b), same(a));
    });

    test('shares a map whole when every entry matches', () {
      final a = {'a': 1, 'b': 2};
      final b = {'a': 1, 'b': 2};
      expect(replaceEqualDeep(a, b), same(a));
      expect(replaceEqualDeep<Map<String, int>>(a, {'a': 1, 'b': 9}),
          isA<Map<String, int>>());
    });

    test('replaceData calls a merge function written inline', () {
      // `structuralSharing` is typed `Object?` so it can also hold `false`,
      // which leaves an inline closure with no contextual type: it infers
      // `dynamic Function(dynamic, dynamic)`. JS only checks
      // `typeof === 'function'`, so the user's merge must still run.
      expect(replaceData<List<int>>([1], [2], (prev, next) => <int>[42]), [42]);
    });

    test('replaces values that are not traversable', () {
      expect(replaceEqualDeep('a', 'b'), 'b');
      expect(replaceEqualDeep([1], 'b'), 'b');
    });
  });

  group('structuralSharing on the cached data', () {
    testWidgets('a refetch returning the same payload keeps the data identity',
        (tester) async {
      final client = testQueryClient();
      final key = queryKey();

      final probe = await pumpHook(
        tester,
        // A fresh list every call: without structural sharing each refetch is a
        // new instance and every observer rebuilds.
        () =>
            useQuery<List<int>>(queryKey: key, queryFn: () async => [1, 2, 3]),
        client: client,
      );
      await tester.pumpAndSettle();
      expect(probe.value.data, [1, 2, 3]);
      final settled = probe.rebuilds;
      final firstData = probe.value.data;

      await probe.value.refetch!();
      await tester.pumpAndSettle();

      // The payload is identical, so `data` keeps its instance: anything
      // memoized on it — a `select` result, a `useMemoized` keyed on the data —
      // is not recomputed.
      expect(probe.value.data, same(firstData));

      // One rebuild, not two: `isFetching` flipping and the new `dataUpdatedAt`
      // are real changes, but the batch coalesces them into a single
      // notification. Without structural sharing this would still be one
      // rebuild, with a brand new list each time.
      expect(probe.rebuilds, settled + 1);
    });

    testWidgets(
        'a queryFn returning a Map still lands as data, not as an error',
        (tester) async {
      final client = testQueryClient();
      final key = queryKey();

      final probe = await pumpHook(
        tester,
        () => useQuery<Map<String, dynamic>>(
            queryKey: key, queryFn: () async => {'a': 1}),
        client: client,
      );
      await tester.pumpAndSettle();

      expect(probe.value.status, QueryStatus.success);
      expect(probe.value.error, isNull);
      expect(probe.value.data, {'a': 1});
    });

    testWidgets('an inline structuralSharing closure decides the merge',
        (tester) async {
      final client = testQueryClient();
      final key = queryKey();

      final probe = await pumpHook(
        tester,
        () => useQuery<List<int>>(
            queryKey: key,
            queryFn: () async => [1, 2, 3],
            structuralSharing: (prev, next) => <int>[9]),
        client: client,
      );
      await tester.pumpAndSettle();

      expect(probe.value.data, [9]);
    });

    testWidgets('structuralSharing: false hands back the new instance',
        (tester) async {
      final client = testQueryClient();
      final key = queryKey();

      final probe = await pumpHook(
        tester,
        () => useQuery<List<int>>(
            queryKey: key,
            queryFn: () async => [1, 2, 3],
            structuralSharing: false),
        client: client,
      );
      await tester.pumpAndSettle();
      final firstData = probe.value.data;

      await probe.value.refetch!();
      await tester.pumpAndSettle();

      expect(probe.value.data, isNot(same(firstData)));
    });
  });

  group('select', () {
    testWidgets('an observer exposes the selected shape', (tester) async {
      final client = testQueryClient();
      final key = queryKey();

      final observer = QueryObserver<Route, Object?, Summary>(
        client,
        QueryObserverOptions<Route, Summary>(
          queryKey: key,
          queryFn: () async => const Route(110000.0, 5400.0),
          select: _toSummary,
        ),
      );
      addTearDown(observer.destroy);

      final unsubscribe = observer.subscribe((_) {});
      await tester.pump(const Duration(milliseconds: 10));

      final result = observer.getCurrentResult();
      expect(result.status, QueryStatus.success);
      expect(result.data, const Summary(110.0, 90));
      unsubscribe();
    });

    testWidgets('two observers select different shapes from one fetch',
        (tester) async {
      final client = testQueryClient();
      final key = queryKey();
      var calls = 0;

      Future<Route> fetch() async {
        calls++;
        return const Route(110000.0, 5400.0);
      }

      final summaryObserver = QueryObserver<Route, Object?, Summary>(
        client,
        QueryObserverOptions<Route, Summary>(
          queryKey: key,
          queryFn: fetch,
          select: _toSummary,
          staleTime: double.infinity,
        ),
      );
      final kmObserver = QueryObserver<Route, Object?, double>(
        client,
        QueryObserverOptions<Route, double>(
          queryKey: key,
          queryFn: fetch,
          select: (r) => r.meters / 1000,
          staleTime: double.infinity,
        ),
      );
      addTearDown(summaryObserver.destroy);
      addTearDown(kmObserver.destroy);

      final unsubA = summaryObserver.subscribe((_) {});
      final unsubB = kmObserver.subscribe((_) {});
      await tester.pump(const Duration(milliseconds: 10));

      expect(calls, 1, reason: 'one cached payload, one network call');
      expect(summaryObserver.getCurrentResult().data, const Summary(110.0, 90));
      expect(kmObserver.getCurrentResult().data, 110.0);
      unsubA();
      unsubB();
    });

    testWidgets('a selecting observer and a plain one share a single fetch',
        (tester) async {
      // The real shape in GasMobility: the itinerary view reads the whole route,
      // the summary bubble only km and minutes, both on the same key.
      final client = testQueryClient();
      final key = queryKey();
      var calls = 0;

      Future<Route> fetch() async {
        calls++;
        return const Route(110000.0, 5400.0);
      }

      final full = QueryObserver<Route, Object?, Route>(
        client,
        QueryOptions<Route>(
            queryKey: key, queryFn: fetch, staleTime: double.infinity),
      );
      final summary = QueryObserver<Route, Object?, Summary>(
        client,
        QueryObserverOptions<Route, Summary>(
          queryKey: key,
          queryFn: fetch,
          select: _toSummary,
          staleTime: double.infinity,
        ),
      );
      addTearDown(full.destroy);
      addTearDown(summary.destroy);

      final unsubA = full.subscribe((_) {});
      final unsubB = summary.subscribe((_) {});
      await tester.pump(const Duration(milliseconds: 10));

      expect(calls, 1);
      expect(full.getCurrentResult().data, isA<Route>());
      expect(summary.getCurrentResult().data, const Summary(110.0, 90));
      unsubA();
      unsubB();
    });

    testWidgets('a throwing select surfaces as an errored result',
        (tester) async {
      final client = testQueryClient();
      final key = queryKey();

      final observer = QueryObserver<String, Object?, int>(
        client,
        QueryObserverOptions<String, int>(
          queryKey: key,
          queryFn: () async => 'not a number',
          select: (s) => int.parse(s),
        ),
      );
      addTearDown(observer.destroy);

      final unsubscribe = observer.subscribe((_) {});
      await tester.pump(const Duration(milliseconds: 10));

      final result = observer.getCurrentResult();
      expect(result.status, QueryStatus.error);
      expect(result.error, isA<FormatException>());
      unsubscribe();
    });

    testWidgets(
        'select runs once per payload, and its result keeps its identity',
        (tester) async {
      final client = testQueryClient();
      final key = queryKey();
      var selectCalls = 0;

      Summary select(Route r) {
        selectCalls++;
        return _toSummary(r);
      }

      final observer = QueryObserver<Route, Object?, Summary>(
        client,
        QueryObserverOptions<Route, Summary>(
          queryKey: key,
          queryFn: () async => const Route(110000.0, 5400.0),
          select: select,
          staleTime: double.infinity,
        ),
      );
      addTearDown(observer.destroy);

      final unsubscribe = observer.subscribe((_) {});
      await tester.pump(const Duration(milliseconds: 10));
      final afterFetch = selectCalls;
      final first = observer.getCurrentResult().data;

      // Same cached payload, same select function: memoized on both identities.
      client.queryCache.getQuery(queryKeyToCacheKey(key))!.notifyObservers();
      await tester.pump(const Duration(milliseconds: 10));

      expect(selectCalls, afterFetch);
      expect(observer.getCurrentResult().data, same(first));
      unsubscribe();
    });
  });
}
