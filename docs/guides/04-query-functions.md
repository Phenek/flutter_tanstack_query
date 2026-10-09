---
id: query-functions
title: Query Functions
---

A query function can be literally any function that **returns a promise**. The promise that is returned should either **resolve the data** or **throw an error**.

All of the following are valid query function configurations:

[//]: # 'Example'

```dart
// Simple usage
useQuery<List<dynamic>>(queryKey: ['todos'], queryFn: fetchAllTodos);

// Passing parameters via a closure
useQuery<Map<String, dynamic>>(queryKey: ['todos', todoId], queryFn: () => fetchTodoById(todoId));

// Async closure
useQuery<Map<String, dynamic>>(
  queryKey: ['todos', todoId],
  queryFn: () async {
    final data = await fetchTodoById(todoId);
    return data;
  },
);

// If you prefer to extract variables from a structured query key, create a helper:
Future<Map<String, dynamic>> fetchTodoByQueryKey(List<Object> key) async {
  final params = key[1] as Map<String, dynamic>;
  final id = params['id'];
  return fetchTodoById(id);
}

useQuery<Map<String, dynamic>>(
  queryKey: ['todos', {'id': todoId}],
  queryFn: () => fetchTodoByQueryKey(['todos', {'id': todoId}]),
);
```

[//]: # 'Example' 

## Handling and Throwing Errors

For TanStack Query to determine a query has errored, the query function **must throw** or return a **rejected Promise**. Any error that is thrown in the query function will be persisted on the `error` state of the query.

[//]: # 'Example2'

```dart
final result = useQuery<Map<String, dynamic>>(
  queryKey: ['todos', todoId],
  queryFn: () async {
    if (somethingGoesWrong) {
      throw Exception('Oh no!');
    }
    if (somethingElseGoesWrong) {
      throw Exception('Oh no!');
    }
    return data;
  },
);

final error = result.error;
```

[//]: # 'Example2' 

## Usage with `fetch` and other clients that do not throw by default

While most utilities like `axios` or `graphql-request` automatically throw errors for unsuccessful HTTP calls, some utilities like `fetch` do not throw errors by default. If that's the case, you'll need to throw them on your own. Here is a simple way to do that with the popular `fetch` API:

[//]: # 'Example3'

```dart
useQuery<Map<String, dynamic>>(
  queryKey: ['todos', todoId],
  queryFn: () async {
    final response = await http.get(Uri.parse('/todos/$todoId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Network response was not ok');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  },
);
```

[//]: # 'Example3' 

## Query Function Variables

Query keys are not just for uniquely identifying the data you are fetching, but are also conveniently passed into your query function as part of the QueryFunctionContext. While not always necessary, this makes it possible to extract your query functions if needed:

[//]: # 'Example4'

```dart
// Use a structured key to pass variables to your queryFn via closure or a helper.
final result = useQuery<List<dynamic>>(
  queryKey: ['todos', {'status': status, 'page': page}],
  queryFn: () => fetchTodoList(status: status, page: page),
);

// Or extract variables from the key explicitly with a helper:
Future<List<dynamic>> fetchTodoListFromKey(List<Object> queryKey) async {
  final params = queryKey[1] as Map<String, dynamic>;
  final status = params['status'];
  final page = params['page'];
  // fetch using status and page
  return [];
}

final result2 = useQuery<List<dynamic>>(
  queryKey: ['todos', {'status': status, 'page': page}],
  queryFn: () => fetchTodoListFromKey(['todos', {'status': status, 'page': page}]),
);
```

[//]: # 'Example4'