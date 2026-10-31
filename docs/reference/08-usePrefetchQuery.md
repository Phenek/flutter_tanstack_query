---
id: usePrefetchQuery
title: usePrefetchQuery / usePrefetchInfiniteQuery
---

Warm the cache for a query **before** a widget needs it, without subscribing to it. The hooks
return nothing and never rebuild: a later `useQuery` on the same key finds the data already there.

```dart
usePrefetchQuery<List<Station>>(
  queryKey: ['stations', 'near', lat, lng],
  queryFn: () => StationsApi.near(lat, lng),
);

usePrefetchInfiniteQuery<Station>(
  queryKey: ['stations'],
  queryFn: (pageParam) => StationsApi.page(pageParam),
  initialPageParam: 0,
  getNextPageParam: (lastPage) => lastPage.nextCursor,
);
```

Like the React versions, the fetch is skipped when the key already has a cache entry, so it is safe
to call on every build. Prefetch on the screen *before* the one that displays the data — a list row,
a marker tap — not on the screen that shows it. For code running outside the widget tree, the same
effect is `queryClient.prefetchQuery(...)` / `queryClient.prefetchInfiniteQuery(...)`.
