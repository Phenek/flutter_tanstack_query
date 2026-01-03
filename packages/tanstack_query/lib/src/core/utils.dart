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
