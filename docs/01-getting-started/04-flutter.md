---
id: flutter
title: Flutter
---

TanStack Query is designed to work out of the box with Flutter.

## Online status management

TanStack Query already supports auto refetch on reconnect in web browsers.
To add this behavior in Flutter, you can use the `onlineManager` with a connectivity package like `internet_connection_checker_plus`:

```dart
import 'package:tanstack_query/tanstack_query.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

void main() {
  var queryClient = QueryClient(
    defaultOptions: const DefaultOptions(
      queries: QueryDefaultOptions(
        enabled: true,
        staleTime: Duration.zero,
        refetchOnWindowFocus: true,
        refetchOnReconnect: true,
      ),
    ),
  );

  InternetConnection connectivity = InternetConnection();

  connectivity.onStatusChange.listen((status) {
    if (status == InternetStatus.connected) {
      onlineManager.setOnline(true);
    } else {
      onlineManager.setOnline(false);
    }
  });

  runApp(
    QueryClientProvider(client: queryClient, child: const MyApp()),
  );
}
```

## Refetch on App focus

Instead of event listeners on `window`, Flutter provides lifecycle information through the [`AppLifecycleListener`](https://api.flutter.dev/flutter/widgets/AppLifecycleListener-class.html). You can use the lifecycle callbacks to trigger updates when the app state changes to active:

```dart
import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  var queryClient = QueryClient(
    defaultOptions: const DefaultOptions(
      queries: QueryDefaultOptions(
        enabled: true,
        staleTime: Duration.zero,
        refetchOnWindowFocus: true,
      ),
    ),
  );

  AppLifecycleListener(
    onResume: () {
      focusManager.setFocused(true);
    },
    onInactive: () {
      focusManager.setFocused(false);
    },
    onPause: () {
      focusManager.setFocused(false);
    },
  );

  runApp(
    QueryClientProvider(client: queryClient, child: const MyApp()),
  );
}
```
