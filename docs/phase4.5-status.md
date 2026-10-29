# Phase 4.5 status — OCR quality and performance convergence

Date: 2026-10-29
Base: Phase 4 (`docs/phase4-status.md`)
Scope: OCR responsiveness, orientation, auto routing and vertical quality.
Phase 5 remains paused until Phase 4.5 passes real-device acceptance.

## Why Phase 4.5 exists

Phase 4 is a working MVP, not a finished OCR engine. The main costs were in the
pipeline around the models rather than the models themselves:

- every readiness check loaded all installed optional models;
- runtime path resolution verified the full SHA-256 of every model file;
- auto routing chose one engine for the whole page;
- 90/270 document orientation was only a hint;
- MangaOCR was a compact pipeline with no noise filter or size-aware grouping.

Phase 4.5 addresses those before Phase 5 adds corpus/history/release work.

## Implemented

### 4.5-A — responsiveness and model lifecycle

- `PaddleOcrEngine.initialize` now loads only the mandatory PaddleOCR det/rec
  sessions. MangaOCR and orientation paths are registered but their sessions are
  lazy.
- `prepare(mode)` / `RikaiOcr.prepare` warm the optional sessions needed by a
  mode. Horizontal mode never creates MangaOCR sessions.
- Readiness now separates availability from loaded state:
  `mangaAvailable`, `mangaLoaded`, `docOrientationAvailable`,
  `docOrientationLoaded`, `textLineOrientationAvailable`,
  `textLineOrientationLoaded`. Existing `mangaReady`/`*Ready` keys remain
  availability flags for UI compatibility.
- `OcrService.ensureReady` is single-flight, reuses the in-session fingerprint,
  and accepts `refresh: true` after returning from model settings.
- The photo set preloads optional sessions in the background after a cached or
  completed result, without blocking the first result.
- Runtime fingerprints are stat-based. Runtime path resolution and the model
  page's installed-status check use file existence and the pinned size;
  SHA-256 remains on downloads, imports and migrations, cached per
  path/size/mtime. The native ONNX/keys loader is the final content check for
  existing files.

### 4.5-B — orientation and auto routing

- The document-orientation model now returns angle, probability and top-1/top-2
  margin. A confident 90/270 label rotates the image by the corrective angle and
  re-runs DBNet.
- The doc model runs only when image aspect and DBNet layout disagree:
  landscape + vertical boxes, or portrait + horizontal boxes. Upright tategaki,
  upright landscape text and square pages skip it.
- Text-line 180° correction now runs only in auto horizontal mode, not in manual
  horizontal mode.
- A mild horizontal deskew (2°–12°) is applied after DBNet when the page is not
  vertical and no 90/270 correction already ran. This targets phones held
  diagonally without re-processing rotated pages twice.
- Auto mode always returns one engine, never a mixed result. If MangaOCR's
  average block confidence is below 0.75, auto falls back to PaddleOCR for that
  page rather than returning low-confidence garbage.
- Changing the mode selector now forces a fresh recognition instead of reusing
  the previous auto/manual cache entry.

### 4.5-C — vertical quality

- Bubble-clustering gap and crop padding scale with the median detected text
  size instead of using fixed 18 px / 6 px values.
- Dense vertical regions are split into at most three text bands per 224 crop
  (horizontal regions keep six), so book columns are not squeezed into one crop.
- MangaOCR output is sanitized (replacement/control characters removed) and
  low-confidence bubbles are dropped.
- Existing bubble/crop/RTL ordering is preserved; no upstream mask/panel
  pipeline was imported.

### Cache and manual correction

- Manual horizontal mode reuses a compatible auto result whose engine is
  `paddle_v5`; manual vertical reuses an auto result whose engine is
  `manga_ocr`. Auto results are always one engine after the routing fix.
- The photo set has a “旋转” action that rotates the private session copy 90°
  clockwise, clears that photo's OCR cache, evicts the image cache and
  re-recognizes. Device originals are never modified.

## Device-feedback fixes (2026-10-29)

- **MDict import**: the worker no longer rejects `Encrypted: 2`. Several real
  dictionaries (漢字源, 日汉双解, 語源由来辞典, 研究社複合動詞) use this for a
  record-block layout that `dict_reader` can read; key-encrypted `Encrypted: 1`
  and v3 files remain unsupported. Import probing now succeeds for those files.
- **MDD resources**: the worker discovers same-basename `.mdd` siblings when an
  older registry has an empty `mddPaths`, and `mddKeyCandidates` strips `../` /
  `./` prefixes used by nested CSS/HTML. Verified with 漢字源 (Encrypted=2) and
  明鏡 (unencrypted) images through `MdictService` + `EntryRenderer`.
- **Entry titles**: result cards use `matchedKey` (the word shown by the entry
  page) instead of internal redirect ids such as `00044` or
  `@daijirin2-...`.
- **Search dictionary bar**: selected chips use the deep blue header colour;
  titles shorten to their shortest unique prefix and wrap; single/multi modes
  and a first “全选” chip are available in both search and the reader sheet.
- **Lookup sheet**: opening an entry no longer dismisses the sheet, so the user
  can inspect another sense without re-opening the word.
- **Corpus**: preview uses the compact two-column card layout; multi-select
  checkbox no longer has the black circular backing; corpus detail shows only
  the tokenized result (no raw OCR block or date). Saved photos remain under
  `getApplicationSupportDirectory()/corpus/images`, never the cache directory.
- **Camera permission**: the denied/unavailable screen keeps “从相册导入” and
  “照片集（N）” available; a centered toast confirms newly captured/imported
  photos.
- **External paths**: UniDic/model/MDict path selection prompts for All Files
  Access when the path is outside the app sandbox, then opens the system
  authorization page.
- **Downloads**: leaving the model page offers “同时停止下载” (unchecked by
  default); leaving without stopping keeps the download running. Interrupted
  downloads keep `.part` files and resume with HTTP Range. Settings now has
  “清除模型缓存”. `hf-mirror.net` is tried before Hugging Face, installed sizes
  use actual file lengths, and the download UI explains resumption.
- **Entry WebView exit**: the WebView is replaced by the page surface as soon as
  the route starts reversing; page transitions are 220 ms forward / 180 ms
  reverse to avoid platform-view stutter.
- **Copy/UI**: removed developer-facing phrases such as “模型按需下载，不随包
  分发”; added the beginner-friendly “边界说明” card below “使用前须知” on the
  home page.
- `test_images/` is now ignored by Git.

## Not changed

- PaddleOCR remains PP-OCRv5 mobile det/rec on ONNX Runtime; no Paddle-Lite,
  OpenCV, cloud OCR or new model.
- MangaOCR remains the compact Rikai bubble/crop pipeline; no mask/panel/free-
  text regrouping, cross-bubble encoder batching, INT8 draft or dense-page
  tiling yet.
- Phase 5 corpus/history/onboarding/release work is not part of this phase.
- No new dependencies were added; the existing `image` package performs the
  manual 90° rotation.

## Verification (2026-10-29)

Host:

```text
flutter analyze  -> No issues found
flutter test     -> 120 tests passed
flutter build apk --debug -> success
```

Device OCR suite (`integration_test/ocr_android_test.dart`, x86_64 API 36,
real PaddleOCR + MangaOCR + orientation models, 8/8 passed):

```text
PaddleOCR horizontal      299ms   1 block   "ありがとう"
Tilted-page deskew        201ms   1 block   "ありがとう"
horizontal lazy sessions  passed  mangaLoaded=false after horizontal
MangaOCR auto (cold)     1175ms   1 block   "これはテストです"
MangaOCR vertical (warm)  146ms   1 block   "これはテストです"
Sideways 90° correction   757ms   8 blocks  "ありがとう" x8
Sideways 270° correction  906ms   8 blocks  "ありがとう" x8
Upside-down 180°          246ms   1 block   "ありがとう"
Cancellation              passed
```

MDict compatibility suite (x86_64, real files):
`integration_test/mdict_compat_android_test.dart` 2/2 passed:

```text
kanjigen Encrypted=2 entries=84396 image=_image/Kanji/Rittou.jpg bytes=439
meikyo entries=403495 image=gaiji/参照.svg bytes=444
```

Real-image regression (`integration_test/ocr_real_images_android_test.dart`)
ran all seven supplied `test_images` through auto/horizontal/vertical. Auto
returns exactly one engine; low-confidence MangaOCR pages (for example the
dense book page) fall back to PaddleOCR and now produce the readable Paddle
text. `manga.jpg` stays on MangaOCR; horizontal screenshots stay on PaddleOCR.

`test/capture_storage_test.dart` also verifies the manual “旋转” path rotates
the session copy clockwise (red-left/blue-right becomes red-top/blue-bottom),
overwrites only the private copy, and rejects paths outside the session
directory.

The lazy-session test asserts that horizontal recognition and
`prepare(horizontal)` keep `mangaLoaded=false`, while `prepare(auto)` loads it.

## Acceptance status

| Item | x86_64 emulator | arm64 device |
|---|---|---|
| Horizontal-only does not load MangaOCR | pass | pending |
| Cached page re-entry does not re-run OCR | existing Phase 3.5 behavior | pending |
| 90/270 sideways page correction | pass (synthetic page) | pending |
| Auto returns one engine / low-confidence fallback | pass (synthetic + 7 real images) | pending |
| Mild deskew | pass (synthetic 6°) | real photos needed |
| Vertical multi-bubble order/noise | synthetic + `manga.jpg` pass | real manga needed |
| PaddleOCR 2048px < 5s | not representative | pending |
| MangaOCR page < 10s, no OOM | not representative | pending |

The development environment only has an x86_64 emulator. The user has tested on
an arm64 device and reported the issues addressed above; those fixes still need
an arm64 retest. Phase 5 must not start until the arm64 rows and real manga-page
quality are checked.

## Remaining risks / next improvements

- First auto/vertical recognition on a fresh process still pays the MangaOCR
  session creation cost when no background prewarm has finished. Cold auto was
  ~1.1s on the emulator; warm vertical was ~180ms.
- Dense book pages that DBNet labels vertical pay for a MangaOCR attempt before
  the low-confidence fallback to Paddle. The real `book_tategaki` image took
  ~6.7s auto but returned the readable Paddle text.
- MangaOCR still lacks full mask/panel/free-text regrouping and cross-bubble
  batching. INT8 speculative decoding remains a later optimization, not the
  current bottleneck.
- Stat-first readiness does not detect a same-size/same-mtime corrupted file;
  the native loader catches invalid ONNX/keys data on first use.
- Real manga pages, furigana noise, dense panels and arm64 performance still
  need a device regression set before Phase 5.
