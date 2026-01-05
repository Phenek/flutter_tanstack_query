---
id: queries
title: Queries
---

## Query Basics

A query is a declarative dependency on an asynchronous source of data that is tied to a **unique key**. A query can be used with any Promise based method (including GET and POST methods) to fetch data from a server. If your method modifies data on the server, we recommend using [Mutations](./09-mutations.md) instead.

To subscribe to a query in your components or custom hooks, call the `useQuery` hook with at least:

- A **unique key for the query**
- A function that returns a promise that:
  - Resolves the data, or
  - Throws an error

[//]: # 'Example'

```dart
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter/material.dart';

class App extends HookWidget {
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final info = useQuery<List<dynamic>>(queryKey: ['todos'], queryFn: fetchTodoList);
    return const SizedBox.shrink();
  }
}
```

[//]: # 'Example' 

The **unique key** you provide is used internally for refetching, caching, and sharing your queries throughout your application.

The query result returned by `useQuery` contains all of the information about the query that you'll need for templating and any other usage of the data:

[//]: # 'Example2'

```dart
final result = useQuery<List<dynamic>>(queryKey: ['todos'], queryFn: fetchTodoList);
```

[//]: # 'Example2' 

The `result` object contains a few very important states you'll need to be aware of to be productive. A query can only be in one of the following states at any given moment:

- `isPending` or `status == QueryStatus.pending` - The query has no data yet
- `isError` or `status == QueryStatus.error` - The query encountered an error
- `isSuccess` or `status == QueryStatus.success` - The query was successful and data is available

Beyond those primary states, more information is available depending on the state of the query:

- `error` - If the query is in an `isError` state, the error is available via the `error` property.
- `data` - If the query is in an `isSuccess` state, the data is available via the `data` property.
- `isFetching` - In any state, if the query is fetching at any time (including background refetching) `isFetching` will be `true`.

For **most** queries, it's usually sufficient to check for the `isPending` state, then the `isError` state, then finally, assume that the data is available and render the successful state:

[//]: # 'Example3'

```dart
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter/material.dart';

class TodosWidget extends HookWidget {
  const TodosWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final result = useQuery<List<dynamic>>(queryKey: ['todos'], queryFn: fetchTodoList);

    final isPending = result.isPending;
    final isError = result.isError;
    final error = result.error;
    final data = result.data;

    if (isPending) {
      return const Center(child: Text('Loading...'));
    }

    if (isError) {
      return Center(child: Text('Error: ${error ?? 'unknown'}'));
    }

    final todos = data ?? [];

    return ListView(
      children: todos.map((todo) {
        return ListTile(title: Text(todo['title'] ?? ''));
      }).toList(),
    );
  }
}
```

[//]: # 'Example3' 

If booleans aren't your thing, you can always use the `status` state as well:

[//]: # 'Example4'

```dart
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'package:flutter/material.dart';

class TodosStatusWidget extends HookWidget {
  const TodosStatusWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final result = useQuery<List<dynamic>>(queryKey: ['todos'], queryFn: fetchTodoList);

    final status = result.status;
    final data = result.data;
    final error = result.error;

    if (status == QueryStatus.pending) {
      return const Center(child: Text('Loading...'));
    }

    if (status == QueryStatus.error) {
      return Center(child: Text('Error: ${error ?? 'unknown'}'));
    }

    final todos = data ?? [];

    return ListView(
      children: todos.map((todo) => ListTile(title: Text(todo['title'] ?? ''))).toList(),
    );
  }
}
```

[//]: # 'Example4'

TypeScript will also narrow the type of `data` correctly if you've checked for `pending` and `error` before accessing it.


### Why two different states?

Background refetches and stale-while-revalidate logic make different combinations for `status` and `isFetching` possible. For example:

- a query in `success` status will usually have `isFetching == false`, but it could also have `isFetching == true` if a background refetch is happening.
- a query that mounts and has no data will usually be in `pending` status and `isFetching == true` while the initial fetch runs.

So keep in mind that a query can be in `pending` state without actually fetching data (e.g., when disabled). As a rule of thumb:

- The `status` gives information about the `data`: Do we have any or not?
- The `isFetching` boolean gives information about the `queryFn`: Is it running or not?

[//]: # 'Materials'

## Further Reading

For an alternative way of performing status checks, have a look at [this article by TkDodo](https://tkdodo.eu/blog/status-checks-in-react-query).

[//]: # 'Materials'
