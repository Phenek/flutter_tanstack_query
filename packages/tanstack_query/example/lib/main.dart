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
        gcTime: 60 * 1000,
        refetchOnWindowFocus: true,
        refetchOnReconnect: true,
      ),
    ),
    queryCache: QueryCache(
      config: QueryCacheConfig(onError: (e) => debugPrint(e.toString())),
    ),
    mutationCache: MutationCache(
      config: MutationCacheConfig(
        onError: (e, [context]) => debugPrint(e.toString()),
      ),
    ),
  );

  InternetConnection connectivity = InternetConnection();

  connectivity.onStatusChange.listen((status) {
    if (status == InternetStatus.connected) {
      onlineManager.setOnline(true);
    } else {
      onlineManager.setOnline(false);
    }
  });

  AppLifecycleListener(
    onResume: () {
      focusManager.setFocused(true);
    },
    onInactive: () {
      focusManager.setFocused(false);
    },
    onPause: () {
      focusManager.setFocused(false);
    },
  );

  runApp(QueryClientProvider(client: queryClient, child: const App()));
}

class App extends HookWidget {
  const App({super.key});

  // flutter-tanstack.com accents: terracotta-400 in light mode, terracotta-300 in dark mode
  static const _seedLight = Color(0xFFD3481B);
  static const _seedDark = Color(0xFFE06E49);

  ThemeData _theme(Brightness brightness) => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: brightness == Brightness.light ? _seedLight : _seedDark,
          brightness: brightness,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final content = useState<Widget>(TodosPage());

    return MaterialApp(
      title: 'tanstack_query Example',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      // ?brightness= is set by the site embedding the app, so it matches the page theme
      themeMode: switch (Uri.base.queryParameters['brightness']) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      },
      home: Scaffold(
        body: SafeArea(child: content.value),
        bottomNavigationBar: NavigationBar(
          selectedIndex: content.value is TodosPage ? 0 : 1,
          onDestinationSelected: (index) {
            // Always create a new page, to see the librairy in action
            content.value = index == 0 ? TodosPage() : InfinityPage();
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.view_agenda_outlined),
              selectedIcon: Icon(Icons.view_agenda),
              label: 'Classical',
            ),
            NavigationDestination(
              icon: Icon(Icons.all_inclusive_outlined),
              selectedIcon: Icon(Icons.all_inclusive),
              label: 'Infinity',
            ),
          ],
        ),
      ),
    );
  }
}
