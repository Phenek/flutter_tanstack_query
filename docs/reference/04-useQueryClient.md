---
id: useQueryClient
title: useQueryClient
---

The `useQueryClient` hook returns the current `QueryClient` instance.

```dart
import 'package:tanstack_query/tanstack_query.dart';

// Returns the `QueryClient` from the nearest provider or the optional one passed
final queryClient = useQueryClient();
```

**Options**

- `queryClient?: QueryClient`
  - Use this to use a custom QueryClient. Otherwise, the one from the nearest context will be used.

## Imperative API

Everything below is also callable outside the widget tree — a service reacting to a notifier, a
navigation side effect — because none of it needs an observer. The key is what ties an imperative
call to a mounted `useQuery`: same key, same cache entry, and a fetch already in flight is joined
instead of duplicated.

```dart
// Read
final data = queryClient.getQueryData<List<Station>>(['stations']);
final result = queryClient.getQueryState<List<Station>>(['stations']);
final all = queryClient.getQueriesData<List<Station>>(queryKey: ['stations']); // [QueryDataEntry(key, data)]

// Write
queryClient.setQueryData<List<Station>>(['stations'], (old) => next); // updater; null writes nothing
queryClient.setQueryDataValue<List<Station>>(['stations'], value);    // plain value, like the JS updater

// Fetch
await queryClient.fetchQuery(queryKey: key, queryFn: fetch);            // retry: false unless a default sets it
await queryClient.prefetchQuery(queryKey: key, queryFn: fetch);         // error swallowed
await queryClient.ensureQueryData(queryKey: key, queryFn: fetch);       // cached data, else fetchQuery
await queryClient.ensureQueryData(queryKey: key, queryFn: fetch, revalidateIfStale: true);
await queryClient.fetchInfiniteQuery(...);   // + prefetchInfiniteQuery / ensureInfiniteQueryData

// Defaults per key prefix: every ['ors', ...] query gets this staleTime unless it says otherwise
queryClient.setQueryDefaults(['ors'], const QueryDefaults(staleTime: 300000));
queryClient.getQueryDefaults(['ors', 'route']);

// Lifecycle
queryClient.removeQueries(queryKey: ['stations']);
queryClient.resetQueries(queryKey: ['stations']); // clears, then refetches active queries
// Keys are matched element by element: ['todos', 1] never touches ['todos', 11].
// `exact: true` restricts the match to that key alone.
```
