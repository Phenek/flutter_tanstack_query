import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:provider/provider.dart';
import 'package:tanstack_query/tanstack_query.dart';

/// Returns the nearest `QueryClient` provided by `QueryClientProvider`.
///
/// Use this hook inside widgets that have been wrapped with
/// `QueryClientProvider`. Throws an [Exception] if called outside of a
/// `QueryClientProvider`.
///
/// Example:
/// ```dart
/// final client = useQueryClient();
/// client.invalidateQueries(queryKey: ['todos']);
/// ```
QueryClient useQueryClient() {
  final context = useContext();
  final provider = Provider.of<QueryClientContext>(context, listen: true);

  if (provider.client == null) {
    throw Exception('useQueryClient must be used inside a QueryClientProvider');
  }

  return provider.client!;
}