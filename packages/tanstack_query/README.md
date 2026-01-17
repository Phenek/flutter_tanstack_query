![Flutter TanStack Query](https://github.com/Phenek/flutter_tanstack_query/blob/main/media/header_query.jpg?raw=true)

[![Pub](https://img.shields.io/pub/v/tanstack_query.svg)](https://pub.dev/packages/tanstack_query)
[![Pub points](https://img.shields.io/pub/points/tanstack_query.svg)](https://pub.dev/packages/tanstack_query/score)
[![Likes](https://img.shields.io/pub/likes/tanstack_query.svg)](https://pub.dev/packages/tanstack_query)

# 🏖️ Flutter TanStack Query

This package provides a Flutter implementation of the query/cache patterns used by
[tanstack/react-query v5](https://tanstack.com/query/latest/docs/framework/react/overview).

Flutter TanStack Query is maintained by independent Flutter developers and is not affiliated with the official TanStack team. This librairy and documentation is a COPY CAT as it closely follows TanStack Query's API architecture and design, and intentionally mirrors every aspects of the JavaScript library.

An async state management library built to simplify fetching, caching, synchronizing, and updating server state.

- Protocol‑agnostic fetching (REST, GraphQL, promises, etc.)
- Caching, refetching, pagination & infinite scroll
- Mutations, dependent queries & background updates
- Prefetching, cancellation & React Suspense support

### <a href="https://flutter-tanstack.com">Read the docs →</b></a>


## Key concepts
- QueryClient — the root object that owns the cache and global defaults.
- QueryCache / MutationCache — caches owned by the core that can broadcast errors/success globally.
- useQuery / useInfiniteQuery / useMutation — Flutter hooks to interact with the cache from widgets.

## Getting started

Instantiate a basic `QueryClient` for your app. Example:

```dart
void main() {
  var queryClient = QueryClient(
    defaultOptions: const DefaultOptions(
      queries: QueryDefaultOptions(
        enabled: true,
        staleTime: 0,
        refetchOnWindowFocus: false,
        refetchOnReconnect: false,
      ),
    ),
    queryCache: QueryCache(
      config: QueryCacheConfig(onError: (e) => debugPrint(e.toString())),
    ),
    mutationCache: MutationCache(
      config: MutationCacheConfig(onError: (e, [context]) => debugPrint(e.toString())),
    ),
  );

  runApp(
    QueryClientProvider(client: queryClient, child: const App()),
  );
}
```
Example: Queries, Mutations and Invalidation (tanstack style)

This short example demonstrates the three core concepts used by React Query:
Queries, Mutations and Query Invalidation. It uses `useQuery` to fetch todos,
`useMutation` to add a todo, and `queryClient.invalidateQueries` to
refetch after a successful mutation.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';

// Fake API helpers used in the example. Replace with your real networking code.
Future<List<Map<String, dynamic>>> getTodos() async {
  await Future.delayed(Duration(milliseconds: 150));
  return [
    {'id': 1, 'title': 'Buy milk'},
    {'id': 2, 'title': 'Walk dog'},
  ];
}

Future<Map<String, dynamic>> postTodo(Map<String, dynamic> todo) async {
  await Future.delayed(Duration(milliseconds: 150));
  return todo; // in a real app you'd POST and return the created item
}

class Todos extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final queryClient = useQueryClient();
    // Queries
    final todosQuery = useQuery<List<Map<String, dynamic>>>(
      queryKey: ['todos'],
      queryFn: getTodos,
    );

    // Mutations
    final addTodoMutation = useMutation(
      mutationFn: postTodo,
      onSuccess: (_) {
        // Invalidate and refetch the todos query after successful mutation
        queryClient.invalidateQueries(queryKey: ['todos']);
      },
    );

    if (todosQuery.isPending) return const Center(child: Text('Loading...'));
    if (todosQuery.isError) return Center(child: Text('Error: ${todosQuery.error}'));

    final todos = todosQuery.data ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Todos')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: todos.map((t) => ListTile(title: Text(t['title'] ?? ''))).toList(),
              ),
            ),
            ElevatedButton(
              child: const Text('Add Todo'),
              onPressed: () {
                addTodoMutation.mutate({'id': DateTime.now().millisecondsSinceEpoch, 'title': 'Do Laundry'});
              },
            )
          ],
        ),
      ),
    );
  }
}
```

## Other useful API notes
- QueryClient provides helper methods like `invalidateQueries` and `clear` to trigger refetches or wipe cache.
- The core `query_core` package contains `DefaultOptions`, `QueryCacheConfig` and `MutationCacheConfig` types.

## Further reading
- React Query (tanstack) docs: https://tanstack.com/query/latest/docs
- See the `packages/tanstack_query/example` folder for end-to-end examples.



## Refetching on focus and reconnect 🔁

When a query is marked with `refetchOnWindowFocus`, `refetchOnMount` or `refetchOnReconnect`, the library will call the query's `refetch` callback when those events happen if the option is `true` (the defaults).

The app is responsible for wiring lifecycle and connectivity events to the exported managers (`focusManager` and `onlineManager`). `QueryClientProvider` will mount the client to listen to those managers when present.

- App focus (window / app active)
Use an app lifecycle listener and set the focus manager accordingly:

Example:
```dart
WidgetsFlutterBinding.ensureInitialized();

AppLifecycleListener(onResume: () {
  focusManager.setFocused(true);
}, onInactive: () {
  focusManager.setFocused(false);
}, onPause: () {
  focusManager.setFocused(false);
});
```

- Connectivity monitoring (reconnect)
Listen to your connectivity provider and update the online manager:

Example (internet_connection_checker_plus):
```dart
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:tanstack_query/tanstack_query.dart';

InternetConnection connectivity = InternetConnection();

connectivity.onStatusChange.listen((status) {
  if (status == InternetStatus.connected) {
    onlineManager.setOnline(true);
  } else {
    onlineManager.setOnline(false);
  }
});
```

### Notes
- Ensure each query's options (or default options) enable the desired `refetchOnWindowFocus`, `refetchOnMount` and `refetchOnReconnect` behaviors.
- You can still trigger refetches manually with `QueryClient` helper methods, but wiring the managers as shown keeps the behavior automatic and platform-agnostic.
