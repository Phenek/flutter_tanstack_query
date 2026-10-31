import 'dart:convert';

// Custom encoder for enums
/// Converts enum values and other items into a string form suitable for
/// JSON encoding by `queryKeyToCacheKey`.
dynamic customEncode(dynamic item) {
  return item.toString();
}

/// Serializes a [queryKey] into a deterministic string usable as a cache key.
String queryKeyToCacheKey(List<Object> queryKey) {
  // Encode the queryKey to JSON using the custom encoder
  String json = jsonEncode(queryKey, toEncodable: customEncode);

  // Decode the JSON back to a List<dynamic>
  List<dynamic> decodedList = jsonDecode(json);

  var input = decodedList.join(';');

  // Regular expression to match properties with null values
  RegExp nullPropertyPattern = RegExp(r'\w+: null,?\s*');

  // Join the resulting entries with a semicolon
  return input.replaceAll(nullPropertyPattern, '');
}

/// Whether [pattern] matches the start of [key], element by element.
///
/// Port of `partialMatchKey` in `utils.ts`, where the second argument is the
/// pattern: every element (or map entry) it declares must match [key], and the
/// elements it does not declare are free.
///
/// This is deliberately stricter than comparing serialized keys with
/// `String.startsWith`, which matches on characters: `['todo']` would match
/// `['todos', 1]` there, and does not match here.
bool partialMatchKey(Object? key, Object? pattern) {
  if (identical(key, pattern) || key == pattern) return true;

  if (key is List && pattern is List) {
    if (pattern.length > key.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (!partialMatchKey(key[i], pattern[i])) return false;
    }
    return true;
  }

  if (key is Map && pattern is Map) {
    for (final entry in pattern.entries) {
      if (!partialMatchKey(key[entry.key], entry.value)) return false;
    }
    return true;
  }

  return false;
}

/// Returns [a] when it is deeply equal to [b], otherwise a copy of [b] that
/// reuses every sub-value already present in [a].
///
/// Port of `replaceEqualDeep` in `utils.ts`. Its purpose is identity stability:
/// a refetch that brings back the same payload hands back the *previous*
/// instance, so observers compare equal and nothing rebuilds.
///
/// One deliberate improvement over the JavaScript version, which compares with
/// `===` throughout: this compares with `==`, so a record, a Freezed model or
/// any class with value equality is recognised as unchanged instead of being
/// treated as a new object. Only [List] and [Map] are traversed — anything else
/// is either equal (and kept) or replaced wholesale, which is also what the JS
/// version does for class instances.
T replaceEqualDeep<T>(Object? a, T b) => _replaceEqualDeep(a, b) as T;

bool _sameValue(Object? a, Object? b) => identical(a, b) || a == b;

bool _isTraversable(Object? value) => value is List || value is Map;

Object? _replaceEqualDeep(Object? a, Object? b) {
  if (_sameValue(a, b)) return a;

  if (a is List && b is List) return _replaceEqualList(a, b);
  if (a is Map && b is Map) return _replaceEqualMap(a, b);
  return b;
}

Object? _replaceEqualList(List<Object?> a, List<Object?> b) {
  // Start from a copy of [b] rather than a fresh `List<Object?>`: Dart generics
  // are reified, so `toList()` keeps the element type and the result can still
  // be used as the `List<T>` the caller expects.
  final copy = b.toList();
  var equalItems = 0;

  for (var i = 0; i < b.length; i++) {
    final inA = i < a.length;
    final aItem = inA ? a[i] : null;
    final bItem = b[i];

    if (inA && _sameValue(aItem, bItem)) {
      copy[i] = aItem;
      equalItems++;
      continue;
    }
    if (!_isTraversable(aItem) || !_isTraversable(bItem)) {
      continue; // copy already holds bItem
    }
    final replaced = _replaceEqualDeep(aItem, bItem);
    copy[i] = replaced;
    if (identical(replaced, aItem)) equalItems++;
  }

  return a.length == b.length && equalItems == a.length ? a : copy;
}

Object? _replaceEqualMap(Map<Object?, Object?> a, Map<Object?, Object?> b) {
  // Unlike lists, a map cannot be copied while keeping its reified key and value
  // types: `List.toList()` is an instance method and carries `E` with it, while
  // every map copy goes through a constructor whose type arguments come from the
  // call site — `Map.of(b)` would hand back a `Map<Object?, Object?>` that fails
  // the cast to the caller's `Map<String, dynamic>`.
  //
  // So maps are shared whole or not at all: either everything matches and [a] is
  // kept, or [b] is returned untouched. This gives up the JavaScript version's
  // per-key sharing inside maps, and keeps the guarantee that matters — a
  // payload that did not change keeps its identity.
  if (a.length != b.length) return b;
  for (final key in b.keys) {
    if (!a.containsKey(key)) return b;
    final aItem = a[key];
    final bItem = b[key];
    if (_sameValue(aItem, bItem)) continue;
    if (!_isTraversable(aItem) || !_isTraversable(bItem)) return b;
    if (!identical(_replaceEqualDeep(aItem, bItem), aItem)) return b;
  }
  return a;
}

/// Applies the `structuralSharing` option to a freshly produced [data].
///
/// Port of `replaceData` in `utils.ts`. [structuralSharing] accepts the same
/// shapes as in JavaScript: `false` to hand the new data back untouched, or a
/// `T Function(T? previous, T next)` to decide the merge yourself. Anything
/// else (including `null`) means the default [replaceEqualDeep].
T replaceData<T>(T? prevData, T data, Object? structuralSharing) {
  if (structuralSharing == false) return data;
  if (structuralSharing is T Function(T?, T)) {
    return structuralSharing(prevData, data);
  }
  if (structuralSharing is Function) {
    // The option is declared as `Object?` so it can also hold `false`, which
    // means a closure written inline at the call site gets no contextual type
    // and infers `dynamic Function(dynamic, dynamic)` — not a subtype of
    // `T Function(T?, T)`, so the typed test above misses it. JavaScript only
    // checks `typeof structuralSharing === 'function'`, so do the same and
    // call it dynamically rather than silently ignoring the user's merge.
    return Function.apply(structuralSharing, <Object?>[prevData, data]) as T;
  }
  return replaceEqualDeep<T>(prevData, data);
}
