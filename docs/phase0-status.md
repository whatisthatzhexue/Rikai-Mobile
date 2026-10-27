# Phase 0 status

Date: 2026-10-27
Project root: `C:\Projects\Rikai-Mobile`

## Completed

- Flutter Android app scaffold (`com.rikai.mobile`, minSdk 26, target/compile 36,
  NDK 28.2.13676358).
- Dependencies resolved: Riverpod, go_router, dict_reader, image_picker, image,
  dio, crypto, path_provider, shared_preferences, sqflite,
  flutter_inappwebview, package_info_plus, url_launcher.
- Vendored `mecab_for_dart` 2.0.5 (BSD-3) with a read-only-UniDic patch:
  `src/dart_ffi.cpp` only adds `-r <dicdir>/mecabrc` when that file exists.
- `packages/rikai_ocr` plugin skeleton with ONNX Runtime 1.28.0 for Android.
- Model manifest with hf-mirror/HF URLs, sizes, licenses, and MangaOCR warning.
- Repository hygiene: `.gitignore`, `NOTICE`, `THIRD_PARTY_NOTICES.md`,
  per-component licenses and modification notes, ADRs, dev setup docs.
- Kana utilities + unit tests; home page scaffold.
- Debug APK builds successfully from `C:\Projects\Rikai-Mobile`:
  `build/app/outputs/flutter-apk/app-debug.apk`.
  - Contains `libmecab_dart.so` for arm64-v8a, armeabi-v7a, x86_64.
  - Contains ONNX Runtime and JNI libs for the same ABIs.
  - Debug APK is ~260 MB (all ABIs + debug runtime); release will be arm64-only.

## Verification run

```text
flutter analyze  -> No issues found
flutter test     -> 8 tests passed
flutter build apk --debug -> success
```

## MDict spike (host-side Dart, real dictionary)

`tool/spike_mdict.dart` (run in an isolated package to avoid the Windows MeCab
native-assets hook):

- `initDict()`: ~200 ms
- entries: 463,312
- header: UTF-8, MDict 2.0, title `講談社 日本語大辞典 第二版 双解版`
- `locateAll("東京")`: <1 ms; entry is `@@@LINK=とうきょう【東京】`
  and must be resolved before rendering.
- after redirect resolution: full HTML entry (724 chars for 東京,
  1,903 chars for 食べる).
- process RSS after init: ~400 MB (Dart VM + key list + block caches).
  Target device should have ≥6 GB RAM; measure on device in Phase 2.
- prefix search works and returns Japanese suggestions.

## Known issues / remaining spikes

- Android MeCab with the real 1.3 GB UniDic has not been loaded on a device yet;
  this is the main Phase 0/1 gate. The native `.so` is built and packaged.
- Running the root package with `dart run` on Windows triggers the
  `mecab_for_dart` native-assets hook, which fails in this Visual Studio
  environment. This does not affect Android builds; use an isolated Dart package
  for host-side MDict scripts.
- ONNX Runtime models have not been executed yet (plugin is a skeleton).
- The Gradle global script caches on this machine were corrupted after
  interrupted builds; see `docs/dev-setup.md` for the recovery procedure.
