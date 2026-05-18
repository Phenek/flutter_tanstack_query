---
id: disabling-queries
title: Disabling/Pausing Queries
---

If you ever want to disable a query from automatically running, you can use the `enabled = false` option. The enabled option also accepts a callback that returns a boolean.

When `enabled` is `false`:

- If the query has cached data, then the query will be initialized in the `status == QueryStatus.success` or `isSuccess` state.
- If the query does not have cached data, then the query will start in the `status == QueryStatus.pending` and `isFetching == false` state.
- The query will not automatically fetch on mount.
- The query will not automatically refetch in the background.
- The query will ignore query client `invalidateQueries` and `refetchQueries` calls that would normally result in the query refetching.
- `refetch` returned from `useQuery` can be used to manually trigger the query to fetch.

For Dart, prefer using `enabled` (for example `enabled: filter != null`) to control whether a query runs.

[//]: # 'Example'

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';

class Todo {
  final int id;
  final String title;

  Todo({required this.id, required this.title});
}

// Example fetch function (replace with your real API call)
Future<List<Todo>> fetchTodoList() async {
  await Future.delayed(const Duration(seconds: 1));
  return List.generate(3, (i) => Todo(id: i, title: 'Todo $i'));
}

class Todos extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final todosQuery = useQuery<List<Todo>>(
      queryKey: ['todos'],
      queryFn: () => fetchTodoList(),
      enabled: false,
    );

    final isLoading = todosQuery.isPending && todosQuery.isFetching;

    return Column(
      children: [
        ElevatedButton(
          onPressed: () {
            // refetch is nullable -> call it if available
            todosQuery.refetch?.call();
          },
          child: const Text('Fetch Todos'),
        ),
        if (todosQuery.data != null)
          Expanded(
            child: ListView(
              children: todosQuery.data!
                  .map((todo) => ListTile(title: Text(todo.title)))
                  .toList(),
            ),
          )
        else if (todosQuery.isError)
          Text('Error: ${todosQuery.error}')
        else if (isLoading)
          const Text('Loading...')
        else
          const Text('Not ready ...'),
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(todosQuery.isFetching ? 'Fetching...' : ''),
        ),
      ],
    );
  }
}
```

[//]: # 'Example'

Permanently disabling a query opts out of many great features that TanStack Query has to offer (like background refetches), and it's also not the idiomatic way. It takes you from the declarative approach (defining dependencies when your query should run) into an imperative mode (fetch whenever I click here). It is also not possible to pass parameters to `refetch`. Oftentimes, all you want is a lazy query that defers the initial fetch:

## Lazy Queries

The enabled option can not only be used to permanently disable a query, but also to enable / disable it at a later time. A good example would be a filter form where you only want to fire off the first request once the user has entered a filter value:

[//]: # 'Example2'

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';

// Reuse the Todo model and fetchTodos from earlier examples or define as needed
Future<List<Todo>> fetchTodos(String filter) async {
  await Future.delayed(const Duration(milliseconds: 500));
  return List.generate(3, (i) => Todo(id: i, title: 'Todo $i (filter: $filter)'));
}

class FiltersForm extends HookWidget {
  final void Function(String) onApply;
  const FiltersForm({required this.onApply});

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    return Row(
      children: [
        Expanded(child: TextField(controller: controller)),
        ElevatedButton(
          onPressed: () => onApply(controller.text),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class TodosWithFilter extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final filter = useState('');

    final todosQuery = useQuery<List<Todo>>(
      queryKey: ['todos', filter.value],
      queryFn: () => fetchTodos(filter.value),
      // ⬇️ disabled as long as the filter is empty
      enabled: filter.value.isNotEmpty,
    );

    return Column(
      children: [
        FiltersForm(onApply: (f) => filter.value = f),
        if (todosQuery.data != null)
          Expanded(
            child: ListView(
              children: todosQuery.data!
                  .map((t) => ListTile(title: Text(t.title)))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
```

[//]: # 'Example2'