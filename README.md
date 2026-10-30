# Rikai-Mobile

An Android Japanese reader and dictionary whose core runs on-device. Take a
photo or paste text, run OCR (PaddleOCR for horizontal, MangaOCR for vertical),
tokenize with the user's UniDic, show furigana, and look up any word in the
user's MDict dictionaries. OCR models may be downloaded during setup; after
that, OCR, tokenization, and dictionary lookup are offline. Phase 6 (planned)
adds an optional dictionary assistant that can call a user-configured LLM
provider; it is not part of the current build.

## Status

Phases 1–4 are working end to end on the Android emulator with a real
UniDic and MDict dictionary. **Phase 4.5 (OCR quality and performance
convergence) was accepted on arm64/real devices on 2026-10-30.** **Phase 5
(corpus/history, onboarding and release polish) was completed and
user-confirmed on a cold-booted emulator on 2026-10-30.** Phase 6 (dictionary
assistant) is in progress: P6.1–P6.5 core is implemented (capability ports,
provider adapters, secure key storage, dictionary familiarization, fixed
orchestrator/evidence/citation pipeline, Agent page and provider settings).
P6.6 (multi-OCR variants/repair) and P6.7 (annotation DSL, Markdown/ruby/pitch,
history/release polish) are not implemented.

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
- Photo-set save action stores the photo + OCR text in the local corpus; both
  the corpus list and detail page show full photos, font/furigana controls and
  copy (card bottom-right in the list, photo bottom-right in the detail), and
  the detail page shows OCR + tokenization with corpus-to-corpus navigation
- First-run onboarding: local-only boundary, storage permission status, UniDic,
  optional MDict/OCR setup links and a licence acknowledgement, with skip and
  a “重新查看新手引导” entry in settings
- Corpus lifecycle: typed text can be saved from the reader, text-only entries
  render without a photo pane, photos are EXIF-baked and compressed to a
  max-2048 quality-85 JPEG, and the corpus can be cleared per entry or wholesale
- Optional “自动保存识别结果” (off by default) saves each fresh OCR result once
  per photo/mode/text; settings also clear the extracted MDict resource cache
  without touching dictionary files
- Phase 5 release packaging: arm64 release APK builds successfully
  (`app-arm64-v8a-release.apk`, about 60 MB); the onboarding/corpus/settings
  flows were user-confirmed on a cold-booted emulator. The APK currently uses
  the debug keystore for development.
- MDict folder import recursively scans subfolders, previews importable/existing/
  unsupported dictionaries, and imports selected entries with progress, then
  returns directly to dictionary management
- Reader lookup keeps the keyboard closed before/after the token sheet
- Phase 4 vertical MangaOCR: one shared DBNet pass, bubble clustering/crop
  planning, RTL reading order, and a Chinese prompt when the model is missing
- Phase 4.5 lazy model sessions: horizontal-only OCR never loads MangaOCR;
  optional sessions are created on demand or by background prewarm, and
  readiness reports availability separately from loaded state
- Stat-first model fingerprints/readiness; SHA-256 remains on download/import
  and is cached per file revision, removing repeated full hashes from page
  re-entry
- Automatic mode routes horizontal/vertical from box geometry and optional
  PP-LCNet orientation, returns exactly one engine, and falls back to PaddleOCR
  when MangaOCR confidence is low; confident 90/270 pages are rotated and
  re-detected, and mild diagonal photos are deskewed
- Upside-down horizontal pages get one 180° re-run when the orientation set is
  installed; MangaOCR grouping uses size-aware gaps and filters low-confidence
  noise
- Manual “旋转” rotates the private photo copy 90° clockwise and re-runs OCR;
  a manual mode reuses a compatible auto result when safe
- MDict import accepts `Encrypted: 2` dictionaries and recovers same-basename
  MDD resources; merged lookup/search dictionary chips use deep blue selection,
  unique short names, wrapping, single/multi mode and a first “全选” option
- Model downloads survive leaving the page unless stopped, resume from `.part`
  files, try hf-mirror.net before Hugging Face, and can be cleaned from settings
- MangaOCR and orientation models can be downloaded or locally imported from
  the existing model page
- OCR text flows into the same reader and MDict lookup UI

### Phase 6 in progress: dictionary assistant

Phase 6 P6.1–P6.5 core is implemented; the home screen now has five actions:
`拍照识别`, `查句子`, `查单词`, `历史记录`, and `词典助手`.

- Capability ports wrap the existing OCR/UniDic/MDict services; a pure
  `LookupGateway` keeps UI and Agent lookup behavior aligned; the unused
  `OcrWorkflow` wrapper was removed on 2026-10-31.
- Provider adapters support OpenAI-compatible endpoints (DeepSeek/custom) and
  Anthropic Messages API. API keys use Android secure storage; the model path is
  text-only and a runtime guard rejects image/file payloads. The opaque
  `image_id` handle is allowed.
- Dictionary familiarization samples bounded entries, asks the small model for
  a profile, requires explicit user save/skip/decline, and caches by dictionary
  fingerprint. UniDic profiling is deterministic.
- The fixed orchestrator runs OCR → familiarization → tokenization → evidence →
  reasoning → quote/citation validation. It prefetches every unique
  word/grammar target in the user's dictionary order; model output cannot invent
  citations or reorder dictionaries. Strict mode requires citations and rejects
  unsourced facts; loose mode labels model supplements.
- The Agent page supports text/gallery input (local OCR only), per-session
  dictionary selection, strict/loose mode, provider choice, stage progress,
  cancellation, original-text quotes, evidence cards and clickable citations
  that open the existing entry page. Provider settings are available under
  Settings → 词典助手.

Still pending: P6.6 multi-OCR variants/dictionary-assisted repair and P6.7
annotation DSL/Markdown/ruby/pitch/history/release polish. Real-network provider
calls, secure-storage device I/O, real-dictionary `sample`/`suggest` and arm64
Agent acceptance still need device verification. See
[docs/phase6-status.md](docs/phase6-status.md) for the current implementation
record, [docs/phase6-agent-design.md](docs/phase6-agent-design.md) for the design
and [docs/phase6-agent-contracts.md](docs/phase6-agent-contracts.md) for the
tool/JSON-schema contracts.

Next: finish P6.6/P6.7 and complete arm64/device acceptance. See
[docs/phase5-status.md](docs/phase5-status.md),
[docs/phase4.5-status.md](docs/phase4.5-status.md),
[docs/phase6-agent-design.md](docs/phase6-agent-design.md),
[docs/phase4-status.md](docs/phase4-status.md),
[docs/phase3-status.md](docs/phase3-status.md),
[docs/phase2-status.md](docs/phase2-status.md),
[docs/phase1-status.md](docs/phase1-status.md) and
[docs/phase0-status.md](docs/phase0-status.md) for design and verified results.

## Requirements

- Flutter 3.38+ / Dart 3.10+
- Android SDK 36, NDK 28.2.13676358
- User-supplied UniDic (MeCab compiled dictionary) and MDict `.mdx` files
- **HarmonyOS Sans SC Regular**, downloaded by the user (not in this repository):
  place it at `assets/fonts/HarmonyOS_Sans_SC_Regular.ttf`; see
  [assets/fonts/README.md](assets/fonts/README.md)

### Phase 6 planned (not required for the current build)

- Network access only when the optional dictionary assistant is configured and
  the user explicitly sends a request.
- A user-supplied API key and provider/model configuration for DeepSeek, Claude,
  or another supported endpoint.
- API keys must never be committed, logged, exported, or included in issue
  reports. Images remain local and are processed by on-device OCR only.

## Build

Download the font first (see above), then:

```powershell
cd C:\Projects\Rikai-Mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

For an arm64 release build, see [docs/dev-setup.md](docs/dev-setup.md): if a
previous debug/integration-test run left `integration_test` in the generated
plugin registrant, run the `--config-only` release command once before
`flutter build apk --release --target-platform android-arm64 --split-per-abi`.
UI work must follow [docs/design-tokens.md](docs/design-tokens.md). The current
build contains no Agent/provider implementation, so Phase 6
provider/fake-server tests are not part of the current build or test suite.

## Documents

- [Development plan](docs/DEVELOPMENT_PLAN.md)
- [Design tokens](docs/design-tokens.md)
- [Phase 0 status](docs/phase0-status.md)
- [Phase 1 status](docs/phase1-status.md)
- [Phase 2 status](docs/phase2-status.md)
- [Phase 3 status](docs/phase3-status.md)
- [Phase 3.5 capture/import status](docs/phase3.5-status.md)
- [Phase 4 vertical OCR status](docs/phase4-status.md)
- [Phase 4.5 OCR convergence status](docs/phase4.5-status.md)
- [Phase 5 corpus/onboarding/release status](docs/phase5-status.md)
- [Phase 6 agent design v2](docs/phase6-agent-design.md)
- [Phase 6 agent contracts](docs/phase6-agent-contracts.md)
- [Phase 6 implementation status](docs/phase6-status.md)
- [Development setup](docs/dev-setup.md)
- [Models](docs/models.md)
- [Architecture decisions](docs/adr/)
- [Third-party notices](THIRD_PARTY_NOTICES.md), [NOTICE](NOTICE)

## Licenses

Rikai-Mobile adapts code from overlay-translator (Apache-2.0) and evaluates
PaddleOCR4Android (MIT). MeCab/mecab_for_dart are BSD-3. ONNX Runtime is MIT.
UniDic and MDict dictionaries are supplied by the user and are not
redistributed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The planned Phase 6 assistant would use user-supplied API keys and a
user-selected remote LLM provider. Provider terms and privacy policies apply;
Rikai-Mobile would not redistribute LLM weights, keys, or conversations. Images
would remain on-device; only locally extracted text and tool results would be
sent when the user explicitly initiates a request.
