# Rikai-Mobile

An Android Japanese reader and dictionary whose core runs on-device. Take a
photo or paste text, run OCR (PaddleOCR for horizontal, MangaOCR for vertical),
tokenize with the user's UniDic, show furigana, and look up any word in the
user's MDict dictionaries. OCR models may be downloaded during setup; after
that, OCR, tokenization, and dictionary lookup are offline. Phase 6 adds an
optional dictionary assistant that can call a user-configured LLM provider;
P6.1–P6.5, the 2026-10-31 feedback waves 1–3, the P6.6 multi-OCR core, and
P6.7 history/pitch/provider-test/Markdown/annotation v1 are implemented.
Feedback wave 4 device acceptance, P6.6 device-quality checks, full text/group
DSL and release polish remain pending.

> Current test/device/performance/build/environment data lives in
> [docs/01-规范/项目数据.md](docs/01-规范/项目数据.md). Normative MUST/MUST NOT rules
> live in [docs/01-规范/项目规则.md](docs/01-规范/项目规则.md). Pitfalls and proven
> fixes live in [docs/01-规范/误区与踩坑.md](docs/01-规范/误区与踩坑.md). Phase 0–5
> implementation history lives in
> [docs/04-历史/项目历史.md](docs/04-历史/项目历史.md). Other documents link to
> them instead of copying current values, rule text, pitfall text or historical
> detail.

## Status

Phases 1–4 are working end to end on the Android emulator with a real
UniDic and MDict dictionary. **Phase 4.5 (OCR quality and performance
convergence) was accepted on arm64/real devices on 2026-10-30.** **Phase 5
(corpus/history, onboarding and release polish) was completed and
user-confirmed on a cold-booted emulator on 2026-10-30.** Phase 6 (dictionary
assistant) is in progress: P6.1–P6.5 core is implemented (capability ports,
provider adapters, secure key storage, dictionary familiarization, fixed
orchestrator/evidence/citation pipeline, Agent page and provider settings).
The 2026-10-31 feedback waves 1–3 are implemented. P6.6 multi-OCR comparison and
dictionary-assisted repair core is implemented (2026-11-02, automated tests);
its real-device quality acceptance remains. P6.7 history/pitch, provider test
connection, restricted Markdown preview and annotation v1 are implemented;
full text/group DSL, release polish and device/visual acceptance remain.

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
  (`app-arm64-v8a-release.apk`; size 见 [project-data](docs/01-规范/项目数据.md) §5);
  the onboarding/corpus/settings
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

Phase 6 P6.1–P6.5 core is implemented; 主页功能按钮的数量、顺序和固定文案见
[project-data](docs/01-规范/项目数据.md) §7，不在本文件重复。

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

Still pending: feedback wave 4 device acceptance for the 2026-10-31 backlog
(real provider/API key, arm64 Agent end-to-end, large-dictionary
suffix/incremental smoke, secure-storage device I/O), P6.6 real-device visual/
OCR/dictionary-candidate acceptance, P6.7 full text/group DSL, release polish
and device/visual acceptance. P6.6's explicit multi-OCR comparison, diff,
quality ranking and user-confirmed dictionary repair are implemented and
covered by fake-OCR/fake-lookup tests; this does not replace device
verification. The feedback plan and wave order are in
[docs/03-进度/设备反馈-2026-10-31.md](docs/03-进度/设备反馈-2026-10-31.md).
See [docs/03-进度/阶段6实现状态.md](docs/03-进度/阶段6实现状态.md) for the current implementation
record, [docs/02-设计/助手/助手设计.md](docs/02-设计/助手/助手设计.md) for the design
and [docs/02-设计/助手/助手契约.md](docs/02-设计/助手/助手契约.md) for the
field/state-machine/bracket-tag contracts (JSON Schemas are internal DTO/storage docs).

Next: finish feedback wave 4 device acceptance for the backlog, P6.6 device
quality checks and P6.7 device/visual acceptance. See
[docs/04-历史/阶段5状态.md](docs/04-历史/阶段5状态.md),
[docs/04-历史/阶段4.5状态.md](docs/04-历史/阶段4.5状态.md),
[docs/02-设计/助手/助手设计.md](docs/02-设计/助手/助手设计.md),
[docs/04-历史/阶段4状态.md](docs/04-历史/阶段4状态.md),
[docs/04-历史/阶段3状态.md](docs/04-历史/阶段3状态.md),
[docs/04-历史/阶段2状态.md](docs/04-历史/阶段2状态.md),
[docs/04-历史/阶段1状态.md](docs/04-历史/阶段1状态.md) and
[docs/04-历史/阶段0状态.md](docs/04-历史/阶段0状态.md) for design and verified results.

## Requirements

- 精确的 Flutter/Dart/SDK/NDK、测试和设备基线统一见
  [docs/01-规范/项目数据.md](docs/01-规范/项目数据.md) §1；本文件不重复具体版本号。
- User-supplied UniDic (MeCab compiled dictionary) and MDict `.mdx` files
- **HarmonyOS Sans SC Regular**, downloaded by the user (not in this repository):
  place it at `assets/fonts/HarmonyOS_Sans_SC_Regular.ttf`; see
  [assets/fonts/README.md](assets/fonts/README.md)

### Phase 6 optional Agent requirements

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
dart tool/verify.dart              # docs + analyze + test
dart tool/verify.dart --build      # also builds a debug APK
flutter build apk --debug
```

For an arm64 release build, see [docs/05-参考/开发环境与构建.md](docs/05-参考/开发环境与构建.md): if a
previous debug/integration-test run left `integration_test` in the generated
plugin registrant, run the `--config-only` release command once before
`flutter build apk --release --target-platform android-arm64 --split-per-abi`.
UI work must follow [docs/01-规范/设计规范.md](docs/01-规范/设计规范.md). The current
build contains P6.1–P6.5, the 2026-10-31 feedback waves 1–3, the P6.6
multi-OCR core, and P6.7 history/pitch/provider-test/Markdown/annotation v1;
feedback wave 4 device acceptance, full text/group DSL and release polish are
not yet implemented.

## Documents

- [Development plan](docs/04-历史/开发计划.md)
- [Project rules](docs/01-规范/项目规则.md)
- [Project data (single source)](docs/01-规范/项目数据.md)
- [Design tokens](docs/01-规范/设计规范.md)
- [Project tips (pitfalls)](docs/01-规范/误区与踩坑.md)
- [Project history (Phase 0–5)](docs/04-历史/项目历史.md)
- [Phase 0 status](docs/04-历史/阶段0状态.md)
- [Phase 1 status](docs/04-历史/阶段1状态.md)
- [Phase 2 status](docs/04-历史/阶段2状态.md)
- [Phase 3 status](docs/04-历史/阶段3状态.md)
- [Phase 3.5 capture/import status](docs/04-历史/阶段3.5状态.md)
- [Phase 4 vertical OCR status](docs/04-历史/阶段4状态.md)
- [Phase 4.5 OCR convergence status](docs/04-历史/阶段4.5状态.md)
- [Phase 5 corpus/onboarding/release status](docs/04-历史/阶段5状态.md)
- [Phase 6 agent design v2](docs/02-设计/助手/助手设计.md)
- [Phase 6 agent contracts](docs/02-设计/助手/助手契约.md)
- [Phase 6 implementation status](docs/03-进度/阶段6实现状态.md)
- [Agent docs / current Device feedback](docs/02-设计/助手/助手文档索引.md)
- [Development setup](docs/05-参考/开发环境与构建.md)
- [Models](docs/05-参考/模型.md)
- [Architecture decisions](docs/02-设计/架构决策/)
- [Third-party notices](THIRD_PARTY_NOTICES.md), [NOTICE](NOTICE)

## Licenses

Rikai-Mobile adapts code from overlay-translator (Apache-2.0) and evaluates
PaddleOCR4Android (MIT). MeCab/mecab_for_dart are BSD-3. ONNX Runtime is MIT.
UniDic and MDict dictionaries are supplied by the user and are not
redistributed. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The optional Phase 6 assistant uses user-supplied API keys and a
user-selected remote LLM provider. Provider terms and privacy policies apply;
Rikai-Mobile does not redistribute LLM weights, keys, or conversations. Images
remain on-device; only locally extracted text and cleaned evidence are sent when
the user explicitly initiates a request. Binding privacy/security rules:
[docs/01-规范/项目规则.md](docs/01-规范/项目规则.md) R-SEC.
