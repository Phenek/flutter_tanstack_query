---
id: useQueryClient
title: useQueryClient
---

The `useQueryClient` hook returns the current `QueryClient` instance.

```dart
import 'package:tanstack_query/tanstack_query.dart';

// Returns the `QueryClient` from the nearest provider or the optional one passed
final queryClient = useQueryClient();
```

**Options**

- `queryClient?: QueryClient`
  - Use this to use a custom QueryClient. Otherwise, the one from the nearest context will be used.
