---
id: query-retries
title: Query Retries
---

When a `useQuery` query fails (the query function throws an error), TanStack Query will automatically retry the query if that query's request has not reached the max number of consecutive retries (defaults to `3`) or a function is provided to determine if a retry is allowed.

You can configure retries both on a global level and an individual query level.

- Setting `retry = false` will disable retries.
- Setting `retry = 6` will retry failing requests 6 times before showing the final error thrown by the function.
- Setting `retry = true` will infinitely retry failing requests.
- Setting `retry = (failureCount, error) => ...` allows for custom logic based on why the request failed.

[//]: # 'Info'

> On the server, retries default to `0` to make server rendering as fast as possible.

[//]: # 'Info'
[//]: # 'Example'

```dart
// Make a specific query retry a certain number of times
final result = useQuery<List<dynamic>>(
  queryKey: ['todos', 1],
  queryFn: fetchTodoListPage,
  retry: 10, // Will retry failed requests 10 times before displaying an error
);
```

[//]: # 'Example'

> Info: Contents of the `error` property will be part of `failureReason` response property of `useQuery` until the last retry attempt. So in above example any error contents will be part of `failureReason` property for first 9 retry attempts (Overall 10 attempts) and finally they will be part of `error` after last attempt if error persists after all retry attempts.

## Retry Delay

By default, retries in TanStack Query do not happen immediately after a request fails. As is standard, a back-off delay is gradually applied to each retry attempt.

The default `retryDelay` is set to double (starting at `1000`ms) with each attempt, but not exceed 30 seconds:

[//]: # 'Example2'

```dart
// Configure for all queries
import 'dart:math' as math;

final queryClient = QueryClient(
  defaultOptions: DefaultOptions(
    queries: QueryDefaultOptions(
      retryDelay: (attemptIndex) => math.min(1000 * (1 << attemptIndex), 30000),
    ),
  ),
);

// Use QueryClientProvider in your app to provide the client to hooks/widgets
// Example placeholder:
// QueryClientProvider(client: queryClient, child: RestOfApp())
```

[//]: # 'Example2'

Though it is not recommended, you can obviously override the `retryDelay` function/integer in both the Provider and individual query options. If set to an integer instead of a function the delay will always be the same amount of time:

[//]: # 'Example3'

```dart
final result = useQuery<List<dynamic>>(
  queryKey: ['todos'],
  queryFn: fetchTodoList,
  retryDelay: 1000, // Will always wait 1000ms to retry, regardless of how many retries
);
```

[//]: # 'Example3'
