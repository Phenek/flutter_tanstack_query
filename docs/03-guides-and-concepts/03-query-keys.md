---
id: query-keys
title: Query Keys
---

At its core, TanStack Query manages query caching for you based on query keys. Query keys have to be an Array at the top level, and can be as simple as an Array with a single string, or as complex as an array of many strings and nested objects. As long as the query key is serializable using `JSON.stringify`, and **unique to the query's data**, you can use it!

## Simple Query Keys

The simplest form of a key is an array with constants values. This format is useful for:

- Generic List/Index resources
- Non-hierarchical resources

[//]: # 'Example'

```dart
// A list of todos
useQuery<List<dynamic>>(queryKey: ['todos'], queryFn: fetchTodoList);

// Something else, whatever!
useQuery<Map<String, dynamic>>(queryKey: ['something', 'special'], queryFn: fetchSomethingSpecial);
```

[//]: # 'Example' 

## Array Keys with variables

When a query needs more information to uniquely describe its data, you can use an array with a string and any number of serializable objects to describe it. This is useful for:

- Hierarchical or nested resources
  - It's common to pass an ID, index, or other primitive to uniquely identify the item
- Queries with additional parameters
  - It's common to pass an object of additional options

[//]: # 'Example2'

```dart
// An individual todo
useQuery<Map<String, dynamic>>(queryKey: ['todo', 5], queryFn: () => fetchTodoById(5));

// An individual todo in a "preview" format
useQuery<Map<String, dynamic>>(queryKey: ['todo', 5, {'preview': true}], queryFn: () => fetchTodoPreviewById(5));

// A list of todos that are "done"
useQuery<List<dynamic>>(queryKey: ['todos', {'type': 'done'}], queryFn: () => fetchTodos(type: 'done'));
```

[//]: # 'Example2' 

## Query Keys are hashed deterministically!

This means that no matter the order of keys in objects, all of the following queries are considered equal:

[//]: # 'Example3'

```dart
useQuery<List<dynamic>>(queryKey: ['todos', {'status': status, 'page': page}], queryFn: () => fetchTodoList(status: status, page: page));
useQuery<List<dynamic>>(queryKey: ['todos', {'page': page, 'status': status}], queryFn: () => fetchTodoList(status: status, page: page));
useQuery<List<dynamic>>(queryKey: ['todos', {'page': page, 'status': status, 'other': null}], queryFn: () => fetchTodoList(status: status, page: page));
```

[//]: # 'Example3' 

The following query keys, however, are not equal. Array item order matters!

[//]: # 'Example4'

```dart
useQuery<List<dynamic>>(queryKey: ['todos', status, page], queryFn: () => fetchTodoList(status: status, page: page));
useQuery<List<dynamic>>(queryKey: ['todos', page, status], queryFn: () => fetchTodoList(status: status, page: page));
useQuery<List<dynamic>>(queryKey: ['todos', null, page, status], queryFn: () => fetchTodoList(status: status, page: page));
```

[//]: # 'Example4' 

## If your query function depends on a variable, include it in your query key

Since query keys uniquely describe the data they are fetching, they should include any variables you use in your query function that **change**. For example:

[//]: # 'Example5'

```dart
class TodosWidget extends HookWidget {
  final int todoId;
  const TodosWidget({required this.todoId});

  @override
  Widget build(BuildContext context) {
    final result = useQuery<Map<String, dynamic>>(queryKey: ['todos', todoId], queryFn: () => fetchTodoById(todoId));
    return const SizedBox.shrink();
  }
}
```

[//]: # 'Example5'