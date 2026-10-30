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

### Second device-feedback pass (2026-10-29)

- **MDD audio**: `sound://` links were previously deleted by the HTML
  sanitiser, so dictionaries with pronunciation files were silent. The
  renderer now resolves the MDD resource and inserts a native `<audio
  controls>` player with a local `file://` source. `sound://` keys are also
  normalised by `mddKeyCandidates`. The real
  `日本語文型辞典 三语音频版` entry `あくまで` was verified on the host and
  on the x86_64 emulator: `sound://00048.aac` resolved to a 25,463-byte MDD
  resource and became a local audio element. Actual speaker output still needs
  a real-device check.
- **Home layout**: the page is now a single Column-style scroll list:
  “使用前须知” → four action buttons → “边界说明”. The previous vertical
  centring of the buttons was removed.
- **Model delete**: the delete button now explicitly paints both its icon and
  label in the error colour inside the red outline.
- **Dictionary import**: the “正在读取 x/y” probing stage now uses a
  determinate progress bar based on the same success/total counts as the text.
- **Lookup filter**: dictionary selection and single/multi mode are global and
  persisted, shared by the search page and reader sheet. Chip widths no longer
  change with selection, so the order never drifts. At most three wrapped rows
  are visible; extra dictionaries scroll vertically. Result-group spacing was
  tightened.
- **Lookup session**: query text, results and the last dictionary selection
  live in app-lifetime providers, so leaving and re-entering the search page no
  longer clears them. A changed global selection refreshes the existing result.
- **Keyboard focus**: a global route-pop observer clears focus after dialogs
  and pages close; search and entry navigation also unfocus before pushing.
- **Toasts**: all transient messages use a root-overlay `RikaiToast` wrapped in
  `IgnorePointer`, so a “已保存到语料库” bubble no longer blocks controls
  underneath it.
- **Vertical OCR strategy**: a vertical page now runs both MangaOCR and
  PaddleOCR and compares them with an engine-independent quality score
  (confidence, Japanese/kana coverage, repetition). PaddleOCR replaces
  MangaOCR only with a clear quality margin. If the best primary score is below
  0.80, PaddleOCR is also tried on the page rotated ±90°; the final result still
  uses exactly one engine. A forced-rotation experiment over all seven
  `test_images` showed that the supplied vertical book pages already scored
  better unrotated (book page: 0.966 unrotated vs 0.937 rotated; Twitter photo:
  0.893 vs 0.807), so rotation remains a low-quality fallback rather than an
  unconditional second pass.
- **OCR text cleanup**: spaces inserted inside Japanese runs and around
  Japanese punctuation are removed before UniDic sees the text, while Latin
  word spacing is preserved.
- **Long token lists**: reader, photo-set and corpus-detail token views build
  lazily; corpus detail no longer spreads every token into one list. The
  automatic scrollbar was suppressed on these variable-height token lists to
  remove its stuttering thumb.
- **Photo rotation**: the rotate action now interrupts a running OCR
  immediately, rotates the private copy and starts the next recognition pass
  without requiring the user to cancel first.
- **Delete confirmation**: the single-photo and multi-select delete dialogs
  both show the “同时删除原文件” checkbox (disabled when the photo has no
  separate original).
- **Corpus dates**: preview cards show `2026.09.12`, or `09.12` for the
  current year.

### Landscape/layout pass (2026-10-30)

- **Dictionary import**: the recursive-scan explanation is now shown only while
  the result list is empty; the “扫描完成” status is cleared when probing ends.
  The freed height goes to the dictionary rows.
- **Manual MDict dialog**: the path field no longer autofocuses; the dialog
  clears focus on entry and after the folder picker, so the keyboard does not
  cover the dialog.
- **Entry limit dialog**: the five choices live in a height-constrained
  `SingleChildScrollView`, so “10 条” remains reachable on short portrait and
  landscape screens.
- **Photo preview collapse**: the resize handle can now reach `0`; at or below
  the 40dp handle the image and its overlays disappear and the result list gets
  the space. Both the photo set and corpus detail use the same `PhotoPane`
  behaviour, and the handle remains available to pull the photo back down.
- **Lookup filter layout**: the “查询词典” heading was removed and chips start
  at its previous height. The single/multi toggle moved into the AppBar on the
  search page and into the top title row of the reader lookup sheet, vertically
  centred with the headword.
- **Reader controls**: after tokenisation, a grey “隐藏输入框” action appears
  to the left of “分词”. Hiding removes the whole input/toolbar block; a
  visibility icon appears below the AppBar at the same left inset and restores
  it. Hidden height is given to the token result list.
- Landscape widget tests cover search controls, reader layout, the manual
  dictionary dialog (no keyboard), and the scrollable entry-limit dialog.

## Not changed

- PaddleOCR remains PP-OCRv5 mobile det/rec on ONNX Runtime; no Paddle-Lite,
  OpenCV, cloud OCR or new model.
- MangaOCR remains the compact Rikai bubble/crop pipeline; no mask/panel/free-
  text regrouping, cross-bubble encoder batching, INT8 draft or dense-page
  tiling yet.
- Phase 5 corpus/history/onboarding/release work is not part of this phase.
- No new dependencies were added; the existing `image` package performs the
  manual 90° rotation.

## Verification (2026-10-30)

Host:

```text
flutter analyze  -> No issues found
flutter test     -> 134 tests passed
flutter build apk --debug -> success (Kotlin/OcrTextQuality compiled)
```

Device OCR suite (`integration_test/ocr_android_test.dart`, x86_64 API 36,
real PaddleOCR + MangaOCR + orientation models, 8/8 passed):

```text
PaddleOCR horizontal      195ms   1 block   "ありがとう"
Tilted-page deskew        169ms   1 block   "ありがとう"
horizontal lazy sessions  passed  mangaLoaded=false after horizontal
MangaOCR auto (cold)     1003ms   1 block   "これはテストです"
MangaOCR vertical (warm)  312ms   1 block   "これはテストです"
Sideways 90° correction   832ms   8 blocks  "ありがとう" x8
Sideways 270° correction  648ms   8 blocks  "ありがとう" x8
Upside-down 180°          135ms   1 block   "ありがとう"
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
The vertical best-of path was re-run on a cold-booted x86_64 emulator after the
second feedback pass. Auto selected exactly one engine per page; `manga.jpg`
stayed on MangaOCR while the book/screenshot pages selected PaddleOCR. Final
auto timings were 0.5–6.1 s, with `book_tategaki.jpg` at 6.1 s (the dense book
page includes both engines). Manual vertical was 2.3–5.6 s on the same set.
The ±90° retry only ran for primary scores below 0.80 and did not win on the
supplied vertical pages; it remains available for weaker inputs. Arm64 is
still the acceptance target.

Real MDD audio rendering was verified against
`mdicts/日本語文型辞典 三语版 音频版` on the host and on the x86_64 emulator:
entry `あくまで` contained `sound://00048.aac`, the 25,463-byte resource was
read from the MDD, and `EntryRenderer` produced an `<audio>` element with a
local `file://` URL. `integration_test/mdict_audio_android_test.dart` passed
1/1 on the emulator. The dictionary unit test also covers the transformation.
Speaker output itself is a device-only check.

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
| Vertical best-of / ±90° Paddle retry | pass on 7 real images (x86_64 cold boot) | pending |
| MDD `sound://` audio player | pass (host + x86_64 emulator); speaker pending | pending |
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
  ~1.0s on the emulator; warm vertical was ~0.3s. A vertical page now also
  runs the PaddleOCR candidate for best-of selection, so its cost is higher
  than the pure-Manga path.
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
