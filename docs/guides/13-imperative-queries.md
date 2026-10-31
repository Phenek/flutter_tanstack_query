---
id: imperative-queries
title: Using queries outside the widget tree
---

Hooks are the normal way to read a query, but some work legitimately lives outside the widget tree:
a service reacting to a notifier, a side effect of a navigation change, an optimistic write from a
callback. The `QueryClient` has an imperative API for exactly that, ported from `queryClient.ts`.

The rule that makes it safe: **the key is the contract**. An imperative call and a mounted
`useQuery` on the same key share one cache entry, and a fetch already in flight is joined, not
duplicated.

```dart
class DetourService {
  void onSelectionChanged(ShellNavigationContext nav) {
    final stationId = nav.selectedStationId.value;
    if (stationId == null) return;

    // Same key, same queryFn as the useDetourQuery hook in the map widgets:
    // one pair of ORS calls whether or not any widget is mounted.
    queryClient.fetchQuery<DetourResult>(
      queryKey: DetourQuery.keyFor(stationId, nav.waypointLocations.value),
      queryFn: () => computeDetour(stationId: stationId, waypoints: nav.waypointLocations.value),
      staleTime: double.infinity,
    );
  }
}
```

What to use, when:

- `fetchQuery` — you await the answer: it resolves with the data or throws with the error. If the
  query exists and the data is not invalidated or older than the given `staleTime`, the data from
  the cache is returned; otherwise it tries to fetch the latest data. `retry` defaults to `false`
  here (unlike `useQuery`): an imperative caller would rather see the error than wait out the
  retries. A `retry` you configure yourself — per call, through `setQueryDefaults`, or in the
  client's `defaultOptions.queries` — still wins.
- `prefetchQuery` — warm the cache, swallow the error; whoever mounts the query later handles it.
- `ensureQueryData` — get an existing query's cached data; if the query does not exist, `fetchQuery`
  is called and its result returned. With `revalidateIfStale: true`, stale data is refetched in the
  background, but the cached data is returned immediately.
- `setQueryData` / `setQueryDataValue` — write the cache synchronously (optimistic updates). An
  updater returning `null` writes nothing and creates no entry. Note the Dart signature takes a
  typed updater `T? Function(T? old)` rather than the JS `value | function` union: with an `Object?`
  parameter the closure loses its contextual type and a literal like `distanceMeters: 110000`
  would infer `int` where `T` expects `double`.
- `getQueryData` / `getQueryState` / `getQueriesData` — read the cache without building a query or
  starting a fetch. Never reactive: use a hook inside widgets.
- `setQueryDefaults` — register defaults for a key prefix, e.g. `staleTime` for every `['ors', ...]`
  query. Per-call options still win over per-key defaults, which win over the global defaults.
  Matching defaults are merged in order of registration, so register from the **most generic key**
  to the **least generic one**: that way more specific defaults override more generic ones.
- `removeQueries` — remove matching queries from the cache. `resetQueries` — reset them to their
  pre-loaded state: the entry is cleared and, if a query is active, it is refetched. Both reach data
  written by `setQueryData` before anything mounted, and a mounted `useQuery` falls back to
  `pending` once its entry is gone.
- The infinite variants: `fetchInfiniteQuery`, `prefetchInfiniteQuery` and `ensureInfiniteQueryData`,
  which takes the same options as `fetchInfiniteQuery` plus `revalidateIfStale`.

Every one of these key filters matches element by element, like `partialMatchKey` in JavaScript:
`['todos']` reaches `['todos', 1]`, while `['todos', 1]` leaves `['todos', 11]` alone. Pass
`exact: true` to match one key only.

Inside widgets, prefer `usePrefetchQuery` / `usePrefetchInfiniteQuery` (see
[reference/08-usePrefetchQuery.md](../reference/08-usePrefetchQuery.md)) over calling
`prefetchQuery` in a build.
