# Rikai-Mobile

An offline Android Japanese reader and dictionary. Take a photo or paste text,
run OCR (PaddleOCR for horizontal, MangaOCR for vertical), tokenize with the
user's UniDic, show furigana, and look up any word in the user's MDict
dictionaries — all in one app, without network access.

## Status

Phases 1–3 are working end to end on the Android emulator with a real
UniDic and MDict dictionary:

- In-place MeCab/UniDic tokenization in a long-lived worker isolate, private
  `mecabrc`, CSV-aware parsing of quoted UniDic fields
- 29-field token mapping, furigana, lookup candidates and token offsets
- Text reader with content-word highlighting, furigana toggle, font size and
  copy; settings with UniDic validation and All Files Access
- MDict worker isolate: lazy in-place dictionaries, `@@@LINK` resolution,
  NFKC/width/kana/stripkey candidates, prefix suggestions and MDD resources
- Offline WebView entry rendering with scripts/network disabled, CSS injection,
  sanitized HTML and MDD images rewritten to local files
- Search page, reader lookup sheet, dictionary management (add/enable/reorder/
  revalidate/delete), configurable per-dictionary entry limit (unlimited by
  default), and single-result entry pages with 查看全部 for homographs
- Blue/white design tokens with compact components, a deep-blue app bar on
  every page, large centered deep-blue home actions, square left drawer,
  branded splash/launcher icon, and font switching/help/copyright pages
- HarmonyOS Sans SC is downloaded by the user (not in this repository; see
  `assets/fonts/README.md`); the system font can be selected in the drawer
- Phase 3 horizontal PaddleOCR: PP-OCRv5 det/rec via ONNX Runtime with a live
  camera, multi-photo session, per-photo/mode/model OCR cache, photo navigation,
  batch selection, and EXIF-corrected max-2048 preprocessing
- Photo set auto-tokenizes OCR text with UniDic and renders it like the text
  reader; copy and font/furigana controls stay available without UniDic
- Resizable photo area with a white drag handle and a full-screen pinch-zoom
  photo viewer; OCR/session caches survive page navigation
- Model manager with configurable directory/migration, hf-mirror → Hugging Face
  → custom mirror, resumable SHA-256-verified downloads, and local import
- Photo-set save action stores the photo + OCR text in the local corpus; the
  corpus list shows full photos + OCR + date, and a detail page shows the photo,
  OCR and tokenization with corpus-to-corpus navigation
- MDict folder import recursively scans subfolders, previews importable/existing/
  unsupported dictionaries, and imports selected entries with progress, then
  returns directly to dictionary management
- Reader lookup keeps the keyboard closed before/after the token sheet
- OCR text flows into the same reader and MDict lookup UI; vertical MangaOCR
  is Phase 4

Next: Phase 4 (vertical MangaOCR and automatic orientation). See
[docs/phase3-status.md](docs/phase3-status.md),
[docs/phase2-status.md](docs/phase2-status.md),
[docs/phase1-status.md](docs/phase1-status.md) and
[docs/phase0-status.md](docs/phase0-status.md) for verified results.

## Requirements

- Flutter 3.38+ / Dart 3.10+
- Android SDK 36, NDK 28.2.13676358
- User-supplied UniDic (MeCab compiled dictionary) and MDict `.mdx` files
- **HarmonyOS Sans SC Regular**, downloaded by the user (not in this repository):
  place it at `assets/fonts/HarmonyOS_Sans_SC_Regular.ttf`; see
  [assets/fonts/README.md](assets/fonts/README.md)

## Build

Download the font first (see above), then:

```powershell
cd C:\Projects\Rikai-Mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

See [docs/dev-setup.md](docs/dev-setup.md) for toolchain and device setup.
UI work must follow [docs/design-tokens.md](docs/design-tokens.md).

## Documents

- [Development plan](docs/DEVELOPMENT_PLAN.md)
- [Design tokens](docs/design-tokens.md)
- [Phase 0 status](docs/phase0-status.md)
- [Phase 1 status](docs/phase1-status.md)
- [Phase 2 status](docs/phase2-status.md)
- [Phase 3 status](docs/phase3-status.md)
- [Phase 3.5 capture/import status](docs/phase3.5-status.md)
- [Development setup](docs/dev-setup.md)
- [Models](docs/models.md)
- [Architecture decisions](docs/adr/)
- [Third-party notices](THIRD_PARTY_NOTICES.md), [NOTICE](NOTICE)

## Licenses

Rikai-Mobile adapts code from overlay-translator (Apache-2.0) and evaluates
PaddleOCR4Android (MIT). MeCab/mecab_for_dart are BSD-3. ONNX Runtime is MIT.
UniDic and MDict dictionaries are supplied by the user and are not
redistributed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
