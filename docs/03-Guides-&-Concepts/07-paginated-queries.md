---
id: paginated-queries
title: Paginated / Lagged Queries
---

Rendering paginated data is a very common UI pattern and in TanStack Query, it "just works" by including the page information in the query key:

[//]: # 'Example'

```dart
final result = useQuery(
  queryKey: ['projects', page],
  queryFn: () => fetchProjects(page),
);
```

[//]: # 'Example'

However, if you run this simple example, you might notice something strange:

**The UI jumps in and out of the `success` and `pending` states because each new page is treated like a brand new query.**

This experience is not optimal and unfortunately is how many tools today insist on working. But not TanStack Query! As you may have guessed, TanStack Query comes with an awesome feature called `placeholderData` that allows us to get around this.

## Better Paginated Queries with `placeholderData`

Consider the following example where we would ideally want to increment a pageIndex (or cursor) for a query. If we were to use `useQuery`, **it would still technically work fine**, but the UI would jump in and out of the `success` and `pending` states as different queries are created and destroyed for each page or cursor. By setting `placeholderData` to `(previousData) => previousData` or `keepPreviousData` function exported from TanStack Query, we get a few new things:

- **The data from the last successful fetch is available while new data is being requested, even though the query key has changed**.
- When the new data arrives, the previous `data` is seamlessly swapped to show the new data.
- `isPlaceholderData` is made available to know what data the query is currently providing you

[//]: # 'Example2'

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:http/http.dart' as http;
import 'package:tanstack_query/tanstack_query.dart';

class TodosPage extends HookWidget {
  const TodosPage({Key? key}) : super(key: key);

  Future<Map<String, dynamic>> fetchProjects(int page) async {
    final res = await http.get(Uri.parse('/api/projects?page=$page'));
    return json.decode(res.body) as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final page = useState<int>(0);

    final result = useQuery<Map<String, dynamic>>(
      queryKey: ['projects', page.value],
      queryFn: () => fetchProjects(page.value),
      placeholderData: (prev) => prev,
    );

    final isPending = result.isPending;
    final isError = result.isError;
    final error = result.error;
    final data = result.data;
    final isFetching = result.isFetching;
    final isPlaceholderData = result.isPlaceholderData;

    if (isPending) {
      return const Center(child: Text('Loading...'));
    }

    if (isError) {
      return Center(child: Text('Error: ${error ?? 'unknown'}'));
    }

    final projects = (data?['projects'] as List?) ?? [];

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: projects.length,
            itemBuilder: (ctx, i) {
              final project = projects[i] as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Text(project['name'] ?? ''),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Current Page: ${page.value + 1}'),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: page.value == 0 ? null : () => page.value = (page.value - 1).clamp(0, 9999),
                child: const Text('Previous Page'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: (!isPlaceholderData && (data?['hasMore'] == true)) ? () => page.value = page.value + 1 : null,
                child: const Text('Next Page'),
              ),
            ],
          ),
        ),
        if (isFetching) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Loading...')),
      ],
    );
  }
}
```

[//]: # 'Example2'

## Lagging Infinite Query results with `placeholderData`

While not as common, the `placeholderData` option also works flawlessly with the `useInfiniteQuery` hook, so you can seamlessly allow your users to continue to see cached data while infinite query keys change over time.
