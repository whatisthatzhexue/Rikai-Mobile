# Phase 3.5 status — capture/model/import review and redesign

Date: 2026-10-29
Base: Phase 3 (`docs/phase3-status.md`)
Scope: `docs/phase3-review.md`, `docs/capture-redesign-requirements.md`

## Confirmed assumptions

- One `.mdx` = one dictionary; same-directory `.mdd`/`.css` auto-associated.
- Photo set is an app-session list: leaving capture keeps it, app restart clears
  unsaved photos.
- OCR is on demand with a cache keyed by **photo + mode + model fingerprint**.
- “Delete original” is best-effort and defaults off; if the system does not
  expose a deletable original, only the session copy is removed with a notice.
- Changing the model directory defaults to migrating existing models; “switch
  only” remains available.
- Vertical recognition and full corpus/history management stay phase-gated;
  the vertical option is disabled with a note.

## Review fixes

### High

- **H1 local model import** now matches by role: exact manifest names first,
  then pinned size + extension, so upstream `inference.onnx` (det/rec) and
  `inference.yml` (keys) import correctly. Existing valid files are reused;
  copies are staged as `.importing` and validated before any live file is
  replaced. The model page refreshes after both success and failure.
- **H2 initialization cancellation**: the photo set owns a run token, cancels
  the old run and checks the token after model initialization; a cancel during
  model loading never calls `recognize` or opens the reader.
- **H3 exactly-once replies**: native recognize uses `CoroutineStart.ATOMIC`,
  an `AtomicBoolean` reply guard and a `finally` fallback, so a cancel before
  dispatch still resolves the Dart future with `CANCELLED`.

### Medium

- **M1 SHA-256**: verified hashes for all PaddleOCR, MangaOCR and orientation
  files are in `assets/models/manifest.json`.
- **M2 session reuse**: the native engine reuses sessions for the same paths,
  `OcrService` keeps one initialized pair and fingerprint across photos, and
  `SessionOptions` is closed after session creation.
- **M3 resume safety**: HTTP 416 deletes the `.part`; a 206 whose
  `Content-Range` start differs from the local part is discarded, so an error
  page can no longer poison a resumed download.
- **M4 OOM**: model-load OOM maps to `OOM`, bitmap rotation no longer catches
  `OutOfMemoryError`, and the UI shows the native error.
- **M5 read-only status**: path resolution and directory creation are separate;
  status/model page loading does not create directories and a permission error
  yields an unavailable-directory state instead of a blank page.
- **M6 stale model state**: the photo set surfaces model/OCR errors and links to
  model settings; the old capture page readiness row is gone. Returning from
  model settings compares fingerprints and clears photo caches when needed.
- **M7 leaving capture**: all OCR awaits have run-token/disposed checks; page
  disposal cancels the native task; sessions live in the app-level OCR service.

### Low

- Progress now reports recognition completion per line (no N+1), and the UI does
  not flip from full to indeterminate when recognition starts.
- New pages use 14sp helpers, loading text and flat layouts; camera tokens and
  shared round action buttons were added to `app_tokens.dart`.
- Shared `formatBytes`; one download implementation; mirror uses the saved
  setting consistently; FilePicker cache is cleared after model import;
  `onDetachedFromEngine` closes sessions off the platform thread.
- `ocrModelManifestProvider` disables Riverpod retry.
- `composeOcrText` preserves repeated lines (lyrics/dialogue).
- Mirror input is validated as an http(s) URL with a host.
- Installed MangaOCR files can be deleted even before Phase 4 download support.
- `cancel()`/`dispose()` go through OcrException conversion.
- OCR reader uses a page-local controller, so it cannot overwrite a global draft
  or a lower ReaderPage.
- Empty model manifests are rejected and `isInstalled` requires a non-empty set.

P1 (vertical ordering) remains a Phase 4 requirement; current vertical mode is
disabled in the UI.

## Feature work

### MDict folder import

- `lib/services/mdict/dictionary_scanner.dart`: isolate-based recursive scan,
  case-insensitive `.mdx`, sibling `.mdd`/directory `.css`, symlink-safe.
- `lib/features/settings/dictionary_import_page.dart`: empty hint field,
  directory picker, scan/probe states, checkable results with
  importable/existing/unsupported status, current/total progress, cancel, and
  a single primary import button.
- Scan rows no longer append the English `MDD`/`CSS` counts; dictionary
  management labels them as “资源/样式/无资源”. Import completes by returning
  directly to dictionary management without a result dialog; failed/cancelled
  batches get a non-blocking count snackbar.
- Dictionary management gets a folder-import action and empty-state entry; no
  files are copied.

### Reader keyboard

- Token taps unfocus the editor before opening the lookup sheet; sheet dismissal
  clears focus again. The lookup sheet has its own focus scope and no close X.
- The OCR reader uses a local controller; the normal text-input route keeps the
  app-lifetime draft. Verified keypad stays hidden after dismissing the scrim.

### OCR model page

- User-facing intro, configurable model directory shown as 16sp SelectableText,
  change-directory with validation (read/write/free space), default migration
  with progress, switch-only option, occupied-space display, invalid-directory
  recovery, custom mirror validation, local import/delete/cancel.

### Capture and photo set

- `camera` plugin live preview with a semi-transparent bottom scrim, shutter,
  multi-photo gallery import and count badge; camera is released when opening
  the photo set or backgrounding and reacquired on return.
- App-session photo set with `BoxFit.contain` preview, OCR text/mode/cache,
  page navigation, auto recognition on photo/mode change, cancel/retry, and
  disabled vertical mode.
- The photo area can be enlarged/shrunk by dragging its bottom edge (single
  white bar, no grey pill), and a tap opens a black full-screen viewer with
  pinch zoom and pan.
- Delete and save are 52dp round actions fixed at the **screen**
  bottom-left/right. Delete confirms and defaults to not deleting originals;
  save uses the deep-blue header colour with a white icon and confirms before
  writing the photo + OCR text + mode + blocks to the local corpus.
- “分析句子” was removed. After OCR the page automatically tokenizes when
  UniDic is configured and renders the same `ReaderBlock` tokens as the text
  reader (tap a token to look up). Without UniDic it shows OCR text; a
  tokenization failure is a red banner over the top of the photo below the AppBar
  with a retry action, so it never covers the result area. Copy is a deep-blue
  bar at the photo's bottom-right; the reader options menu provides the same
  16/20/24/28 font sizes and furigana toggle.
- The OCR mode is stored in the capture session. Cache hits use the
  app-level `OcrService.fingerprint` before touching the models, so returning
  from model settings, the multi-select page or another page does not re-run
  OCR when mode/fingerprint are unchanged. Returning from model settings only
  clears the cache and forces recognition when the fingerprint changed.
- The multi-select page receives the current fingerprint and only recognizes
  photos without a matching cache entry; when all are cached it shows their
  text without a progress flicker. Its OCR preview is 20sp.
- Single Photo Set AppBar “多选” entry; the selection page uses the same round
  delete/save icons for batch operations, with confirmation. The duplicate
  “保存到语料库（后续支持）” buttons were removed.
- Model settings is centered; no duplicate text action. The mode selector,
  model-settings link and page arrows sit at the bottom; the arrow centre line
  matches the screen-corner buttons.

### Corpus

- `HistoryStore` (sqflite, app support dir) stores sessions and copies photos to
  `corpus/images`. The corpus list shows a large, uncropped photo with a red
  round delete action at its top-right, the full OCR result below, then the
  recognition date.
- Opening an entry goes to `/corpus-detail`: full photo with resize/zoom, OCR
  original, date, and a tokenized ReaderBlock section. Page arrows move between
  corpus entries, the title is “语料”, and only a bottom-left delete action is
  shown (no multi-select, orientation, model settings or save). All data and
  tokenization are local/offline.
- Full history/corpus management remains Phase 5.

## Verification

```text
flutter analyze  -> No issues found
flutter test     -> 107 tests passed
flutter build apk --debug -> success
```

Unit coverage added: model role/size import, existing-file fill, 416/Content-
Range reset, read-only status, migration, custom mirror, capture session mode
and cache, recursive dictionary scan, dictionary-title sanitization, and reader
line grouping.

Manual emulator checks:

- home layout: usage notice at the top, four deep-blue actions centred in the
  remaining space;
- live camera preview, shutter, gallery multi-select, photo-set OCR and
  text-to-reader flow;
- photo set automatically tokenized `ありがとう / 東京で食べた。` with UniDic and
  rendered ReaderBlocks; copy (bottom-right deep-blue bar) and the 16/20/24/28
  font menu worked;
- photo-area resize with the single white handle and full-screen pinch viewer
  opening from a photo tap;
- tokenization failure showed the red retry banner over the top of the photo
  without covering the OCR result area;
- returning from model settings and from multi-select reused cached OCR with
  no progress/re-recognition; multi-select showed cached text immediately and
  used 20sp previews;
- photo-set screen-corner delete/save actions (52 dp each, save deep blue);
  page-arrow centres aligned with the action centres;
- save confirmation; corpus list showed the full photo, top-right red delete,
  OCR text and date; corpus detail showed photo/OCR/tokens, corpus-to-corpus
  navigation, bottom-left delete and no save/multi/orientation/model controls;
- model page directory/space/mirror/installed state;
- MDict folder scan of `/sdcard/Download/rikai-mdict` showing title, size and
  “已在词典库中” without the English MDD/CSS suffix; importing a second MDX
  returned directly to dictionary management with no result dialog;
- reader token sheet opens with keyboard hidden and stays hidden when dismissed.

The Phase 3 OCR device suite was re-run after the native reply/session changes:
2/2 passed, readiness `reused:false`, recognition 235 ms, confidence 1.000.
The host emulator cannot resolve hf-mirror/Hugging Face, so live network model
download is still pending a network-capable device.

## Known limitations

- No arm64 device; camera/OCR performance remains functional-only on x86_64.
- Gallery “delete original” is best-effort because image_picker exposes a cache
  copy, not a MediaStore delete handle; the UI falls back to session removal.
- Corpus saves photo + OCR text + blocks + mode/time and re-tokenizes on detail
  open; full history management remains Phase 5.
- Vertical OCR and orientation routing remain Phase 4.
- Batch corpus save was verified on the emulator for a single selected photo;
  a multi-photo/large-set pass remains desirable.
- The corpus detail photo/token sections are read-only apart from delete and
  navigation; editing/exporting corpus text remains Phase 5.
