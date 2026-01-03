import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

void main() {
  late QueryClient client;

  setUp(() {
    client = QueryClient();
    client.mutationCache.clear();
  });

  test('MutationObserver notifies listeners and calls callbacks', () async {
    String? successData;
    final observer = MutationObserver<String, String>(
      client,
      MutationOptions<String, String>(
        mutationFn: (p) async {
          await Future.delayed(Duration(milliseconds: 10));
          return 'ok';
        },
        onSuccess: (d) => successData = d,
      ),
    );

    final events = <MutationStatus>[];
    final unsubscribe = observer.subscribe((res) {
      events.add(res.status);
    });

    final future = observer.mutate('p');
    // pending should appear
    expect(events.contains(MutationStatus.pending), true);

    final data = await future;
    expect(data, equals('ok'));
    expect(successData, equals('ok'));

    unsubscribe();
  });
}
