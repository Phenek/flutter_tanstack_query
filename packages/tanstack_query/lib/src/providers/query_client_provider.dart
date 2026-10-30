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
      {super.key, required this.client, required this.child});

  /// Re-provides the client of [context] to a subtree mounted **outside** the
  /// provider, typically an `Overlay`: a dragged `ReorderableListView` item, a
  /// route pushed with `Navigator`, or a `showDialog` builder all build under
  /// the overlay, where `useQueryClient()` finds no provider and throws.
  ///
  /// [context] must be a context that still sees the provider — capture it in
  /// the enclosing `build`, then call this inside the overlay builder:
  ///
  /// ```dart
  /// ReorderableListView(
  ///   proxyDecorator: (child, index, animation) =>
  ///       QueryClientProvider.portal(context, child: child),
  ///   ...
  /// )
  /// ```
  ///
  /// It only re-exposes the client; mounting stays owned by the real provider,
  /// so focus/online subscriptions are never duplicated.
  static Widget portal(BuildContext context, {required Widget child}) {
    final queryClientContext =
        Provider.of<QueryClientContext>(context, listen: false);
    return Provider<QueryClientContext>.value(
      value: queryClientContext,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final queryClientContext = useMemoized(() {
      return QueryClientContext(client: client);
    }, [client]);

    // Mount the client when this provider is added to the widget tree and
    // unmount when removed so it can listen to global focus/online events.
    useEffect(() {
      client.mount();
      return () {
        client.unmount();
      };
    }, [client]);

    return Provider<QueryClientContext>.value(
      value: queryClientContext,
      child: child,
    );
  }
}
