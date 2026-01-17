---
id: mutations
title: Mutations
---

Unlike queries, mutations are typically used to create/update/delete data or perform server side-effects. For this purpose, TanStack Query exports a `useMutation` hook.

Here's an example of a mutation that adds a new todo to the server:

[//]: # 'Example'

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:http/http.dart' as http;

class CreateTodo extends HookWidget {
  const CreateTodo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mutation = useMutation<Map<String, dynamic>, Map<String, dynamic>>(
      mutationFn: (newTodo) async {
        final res = await http.post(
          Uri.parse('/todos'),
          body: jsonEncode(newTodo),
          headers: {'Content-Type': 'application/json'},
        );
        return jsonDecode(res.body) as Map<String, dynamic>;
      },
    );

    if (mutation.isPending) {
      return const Text('Adding todo...');
    }

    return Column(
      children: [
        if (mutation.isError) Text('An error occurred: ${mutation.error}'),
        if (mutation.isSuccess) const Text('Todo added!'),
        ElevatedButton(
          onPressed: () => mutation.mutate({'id': DateTime.now().toIso8601String(), 'title': 'Do Laundry'}),
          child: const Text('Create Todo'),
        ),
      ],
    );
  }
}
```

> Tip: `useMutation` accepts an optional `mutationKey` parameter (a `List<Object>`) that uniquely identifies the mutation. If provided, it will be serialized to a cache key string and made available through the `MutationFunctionContext` passed to lifecycle callbacks (`onMutate`, `onSuccess`, `onError`, `onSettled`).

[//]: # 'Example'

A mutation can only be in one of the following states at any given moment:

- `isIdle` or `status == MutationStatus.idle` - The mutation is currently idle or in a fresh/reset state
- `isPending` or `status == MutationStatus.pending` - The mutation is currently running
- `isError` or `status == MutationStatus.error` - The mutation encountered an error
- `isSuccess` or `status == MutationStatus.success` - The mutation was successful and mutation data is available

Beyond those primary states, more information is available depending on the state of the mutation:

- `error` - If the mutation is in an `error` state, the error is available via the `error` property.
- `data` - If the mutation is in a `success` state, the data is available via the `data` property.

In the example above, you also saw that you can pass variables to your mutations function by calling the `mutate` function with a **single variable or object**.

[//]: # 'Info1'

> IMPORTANT: The `mutate` function is an asynchronous function, which means you cannot use it directly in an event callback in **React 16 and earlier**. If you need to access the event in `onSubmit` you need to wrap `mutate` in another function. This is due to [React event pooling](https://reactjs.org/docs/legacy-event-pooling.html).

[//]: # 'Info1'
[//]: # 'Example2'

```dart
// In Flutter there's no React event pooling; you can call mutate directly from handlers.
class CreateTodoForm extends HookWidget {
  const CreateTodoForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mutation = useMutation<Map<String, dynamic>, Map<String, dynamic>>(
      mutationFn: (formData) async {
        final res = await http.post(
          Uri.parse('/api'),
          body: jsonEncode(formData),
          headers: {'Content-Type': 'application/json'},
        );
        return jsonDecode(res.body) as Map<String, dynamic>;
      },
    );

    void onSubmit(Map<String, dynamic> formData) {
      mutation.mutate(formData);
    }

    return Form(
      child: Column(
        children: [
          TextField(onSubmitted: (value) => onSubmit({'title': value})),
          ElevatedButton(onPressed: () => onSubmit({'title': 'Example'}), child: const Text('Submit')),
        ],
      ),
    );
  }
}
```

[//]: # 'Example2'

## Resetting Mutation State

It's sometimes the case that you need to clear the `error` or `data` of a mutation request. To do this, you can use the `reset` function to handle this:

[//]: # 'Example3'

```dart
class CreateTodoForm extends HookWidget {
  const CreateTodoForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final title = useState('');
    final mutation = useMutation<Map<String, dynamic>, Map<String, dynamic>>(
      mutationFn: (vars) async {
        final res = await http.post(Uri.parse('/api/todos'), body: jsonEncode(vars), headers: {'Content-Type': 'application/json'});
        return jsonDecode(res.body) as Map<String, dynamic>;
      },
    );

    void onCreateTodo() {
      mutation.mutate({'title': title.value});
    }

    return Form(
      child: Column(
        children: [
          if (mutation.error != null)
            GestureDetector(onTap: () => mutation.reset(), child: Text('${mutation.error}')),
          TextField(onChanged: (v) => title.value = v),
          ElevatedButton(onPressed: onCreateTodo, child: const Text('Create Todo')),
        ],
      ),
    );
  }
}
```

[//]: # 'Example3'

## Mutation Side Effects

`useMutation` comes with some helper options that allow quick and easy side-effects at any stage during the mutation lifecycle. These come in handy for both [invalidating and refetching queries after mutations](./10-query-invalidation.md) and even [optimistic updates](#optimistic-updates)

### Optimistic Updates

[//]: # 'Example4' 

```dart
useMutation<Map<String, dynamic>, Map<String, dynamic>>(
  mutationFn: addTodo,
  onMutate: () {
    // A mutation is about to happen!
    // Optionally prepare optimistic update
  },
  onError: (error) {
    // An error happened!
    print('rolling back optimistic update');
  },
  onSuccess: (data) {
    // Boom baby!
  },
  onSettled: (data, error) {
    // Error or success... doesn't matter!
  },
);
```

[//]: # 'Example4'

When returning a promise in any of the callback functions it will first be awaited before the next callback is called:

[//]: # 'Example5'

```dart
useMutation<Map<String, dynamic>, Map<String, dynamic>>(
  mutationFn: addTodo,
  onSuccess: (data) {
    print("I'm first!");
  },
  onSettled: (data, error) {
    print("I'm second!");
  },
);
```

[//]: # 'Example5'

You might find that you want to **trigger additional callbacks** beyond the ones defined on `useMutation` when calling `mutate`. This can be used to trigger component-specific side effects. To do that, you can provide any of the same callback options to the `mutate` function after your mutation variable. Supported options include: `onSuccess`, `onError` and `onSettled`. Please keep in mind that those additional callbacks won't run if your component unmounts _before_ the mutation finishes.

[//]: # 'Example6'

```dart
final mutation = useMutation<Map<String, dynamic>, Map<String, dynamic>>(
  mutationFn: addTodo,
  onSuccess: (data) {
    // I will fire first
  },
  onError: (error) {
    // I will fire first
  },
  onSettled: (data, error) {
    // I will fire first
  },
);

// Provide per-call callbacks via MutateOptions to mutateAsync
await mutation.mutateAsync(todo, MutateOptions(
  onSuccess: (data) {
    // I will fire second!
  },
  onError: (error) {
    // I will fire second!
  },
  onSettled: (data, error) {
    // I will fire second!
  },
));
```

[//]: # 'Example6'

### Consecutive mutations

There is a slight difference in handling `onSuccess`, `onError` and `onSettled` callbacks when it comes to consecutive mutations. When passed to the `mutate` function, they will be fired up only _once_ and only if the component is still mounted. This is due to the fact that mutation observer is removed and resubscribed every time when the `mutate` function is called. On the contrary, `useMutation` handlers execute for each `mutate` call.

> Be aware that most likely, `mutationFn` passed to `useMutation` is asynchronous. In that case, the order in which mutations are fulfilled may differ from the order of `mutate` function calls.

[//]: # 'Example7'

```dart
useMutation<Map<String, dynamic>, String>(
  mutationFn: addTodo,
  onSuccess: (data) {
    // Will be called 3 times
  },
);

final todos = ['Todo 1', 'Todo 2', 'Todo 3'];
for (final todo in todos) {
  // Per-call callbacks can be passed to mutateAsync
  mutation.mutateAsync(todo, MutateOptions(
    onSuccess: (data) {
      // Will execute only once, for the last mutation (Todo 3),
      // regardless which mutation resolves first
    },
  ));
}
```

[//]: # 'Example7'

## Promises

Use `mutateAsync` instead of `mutate` to get a promise which will resolve on success or throw on an error. This can for example be used to compose side effects.

[//]: # 'Example8'

```dart
final mutation = useMutation<Map<String, dynamic>, Map<String, dynamic>>(mutationFn: addTodo);

try {
  final todo = await mutation.mutateAsync({'title': 'Do Laundry'});
  print(todo);
} catch (error) {
  print(error);
} finally {
  print('done');
}
```

[//]: # 'Example8'

## Retry

By default, TanStack Query will not retry a mutation on error, but it is possible with the `retry` option:

[//]: # 'Example9'

```dart
final mutation = useMutation<Map<String, dynamic>, Map<String, dynamic>>(
  mutationFn: addTodo,
  retry: 3,
);
```

[//]: # 'Example9'

If mutations fail because the device is offline, they will be retried in the same order when the device reconnects.

## Persist mutations

Mutations can be persisted to storage if needed and resumed at a later point. This can be done with the hydration functions:

[//]: # 'Example10'

```dart
final queryClient = QueryClient(
  mutationCache: MutationCache(
    config: MutationCacheConfig(
      onMutate: () {
        // Cancel current queries for the todos list
        // Create optimistic todo
        // Add optimistic todo to todos list via queryClient.setQueryInfiniteData / setQueryData
      },
      onSuccess: (result) {
        // Replace optimistic todo in the todos list with the result
      },
      onError: (error) {
        // Remove optimistic todo from the todos list
      },
    ),
  ),
);

// Start mutation in some component:
final mutation = useMutation<Map<String, dynamic>, Map<String, dynamic>>(mutationFn: addTodo);
mutation.mutate({'title': 'title'});

// Note: Dehydrate / hydrate APIs and resumePausedMutations may differ in Dart; use equivalent helpers if available.
```

[//]: # 'Example10'