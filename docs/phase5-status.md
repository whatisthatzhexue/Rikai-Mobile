# Phase 5 status — corpus, polish and release

Date: 2026-10-30
Closed: 2026-10-30 (user-confirmed emulator/device test pass)
Base: Phase 4.5 (`docs/phase4.5-status.md`), closed on 2026-10-30
Scope: complete corpus/history lifecycle, first-run onboarding, settings polish,
error/empty states, licence/about entry points, tests and release packaging.

> **Status: complete.** The user confirmed the Phase 5 test pass on 2026-10-30.
> Phase 6 remains design-only and must not start before the user approves the
> design and implementation plan.

## Implemented

### First-run onboarding

- New route `/onboarding` and `lib/features/onboarding/onboarding_page.dart`.
  A fresh install opens it instead of the home page; `RikaiApp` chooses the
  initial route from the persisted setting.
- The guide shows the local-only boundary, then a setup checklist:
  - storage permission (read-only status; opens All Files Access or the legacy
    permission request);
  - UniDic path (configured/not configured; opens settings);
  - MDict dictionaries (count; opens dictionary management);
  - OCR models (optional; opens model settings).
- A licence/boundary acknowledgement checkbox gates “开始使用”. “跳过” and the
  settings action “重新查看新手引导” are available. Existing installs that already
  have a UniDic path are treated as completed so an update does not block them.
- The setting is persisted as `app_onboarding_completed`.

### Corpus/history lifecycle

- `HistoryStore` now supports:
  - `saveText` for text-reader sessions without a photo;
  - `clear` to delete every row and every copied image;
  - `imageBytes` for storage reporting;
  - deterministic newest-first ordering when several saves share a millisecond;
  - image compression before storage: EXIF orientation is baked, the longest
    edge is limited to 2048 px, and the result is a quality-85 JPEG. Unsupported
    source formats fall back to a byte-for-byte copy so saving never fails.
- The reader has a “保存到语料” AppBar action; it saves the current text even
  when UniDic is not configured.
- The photo set and multi-select page share `capture_corpus.dart` for block JSON
  and photo saving. Manual saving is unchanged.
- New optional setting “自动保存识别结果” (default off). When enabled, a fresh
  OCR result is saved automatically once per photo/mode/text within the session;
  cached results and repeated page visits do not duplicate it.
- Corpus page:
  - overflow menu “清空语料” with confirmation;
  - friendly error state without raw exceptions;
  - text-only entries render a “文本语料” placeholder instead of a broken image.
- Corpus detail:
  - no photo pane for text-only entries, with a copy action in the compact
    header;
  - friendly error state; existing tokenization/navigation/delete behaviour is
    unchanged.

### Settings and storage polish

- New “语料与存储” section:
  - auto-save switch;
  - “清空语料” with confirmation;
  - “清除词典资源缓存” removes extracted MDD images/audio and invalidates the
    in-memory rendered-entry cache; dictionary files are untouched.
- New “关于与帮助” section with help, copyright/open-source licences, and a
  “重新查看新手引导” action. `/help` and `/copyright` are now router routes in
  addition to the drawer entries.
- Existing settings remain flat white sections; no cards were introduced.

### Licences and documentation

- `CopyrightPage` continues to list MeCab/mecab_for_dart, dict_reader,
  ONNX Runtime, PaddleOCR models, MangaOCR, overlay-translator,
  PaddleOCR4Android, HarmonyOS Sans, UniDic and user-supplied MDict content,
  with the Flutter licence page.
- README, CLAUDE.md, the development plan and design tokens were updated for
  the Phase 4.5 close and Phase 5 status.

## Tests

- `test/onboarding_test.dart`: first-run acknowledgement and skip paths.
- `test/history_store_test.dart`: photo-block JSON serialization and the
  corpus-image resize/JPEG contract (pure functions; no database or desktop
  SQLite dependency).
- `test/reader_save_test.dart`: saving typed reader text through the AppBar.
- `test/settings_store_test.dart`: onboarding/auto-save persistence and the
  existing-UniDic heuristic.
- Existing widget tests now seed `app_onboarding_completed=true` so they continue
  to exercise the home page.

An attempted `sqflite_common_ffi` dev dependency was removed: its transitive
`sqlite3` native-assets hook tries to download a prebuilt library from GitHub
during the Android build, which is unavailable in this environment and broke
`flutter build apk`. Corpus behavior is therefore covered with UI tests and
pure-function tests rather than a desktop SQLite harness.

Verification:

```text
flutter analyze  -> No issues found
flutter test     -> 149 tests passed
flutter build apk --debug -> success
flutter build apk --release --target-platform android-arm64 --split-per-abi
  -> build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (60.1 MB)
```

The user confirmed the Phase 5 test pass on a cold-booted x86_64 emulator on
2026-10-30. The release APK is built with the debug keystore for development.

## Release build note

A debug/integration-test build can leave `integration_test` in
`GeneratedPluginRegistrant.java`, which makes the release Java compile fail.
Regenerate release tooling before the release build:

```bash
flutter build apk --release --target-platform android-arm64 --split-per-abi --config-only
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

`flutter clean` alone did not remove the stale registrant in this environment.
See `docs/dev-setup.md` and CLAUDE.md pitfall #130.

## Remaining before distribution

- Release signing still uses the debug keystore (`android/app/build.gradle.kts`
  has a TODO). Replace it before distributing outside development.
- Consider an optional legal/privacy page link for provider terms once Phase 6
  exists; Phase 6 remains unimplemented.
- Re-run the OCR/MDict device suites after future model or rendering changes.

## Next stage

Phase 6 is design-only. Start it only after the user approves the design and
implementation plan; see `docs/phase6-agent-design.md` and
`docs/phase6-agent-contracts.md`.

## Known limitations

- Auto-save deduplication is session-scoped (photo id + mode + text). Reopening
  the app with a new photo session can create a new corpus entry; this is
  intentional because session photo ids do not survive a restart.
- The onboarding guide is status-driven rather than embedding the UniDic/model
  pickers; it links to the existing settings pages to avoid duplicating complex
  validation and migration flows.
- Corpus thumbnails still decode the stored JPEG at display size; very large
  corpora may benefit from generated thumbnails in a later phase.
