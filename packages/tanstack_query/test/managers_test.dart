import 'package:flutter_test/flutter_test.dart';
import 'package:tanstack_query/tanstack_query.dart';

void main() {
  setUp(() {
    // ensure a known baseline state
    focusManager.setFocused(true);
    onlineManager.setOnline(true);
  });

  test('FocusManager should notify subscribers on setFocused and onFocus', () {
    final calls = <bool>[];
    final unsubscribe = focusManager.subscribe((focused) {
      calls.add(focused);
    });

    // toggle focus
    focusManager.setFocused(false);
    expect(calls.isNotEmpty, true);
    expect(calls.last, equals(false));

    focusManager.setFocused(true);
    expect(calls.last, equals(true));

    // direct onFocus should invoke listeners with current state
    focusManager.onFocus();
    expect(calls.last, equals(true));

    unsubscribe();
  });

  test('OnlineManager should notify subscribers on setOnline', () {
    final calls = <bool>[];
    final unsubscribe = onlineManager.subscribe((online) {
      calls.add(online);
    });

    onlineManager.setOnline(false);
    expect(calls.isNotEmpty, true);
    expect(calls.last, equals(false));

    onlineManager.setOnline(true);
    expect(calls.last, equals(true));

    unsubscribe();
  });
}
