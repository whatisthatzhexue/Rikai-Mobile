# Rikai-Mobile

An offline Android Japanese reader and dictionary. Take a photo or paste text,
run OCR (PaddleOCR for horizontal, MangaOCR for vertical), tokenize with the
user's UniDic, show furigana, and look up any word in the user's MDict
dictionaries — all in one app, without network access.

## Status

Phase 0 scaffold is in place:

- Flutter Android project (`com.rikai.mobile`, minSdk 26, arm64 release)
- Vendored MeCab (`packages/mecab_for_dart`, BSD-3) with a read-only UniDic
  path patch
- ONNX Runtime OCR plugin skeleton (`packages/rikai_ocr`)
- Model catalog with hf-mirror fallback (`assets/models/manifest.json`)
- License/attribution files and repository hygiene
- Basic kana utilities + tests; debug APK builds

Next: Phase 1 (UniDic/MeCab service, tokens, furigana, reader).

## Requirements

- Flutter 3.38+ / Dart 3.10+
- Android SDK 36, NDK 28.2.13676358
- User-supplied UniDic (MeCab compiled dictionary) and MDict `.mdx` files

## Build

```powershell
cd C:\Projects\Rikai-Mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

See [docs/dev-setup.md](docs/dev-setup.md) for toolchain and device setup.

## Documents

- [Development plan](docs/DEVELOPMENT_PLAN.md)
- [Development setup](docs/dev-setup.md)
- [Models](docs/models.md)
- [Architecture decisions](docs/adr/)
- [Third-party notices](THIRD_PARTY_NOTICES.md), [NOTICE](NOTICE)

## Licenses

Rikai-Mobile adapts code from overlay-translator (Apache-2.0) and evaluates
PaddleOCR4Android (MIT). MeCab/mecab_for_dart are BSD-3. ONNX Runtime is MIT.
UniDic and MDict dictionaries are supplied by the user and are not
redistributed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
