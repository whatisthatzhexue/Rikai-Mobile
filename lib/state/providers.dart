import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/dict_info.dart';
import '../core/models/corpus_entry.dart';
import '../core/models/lookup_match_mode.dart';
import '../core/models/ocr_model.dart';
import '../core/theme/app_fonts.dart';
import '../services/mdict/entry_cache.dart';
import '../services/mdict/mdict_worker.dart';
import '../services/mecab/mecab_service.dart';
import '../services/ocr/model_manager.dart';
import '../services/ocr/ocr_service.dart';
import '../services/storage/dictionary_store.dart';
import '../services/storage/history_store.dart';
import '../services/storage/permission_service.dart';
import '../services/storage/settings_store.dart';
import '../services/storage/storage_space_service.dart';

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

final storageSpaceServiceProvider = Provider<StorageSpaceService>((ref) {
  return const StorageSpaceService();
});

final historyStoreProvider = Provider<HistoryStore>((ref) {
  final store = HistoryStore();
  ref.onDispose(store.close);
  return store;
});

final corpusEntriesProvider = FutureProvider<List<CorpusEntry>>(
  (ref) => ref.watch(historyStoreProvider).list(),
  retry: (retryCount, error) => null,
);

/// Reader input draft that survives navigation for the app's lifetime.
final readerDraftControllerProvider = Provider<TextEditingController>((ref) {
  final controller = TextEditingController();
  ref.onDispose(controller.dispose);
  return controller;
});

final mecabServiceProvider =
    AsyncNotifierProvider<MecabServiceNotifier, MecabService>(
      MecabServiceNotifier.new,
      // A missing/invalid UniDic will not fix itself. Riverpod 3 retries
      // failed providers by default, which would repeatedly attempt to mmap a
      // 1.3 GB dictionary and keep the UI in a loading state.
      retry: (retryCount, error) => null,
    );

final dictionaryStoreProvider = Provider<DictionaryStore>((ref) {
  return DictionaryStore(ref.watch(sharedPreferencesProvider));
});

final dictionaryRepositoryProvider =
    NotifierProvider<DictionaryRepositoryNotifier, List<DictionaryInfo>>(
      DictionaryRepositoryNotifier.new,
    );

/// Dictionaries used for lookups: enabled and currently readable.
final enabledDictionariesProvider = Provider<List<DictionaryInfo>>((ref) {
  return ref
      .watch(dictionaryRepositoryProvider)
      .where((dictionary) => dictionary.enabled && dictionary.isAvailable)
      .toList(growable: false);
});

final mdictServiceProvider =
    AsyncNotifierProvider<MdictServiceNotifier, MdictService>(
      MdictServiceNotifier.new,
      retry: (retryCount, error) => null,
    );

/// LRU cache for rendered entry pages (in-memory, app lifetime).
final entryRenderCacheProvider = Provider<EntryRenderCache>((ref) {
  return EntryRenderCache();
});

/// OCR model catalog. The manifest is checked into the app; model binaries are
/// downloaded into getExternalFilesDir()/models/ at runtime.
final ocrModelManifestProvider = FutureProvider<OcrModelManifest>((ref) {
  return OcrModelManager().loadManifest();
}, retry: (retryCount, error) => null);

final ocrModelManagerProvider = Provider<OcrModelManager>((ref) {
  final space = ref.watch(storageSpaceServiceProvider);
  return OcrModelManager(
    modelsDirectory: () async =>
        ref.read(appSettingsProvider).ocrModelsDirectory,
    availableSpace: space.availableBytes,
  );
});

final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrService(ref.watch(ocrModelManagerProvider));
  ref.onDispose(service.dispose);
  return service;
});

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

  void setFontFamily(String value) {
    _update(state.copyWith(fontFamily: AppFonts.sanitize(value)));
  }

  void setMaxEntriesPerDictionary(int value) {
    _update(state.copyWith(maxEntriesPerDictionary: value < 0 ? 0 : value));
  }

  void setLookupMatchMode(LookupMatchMode mode) {
    _update(state.copyWith(lookupMatchMode: mode));
  }

  void setOcrMirror(String value) {
    _update(state.copyWith(ocrMirror: value.trim()));
  }

  void setOcrModelsDirectory(String value) {
    _update(state.copyWith(ocrModelsDirectory: value.trim()));
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

/// Lazily opens the MDict worker isolate on first use.
class MdictServiceNotifier extends AsyncNotifier<MdictService> {
  @override
  Future<MdictService> build() async {
    MdictService? service;
    var disposed = false;
    ref.onDispose(() {
      disposed = true;
      final current = service;
      if (current != null) unawaited(current.dispose());
    });

    final created = await MdictService.open();
    if (disposed) {
      await created.dispose();
      throw const MdictException(MdictErrorCode.disposed, '词典服务已释放');
    }
    service = created;
    return created;
  }
}

/// Dictionary registry: add/remove/reorder and validate MDX files in place.
class DictionaryRepositoryNotifier extends Notifier<List<DictionaryInfo>> {
  late DictionaryStore _store;

  @override
  List<DictionaryInfo> build() {
    _store = ref.watch(dictionaryStoreProvider);
    return _sorted(_store.load());
  }

  Future<DictionaryInfo> addDictionary(String rawPath) async {
    final path = normalizeDictionaryPath(rawPath);
    if (path.isEmpty) {
      throw const MdictException(MdictErrorCode.fileNotFound, '请输入 .mdx 词典路径');
    }
    if (!path.toLowerCase().endsWith('.mdx')) {
      throw const MdictException(
        MdictErrorCode.invalidDictionary,
        '请选择 .mdx 词典文件',
      );
    }
    final duplicate = state.any(
      (dictionary) =>
          normalizeDictionaryPath(dictionary.mdxPath).toLowerCase() ==
          path.toLowerCase(),
    );
    if (duplicate) {
      throw const MdictException(MdictErrorCode.invalidDictionary, '该词典已经添加');
    }

    final service = await ref.read(mdictServiceProvider.future);
    final metadata = await service.probe(path);
    final siblings = await _discoverSiblings(path);
    final info = DictionaryInfo(
      id: DictionaryInfo.idForPath(path),
      title: displayDictionaryTitle(metadata.title, path),
      mdxPath: path,
      mddPaths: siblings.mddPaths,
      cssPaths: siblings.cssPaths,
      entryCount: metadata.entryCount,
      encoding: metadata.encoding,
      engineVersion: metadata.engineVersion,
      enabled: true,
      order: state.length,
      lastValidatedAt: DateTime.now(),
    );

    state = _sorted([...state, info]);
    await _store.save(state);
    // Cache the reader in the worker so the first lookup after adding is hot.
    try {
      await service.warmUp([info]);
    } catch (_) {
      // Warm-up is an optimization; lookup will retry on demand.
    }
    return info;
  }

  Future<DictionaryInfo?> revalidate(String id) async {
    final index = state.indexWhere((dictionary) => dictionary.id == id);
    if (index < 0) return null;

    final current = state[index];
    DictionaryInfo updated;
    try {
      final service = await ref.read(mdictServiceProvider.future);
      final metadata = await service.probe(current.mdxPath);
      final siblings = await _discoverSiblings(current.mdxPath);
      updated = current.copyWith(
        title: displayDictionaryTitle(metadata.title, current.mdxPath),
        mddPaths: siblings.mddPaths,
        cssPaths: siblings.cssPaths,
        entryCount: metadata.entryCount,
        encoding: metadata.encoding,
        engineVersion: metadata.engineVersion,
        lastError: '',
        lastValidatedAt: DateTime.now(),
      );
      try {
        await service.closeDictionary(id);
      } catch (_) {
        // The next lookup reopens the dictionary if needed.
      }
      if (updated.isAvailable) {
        try {
          await service.warmUp([updated]);
        } catch (_) {
          // Warm-up is an optimization only.
        }
      }
    } on MdictException catch (error) {
      updated = current.copyWith(
        lastError: error.message,
        lastValidatedAt: DateTime.now(),
      );
    } catch (error) {
      updated = current.copyWith(
        lastError: error.toString(),
        lastValidatedAt: DateTime.now(),
      );
    }

    final next = state.toList();
    next[index] = updated;
    state = _sorted(next);
    await _store.save(state);
    ref.invalidate(entryRenderCacheProvider);
    return updated;
  }

  Future<void> removeDictionary(String id) async {
    final service = ref.read(mdictServiceProvider).asData?.value;
    if (service != null) {
      try {
        await service.closeDictionary(id);
      } catch (_) {
        // Best effort.
      }
    }

    final remaining = state
        .where((dictionary) => dictionary.id != id)
        .toList(growable: false);
    state = [
      for (var index = 0; index < remaining.length; index++)
        remaining[index].copyWith(order: index),
    ];
    await _store.save(state);
    ref.invalidate(entryRenderCacheProvider);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    state = [
      for (final dictionary in state)
        dictionary.id == id
            ? dictionary.copyWith(enabled: enabled)
            : dictionary,
    ];
    await _store.save(state);
  }

  Future<void> move(String id, int delta) async {
    final list = state.toList();
    final index = list.indexWhere((dictionary) => dictionary.id == id);
    if (index < 0) return;
    final target = index + delta;
    if (target < 0 || target >= list.length) return;

    final item = list.removeAt(index);
    list.insert(target, item);
    state = [
      for (var position = 0; position < list.length; position++)
        list[position].copyWith(order: position),
    ];
    await _store.save(state);
  }

  Future<({List<String> mddPaths, List<String> cssPaths})> _discoverSiblings(
    String mdxPath,
  ) async {
    final directory = File(mdxPath).parent;
    if (!await directory.exists()) {
      return (mddPaths: const <String>[], cssPaths: const <String>[]);
    }

    final base = dictionaryTitleFallback(mdxPath).toLowerCase();
    final mddPaths = <String>[];
    final cssPaths = <String>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = dictionaryFileName(entity.path).toLowerCase();
        if (name.endsWith('.mdd') &&
            dictionaryTitleFallback(entity.path).toLowerCase() == base) {
          mddPaths.add(entity.path);
        } else if (name.endsWith('.css')) {
          cssPaths.add(entity.path);
        }
      }
    } on FileSystemException {
      // Missing permission or removed media: never fail adding the MDX.
    }

    mddPaths.sort();
    cssPaths.sort();
    return (
      mddPaths: List<String>.unmodifiable(mddPaths),
      cssPaths: List<String>.unmodifiable(cssPaths),
    );
  }

  List<DictionaryInfo> _sorted(Iterable<DictionaryInfo> dictionaries) {
    final list = dictionaries.toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }
}
