---
id: render-optimizations
title: Render Optimizations
---

Flutter TanStack Query applies a couple of optimizations automatically so your widgets only rebuild
when they actually need to.

## structural sharing

The library keeps as many references as possible intact between fetches. A `queryFn` usually hands
back a completely new object — a fresh list from `jsonDecode`, a rebuilt model — but if _nothing_
changed in the data, the previous instance is kept. If only a subset changed, the unchanged parts are
kept and only the changed parts are replaced.

```dart
final stations = useQuery<List<StationOff>>(
  queryKey: [GetAllStationsApi.name],
  queryFn: GetAllStationsApi.request,
);
// Refetch the same payload, and `stations.data` is the *same* list instance,
// so anything memoized on it is not recomputed.
```

Turn it off, or take over, per query:

```dart
useQuery<List<int>>(
  queryKey: key,
  queryFn: fetch,
  structuralSharing: false,                      // store each fetch as-is
  // structuralSharing: (prev, next) => merge(prev, next),  // or merge yourself
);
```

Two differences from the JavaScript version worth knowing:

- JavaScript compares with `===` throughout, so only lists and plain objects can ever be recognised
  as unchanged. Dart compares with `==`, so a **record, a Freezed model or any class with value
  equality is recognised as unchanged** and keeps its identity. In an app where every DTO is Freezed,
  this is where most of the benefit comes from.
- **Lists** are shared per element, exactly as in JavaScript. **Maps** are shared whole or not at
  all: a map cannot be copied in Dart while keeping its reified key and value types, so either every
  entry matches and the previous map is kept, or the new one is returned untouched.

### referential identity

The `QueryResult` returned by a hook is a new instance on every notification, but it compares by
value, so an observer that recomputes an identical result never wakes its listeners. The `data` it
carries is as stable as structural sharing can make it.

## select

`select` lets an observer expose something *derived* from the cached data. Two widgets can read
different shapes out of one cached payload — and therefore one network request:

```dart
// The itinerary view reads the whole route.
final route = useQuery<OrsRoute>(queryKey: key, queryFn: fetchRoute);

// The summary bubble only needs km and duration, derived from the same cache entry.
final observer = QueryObserver<OrsRoute, Object?, Summary>(
  client,
  QueryObserverOptions<OrsRoute, Summary>(
    queryKey: key,            // same key: one request
    queryFn: fetchRoute,
    select: routeToSummary,
  ),
);
```

A `select` that throws surfaces as an errored result, so a parsing mistake shows up as an error state
rather than a crash.

> `select` lives on `QueryObserver` / `QueryObserverOptions`, where query-core puts it, and not on
> `useQuery`. The reason is a Dart limitation: TypeScript declares `useQuery` with `TData =
> TQueryFnData`, a default for a generic, which Dart does not have (nor does it have function
> overloads). A `useQuery` with two type parameters would silently infer `dynamic` at every call site
> that writes no type argument. Wrap the observer in your own hook instead — `select` being required
> there makes both types inferable.

### memoization

`select` runs on every result, so it must be cheap and pure. It is memoized on the identity of both
the cached data and the function itself:

```dart
// Memoized: a top-level function or a tear-off keeps its identity.
Summary routeToSummary(OrsRoute route) => ...;
select: routeToSummary,

// NOT memoized: a new closure on every build re-runs the selection.
select: (route) => Summary(route.distanceMeters / 1000, ...),
```

The selected value also goes through `structuralSharing`, so returning a freshly built record or list
does not by itself cause a rebuild.

## Further Reading

- [Important Defaults](./01-important-defaults.md)
- [Caching](./11-caching.md)
