import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/app_tokens.dart';
import 'state/providers.dart';

/// Shows the branded splash while preferences, installed dictionaries and the
/// tokenizer are prepared, then hands a single ProviderContainer to the app.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  ProviderContainer? _container;
  bool _ready = false;
  String _status = '正在加载主界面…';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _container?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      _container = container;
      if (!mounted) {
        container.dispose();
        _container = null;
        return;
      }

      await _loadDictionaries(container);
      await _loadTokenizer(container);

      if (!mounted) {
        container.dispose();
        _container = null;
        return;
      }
      setState(() => _ready = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _loadDictionaries(ProviderContainer container) async {
    if (!mounted) return;
    setState(() => _status = '正在加载已安装的词典…');

    final dictionaries = container.read(enabledDictionariesProvider);
    if (dictionaries.isEmpty) return;

    try {
      final service = await container
          .read(mdictServiceProvider.future)
          .timeout(const Duration(seconds: 20));
      // Opening all enabled dictionaries now removes the cold-start delay from
      // the first entry navigation.
      await service.warmUp(dictionaries).timeout(const Duration(seconds: 20));
    } catch (error) {
      debugPrint('[Bootstrap] dictionary warm-up skipped: $error');
    }
  }

  Future<void> _loadTokenizer(ProviderContainer container) async {
    final path = container.read(appSettingsProvider).unidicPath;
    if (path.isEmpty || !mounted) return;

    setState(() => _status = '正在加载分词功能…');
    try {
      await container
          .read(mecabServiceProvider.future)
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      // An invalid UniDic must not block startup; the reader/settings page will
      // show the detailed error and allow the user to fix the path.
      debugPrint('[Bootstrap] tokenizer warm-up skipped: $error');
    }
  }

  void _retry() {
    final old = _container;
    _container = null;
    old?.dispose();
    setState(() {
      _error = null;
      _ready = false;
      _status = '正在加载主界面…';
    });
    _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final container = _container;
    if (_ready && container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: const RikaiApp(),
      );
    }

    return MaterialApp(
      title: 'Rikai',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.light(),
      themeMode: ThemeMode.light,
      home: SplashPage(
        status: _status,
        error: _error,
        onRetry: _error == null ? null : _retry,
      ),
    );
  }
}

/// Branded loading screen with the real initialization phases.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key, required this.status, this.error, this.onRetry});

  final String status;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = error != null;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Image.asset(
                  'assets/Rikai_Icon.jpg',
                  width: 160,
                  height: 160,
                  fit: BoxFit.cover,
                  cacheWidth: 480,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 160,
                    height: 160,
                    color: AppColors.primaryContainer,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.menu_book,
                      size: AppSizes.heroIcon,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Rikai', style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                hasError ? '启动失败' : status,
                key: const ValueKey('splash-status'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              if (hasError) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: AppSizes.icon),
                  label: const Text('重试'),
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.lg),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
