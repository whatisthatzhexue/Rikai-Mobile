import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mecab/mecab_service.dart';
import '../services/storage/permission_service.dart';
import '../services/storage/settings_store.dart';

/// Overridden in `main()` after SharedPreferences is loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  );
});

final settingsStoreProvider = Provider<SettingsStore>((ref) {
  return SettingsStore(ref.watch(sharedPreferencesProvider));
});

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return const PermissionService();
});

final mecabServiceProvider =
    AsyncNotifierProvider<MecabServiceNotifier, MecabService>(
      MecabServiceNotifier.new,
      // A missing/invalid UniDic will not fix itself. Riverpod 3 retries
      // failed providers by default, which would repeatedly attempt to mmap a
      // 1.3 GB dictionary and keep the UI in a loading state.
      retry: (retryCount, error) => null,
    );

class AppSettingsNotifier extends Notifier<AppSettings> {
  late SettingsStore _store;

  @override
  AppSettings build() {
    _store = ref.watch(settingsStoreProvider);
    return _store.load();
  }

  void setUnidicPath(String path) {
    _update(state.copyWith(unidicPath: path.trim()));
  }

  void setShowFurigana(bool value) {
    _update(state.copyWith(showFurigana: value));
  }

  void setReaderFontSize(double value) {
    _update(state.copyWith(readerFontSize: value));
  }

  void _update(AppSettings next) {
    state = next;
    unawaited(_store.save(next));
  }
}

/// Lazily opens the long-lived MeCab worker for the configured UniDic path.
///
/// The provider rebuilds automatically when the path changes; the previous
/// worker is disposed through `onDispose`.
class MecabServiceNotifier extends AsyncNotifier<MecabService> {
  @override
  Future<MecabService> build() async {
    final path = ref.watch(
      appSettingsProvider.select((settings) => settings.unidicPath),
    );
    if (path.isEmpty) {
      throw const MecabException(
        MecabErrorCode.notConfigured,
        '尚未在设置中填写 UniDic 目录',
      );
    }

    final supportDirectory = await getApplicationSupportDirectory();
    MecabService? service;
    var disposed = false;
    ref.onDispose(() {
      disposed = true;
      final current = service;
      if (current != null) unawaited(current.dispose());
    });

    final created = await MecabService.open(
      dictDir: path,
      rcDirectory: supportDirectory.path,
    );
    if (disposed) {
      await created.dispose();
      throw const MecabException(MecabErrorCode.disposed, '分词服务已释放');
    }
    service = created;
    return created;
  }
}
