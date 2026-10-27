# Rikai-Mobile

An offline Android Japanese reader and dictionary. Take a photo or paste text,
run OCR (PaddleOCR for horizontal, MangaOCR for vertical), tokenize with the
user's UniDic, show furigana, and look up any word in the user's MDict
dictionaries — all in one app, without network access.

## Status

Phase 1 is working end to end with a real UniDic on the Android emulator:

- In-place MeCab/UniDic tokenization in a long-lived worker isolate, private
  `mecabrc`, CSV-aware parsing of quoted UniDic fields
- 29-field token mapping, furigana, lookup candidates and token offsets
- Text reader with content-word highlighting, furigana toggle, font size and
  copy; settings with UniDic validation and All Files Access
- Native All Files Access MethodChannel (`rikai/storage_permission`)
- OCR plugin skeleton, model catalog and license files from Phase 0

Next: Phase 2 (MDict lookup, search and offline WebView rendering). See
[docs/phase1-status.md](docs/phase1-status.md) and
[docs/phase0-status.md](docs/phase0-status.md) for verified results.

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
- [Phase 0 status](docs/phase0-status.md)
- [Phase 1 status](docs/phase1-status.md)
- [Development setup](docs/dev-setup.md)
- [Models](docs/models.md)
- [Architecture decisions](docs/adr/)
- [Third-party notices](THIRD_PARTY_NOTICES.md), [NOTICE](NOTICE)

## Licenses

Rikai-Mobile adapts code from overlay-translator (Apache-2.0) and evaluates
PaddleOCR4Android (MIT). MeCab/mecab_for_dart are BSD-3. ONNX Runtime is MIT.
UniDic and MDict dictionaries are supplied by the user and are not
redistributed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
