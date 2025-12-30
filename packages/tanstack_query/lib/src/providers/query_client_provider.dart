import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'package:provider/provider.dart';

/// A lightweight holder used to provide a `QueryClient` instance to
/// the widget subtree via `Provider<QueryClientContext>`.
class QueryClientContext {
  /// The `QueryClient` instance stored in this context.
  final QueryClient? client;

  QueryClientContext({this.client});
}

/// Provides a `QueryClient` to its descendants.
///
/// Wrap your application (or a subtree) with `QueryClientProvider` to make a
/// `QueryClient` available via the `useQueryClient()` hook.
class QueryClientProvider extends HookWidget {
  /// The `QueryClient` to provide to descendants.
  final QueryClient client;

  /// The subtree which can access the provided `QueryClient`.
  final Widget child;

  const QueryClientProvider(
      {Key? key, required this.client, required this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final queryClientContext = useMemoized(() {
      return QueryClientContext(client: client);
    }, [client]);

    return Provider<QueryClientContext>.value(
      value: queryClientContext,
      child: child,
    );
  }
}

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
