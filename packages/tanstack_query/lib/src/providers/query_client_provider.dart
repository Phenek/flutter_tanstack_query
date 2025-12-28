import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'package:provider/provider.dart';

class QueryClientContext {
  final QueryClient? client;
  
  QueryClientContext({this.client});
}

class QueryClientProvider extends HookWidget {
  final QueryClient client;
  final Widget child;

  const QueryClientProvider({Key? key, required this.client, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    
    final queryClientContext = useMemoized(() {
      return QueryClientContext(
        client: client
      );
    }, [client]);

    return Provider<QueryClientContext>.value(
      value: queryClientContext,
      child: child,
    );
  }
}

QueryClient useQueryClient() {
  final context = useContext();
  final provider = Provider.of<QueryClientContext>(context, listen: true);

  if (provider.client == null) {
    throw Exception('useQueryClient must be used inside a QueryClientProvider');
  }

  return provider.client!;
}
