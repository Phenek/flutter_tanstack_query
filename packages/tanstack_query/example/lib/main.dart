import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:tanstack_query/tanstack_query.dart';
import 'pages/infinity_page.dart';
import 'pages/todos_page.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  var queryClient = QueryClient(
    defaultOptions: const DefaultOptions(
      queries: QueryDefaultOptions(
        enabled: true,
        staleTime: 0,
        refetchOnWindowFocus: true,
        refetchOnReconnect: true,
      ),
    ),
    queryCache: QueryCache(
        config: QueryCacheConfig(onError: (e) => debugPrint(e.toString()))),
    mutationCache: MutationCache(
        config: MutationCacheConfig(onError: (e) => debugPrint(e.toString()))),
  );

  InternetConnection connectivity = InternetConnection();

  connectivity.onStatusChange.listen((status) {
    if (status == InternetStatus.connected) {
      onlineManager.setOnline(true);
    } else {
      onlineManager.setOnline(false);
    }
  });

  AppLifecycleListener(onResume: () {
    focusManager.setFocused(true);
  }, onInactive: () {
    focusManager.setFocused(false);
  }, onPause: () {
    focusManager.setFocused(false);
  });

  runApp(
    QueryClientProvider(client: queryClient, child: const App()),
  );
}

class App extends HookWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final content = useState<Widget>(TodosPage());

    return MaterialApp(
      title: 'tanstack_query Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Scaffold(
        body: SafeArea(
          child: content.value,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: content.value is TodosPage ? 0 : 1,
          onTap: (index) {
            if (index == 0) {
              // Always create a new TodosPage, to see the librairy in action
              content.value = TodosPage();
            } else {
              // Always create a new InfinityPage, to see the librairy in action
              content.value = InfinityPage();
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.view_agenda),
              label: 'Classical',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.all_inclusive),
              label: 'Infinity',
            ),
          ],
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.black54,
        ),
      ),
    );
  }
}
