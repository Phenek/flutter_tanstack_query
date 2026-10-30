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

- `child: Widget`
  - **Required**
  - the subtree that can read the client with [`useQueryClient`](./04-useQueryClient.md)

## `QueryClientProvider.portal`

A widget built into an `Overlay` is not a descendant of the provider, so `useQueryClient()` finds
nothing and throws. This happens with a dragged `ReorderableListView` item, a `showDialog` builder,
or anything mounted through `Navigator`.

`QueryClientProvider.portal` re-exposes the client to such a subtree. Pass it a context that still
sees the provider — capture it in the enclosing `build`:

```dart
@override
Widget build(BuildContext context) {
  return ReorderableListView(
    // The dragged item builds under the Overlay: put the client back in scope.
    proxyDecorator: (child, index, animation) =>
        QueryClientProvider.portal(context, child: child),
    children: items,
  );
}
```

It only re-exposes the client: mounting stays owned by the real provider, so focus and online
subscriptions are never duplicated.
