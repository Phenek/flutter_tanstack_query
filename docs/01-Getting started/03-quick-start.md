---
id: quick-start
title: Quick Start
---

This code snippet very briefly illustrates the 3 core concepts of React Query:

- [Queries](../03-Guides-&-Concepts/02-queries.md)
- [Mutations](../03-Guides-&-Concepts/09-mutations.md)
- [Query Invalidation](../03-Guides-&-Concepts/10-query-invalidation.md)

[//]: # 'Example' 

If you're looking for a fully functioning example, please have a look at our [simple example](https://github.com/Phenek/flutter_tanstack_query/tree/main/packages/tanstack_query/example)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'dart:async';
import 'package:example/conf/my_api_conf.dart';

// Create a client
final queryClient = QueryClient();

void main() {
  runApp(
    QueryClientProvider(client: queryClient, child: const App()),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Todos())),
    );
  }
}

class Todos extends HookWidget {
  const Todos({super.key});

  @override
  Widget build(BuildContext context) {
    // Access the client
    final qc = useQueryClient();

    // Queries
    final query = useQuery<List<Map<String, dynamic>>>(
      queryKey: ['todos'],
      queryFn: getTodos,
    );

    // Mutations
    final mutation = useMutation<Map<String, dynamic>, Map<String, dynamic>>(
      mutationFn: postTodo,
      onSuccess: (_) {
        // Invalidate and refetch
        qc.invalidateQueries(queryKey: ['todos']);
      },
    );

    if (query.isPending) return const CircularProgressIndicator();

    if (query.error != null) {
      return Text('An error has occurred: ${query.error}');
    }

    final todos = query.data ?? [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 200,
          child: ListView.builder(
            itemCount: todos.length,
            itemBuilder: (_, i) => ListTile(title: Text(todos[i]['title'])),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () {
            mutation.mutate({
              'id': DateTime.now().millisecondsSinceEpoch,
              'title': 'Do Laundry',
            });
          },
          child: const Text('Add Todo'),
        ),
      ],
    );
  }
}
```

[//]: # 'Example'

These three concepts make up most of the core functionality of React Query. The next sections of the documentation will go over each of these core concepts in great detail.
