---
id: QueryClientProvider
title: QueryClientProvider
---

Use the `QueryClientProvider` component to connect and provide a `QueryClient` to your application:

```dart
import 'package:tanstack_query/tanstack_query.dart';

var queryClient = QueryClient();

runApp(
  QueryClientProvider(client: queryClient, child: const App()),
);
```

**Options**

- `client: QueryClient`
  - **Required**
  - the QueryClient instance to provide
