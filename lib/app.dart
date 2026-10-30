import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_tokens.dart';
import 'core/theme/unfocus_route_observer.dart';
import 'state/providers.dart';
import 'features/capture/capture_page.dart';
import 'features/capture/photo_set_page.dart';
import 'features/corpus/corpus_detail_page.dart';
import 'features/corpus/corpus_page.dart';
import 'features/home/home_page.dart';
import 'features/lookup/search_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/reader/reader_page.dart';
import 'features/settings/copyright_page.dart';
import 'features/settings/dictionary_import_page.dart';
import 'features/settings/dictionary_page.dart';
import 'features/settings/help_page.dart';
import 'features/settings/model_page.dart';
import 'features/settings/settings_page.dart';

Page<void> _page(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: animation.drive(
          Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)),
        ),
        child: child,
      );
    },
  );
}

GoRouter _createRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    observers: [UnfocusRouteObserver()],
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _page(state, const HomePage()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _page(state, const OnboardingPage()),
      ),
      GoRoute(
        path: '/reader',
        pageBuilder: (context, state) {
          final extra = state.extra;
          final page = extra is ReaderRouteArgs
              ? ReaderPage(initialText: extra.text, replaceDraft: true)
              : ReaderPage(
                  initialText: state.uri.queryParameters['text'] ?? '',
                );
          return _page(state, page);
        },
      ),
      GoRoute(
        path: '/capture',
        pageBuilder: (context, state) => _page(state, const CapturePage()),
      ),
      GoRoute(
        path: '/photos',
        pageBuilder: (context, state) => _page(state, const PhotoSetPage()),
      ),
      GoRoute(
        path: '/corpus',
        pageBuilder: (context, state) => _page(state, const CorpusPage()),
      ),
      GoRoute(
        path: '/corpus-detail',
        pageBuilder: (context, state) {
          final extra = state.extra;
          final page = extra is CorpusDetailRouteArgs
              ? CorpusDetailPage(initialEntry: extra.entry)
              : const CorpusPage();
          return _page(state, page);
        },
      ),
      GoRoute(
        path: '/models',
        pageBuilder: (context, state) => _page(state, const ModelPage()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _page(state, const SettingsPage()),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (context, state) => _page(state, const SearchPage()),
      ),
      GoRoute(
        path: '/dictionaries',
        pageBuilder: (context, state) => _page(state, const DictionaryPage()),
      ),
      GoRoute(
        path: '/dictionary-import',
        pageBuilder: (context, state) =>
            _page(state, const DictionaryImportPage()),
      ),
      GoRoute(
        path: '/help',
        pageBuilder: (context, state) => _page(state, const HelpPage()),
      ),
      GoRoute(
        path: '/copyright',
        pageBuilder: (context, state) => _page(state, const CopyrightPage()),
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
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final completed = ref.read(appSettingsProvider).onboardingCompleted;
    _router = _createRouter(initialLocation: completed ? '/' : '/onboarding');
  }

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
