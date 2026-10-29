import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_tokens.dart';
import 'state/providers.dart';
import 'features/capture/capture_page.dart';
import 'features/capture/photo_set_page.dart';
import 'features/corpus/corpus_detail_page.dart';
import 'features/corpus/corpus_page.dart';
import 'features/home/home_page.dart';
import 'features/lookup/search_page.dart';
import 'features/reader/reader_page.dart';
import 'features/settings/dictionary_import_page.dart';
import 'features/settings/dictionary_page.dart';
import 'features/settings/model_page.dart';
import 'features/settings/settings_page.dart';

GoRouter _createRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/reader',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is ReaderRouteArgs) {
            return ReaderPage(initialText: extra.text, replaceDraft: true);
          }
          return ReaderPage(
            initialText: state.uri.queryParameters['text'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/capture',
        builder: (context, state) => const CapturePage(),
      ),
      GoRoute(
        path: '/photos',
        builder: (context, state) => const PhotoSetPage(),
      ),
      GoRoute(path: '/corpus', builder: (context, state) => const CorpusPage()),
      GoRoute(
        path: '/corpus-detail',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is CorpusDetailRouteArgs) {
            return CorpusDetailPage(initialEntry: extra.entry);
          }
          return const CorpusPage();
        },
      ),
      GoRoute(path: '/models', builder: (context, state) => const ModelPage()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
      GoRoute(
        path: '/dictionaries',
        builder: (context, state) => const DictionaryPage(),
      ),
      GoRoute(
        path: '/dictionary-import',
        builder: (context, state) => const DictionaryImportPage(),
      ),
    ],
  );
}

class RikaiApp extends ConsumerStatefulWidget {
  const RikaiApp({super.key});

  @override
  ConsumerState<RikaiApp> createState() => _RikaiAppState();
}

class _RikaiAppState extends ConsumerState<RikaiApp> {
  late final GoRouter _router = _createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = ref.watch(
      appSettingsProvider.select((settings) => settings.fontFamily),
    );

    return MaterialApp.router(
      title: 'Rikai',
      debugShowCheckedModeBanner: false,
      // Canonical v1 design is light blue/white; see docs/design-tokens.md.
      theme: AppTheme.light(fontFamily: fontFamily),
      darkTheme: AppTheme.light(fontFamily: fontFamily),
      themeMode: ThemeMode.light,
      routerConfig: _router,
    );
  }
}
