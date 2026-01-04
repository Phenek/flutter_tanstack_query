---
id: installation
title: Installation
---

You can install Flutter TanStack Query from [pub.dev](https://pub.dev/packages/tanstack_query).

### Pub.dev

To add the package to your app, run:

```bash
flutter pub add tanstack_query
```

or, with the lower-level Dart tool:

```bash
dart pub add tanstack_query
```

Alternatively add it manually to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  tanstack_query: ^x.y.z # replace with desired version
```

Then import it in your Dart code:

```dart
import 'package:tanstack_query/tanstack_query.dart';
```

### Requirements

Flutter TanStack Query is built for Flutter apps and works with the stable Flutter SDK. Ensure your Flutter SDK is up to date (we recommend using the latest stable channel).

> Note: Depending on your app you'll likely also want packages for HTTP requests such as `http` or `dio`, and `flutter_hooks` if you want to use hook-style widgets.

### Recommendations

- Read the full API reference and examples in this docs site for usage patterns and best practices.
- Consider using `flutter_hooks` if you prefer HookWidgets and `http`/`dio` for request implementations.
- For contributions, bug reports, or to see more examples, visit the project repository and the package page on pub.dev: https://pub.dev/packages/tanstack_query
