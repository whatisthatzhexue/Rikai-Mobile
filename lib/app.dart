import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_tokens.dart';
import 'features/home/home_page.dart';
import 'features/lookup/search_page.dart';
import 'features/reader/reader_page.dart';
import 'features/settings/dictionary_page.dart';
import 'features/settings/settings_page.dart';

GoRouter _createRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/reader',
        builder: (context, state) =>
            ReaderPage(initialText: state.uri.queryParameters['text'] ?? ''),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
      GoRoute(
        path: '/dictionaries',
        builder: (context, state) => const DictionaryPage(),
      ),
    ],
  );
}

class RikaiApp extends StatefulWidget {
  const RikaiApp({super.key});

  @override
  State<RikaiApp> createState() => _RikaiAppState();
}

class _RikaiAppState extends State<RikaiApp> {
  late final GoRouter _router = _createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Rikai',
      debugShowCheckedModeBanner: false,
      // Canonical v1 design is light blue/white; see docs/design-tokens.md.
      theme: AppTheme.light(),
      darkTheme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: _router,
    );
  }
}
