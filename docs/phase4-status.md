# Phase 4 status — vertical MangaOCR and automatic orientation

Date: 2026-10-29
Base: Phase 3 horizontal OCR (`docs/phase3-status.md`) and Phase 3.5
(`docs/phase3.5-status.md`)

## Scope

Phase 4 adds the vertical OCR path and makes the photo set's “自动 / 横向 / 竖向”
mode selector real:

- one DBNet detection pass feeds either PaddleOCR CTC (horizontal) or
  MangaOCR encoder/decoder (vertical);
- automatic routing uses DBNet box geometry plus the optional PP-LCNet
  document-orientation model;
- the optional PP-LCNet text-line model corrects upside-down horizontal pages
  with one 180° re-run;
- MangaOCR and orientation files are optional downloads/imports; horizontal
  OCR remains available when they are absent.

## Native implementation

### MangaOCR

`packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/MangaOcrRecognizer.kt`

- Loads `encoder_model.onnx`, `decoder_model.onnx` and `vocab.txt`; validates
  pad/CLS/SEP ids; discovers the Optimum input/output names.
- Reuses the existing DBNet quads, clusters line boxes into speech-bubble-like
  regions (18 px gap, 6 px crop padding), and splits dense regions into at most
  six text bands per 224×224 crop.
- Converts each crop with manga-ocr's grayscale/`(x-0.5)/0.5` preprocessing,
  runs the ViT encoder once, then greedy-decodes up to 48 WordPiece tokens with
  the FP32 decoder.
- Emits one block per bubble with bounds, confidence and `orientation=vertical`.
- Sorts blocks top-to-bottom by horizontal panel bands, then right-to-left by
  column and top-to-bottom inside a column.

### Routing and orientation

`PaddleOcrEngine.kt`, `TextLayoutHeuristic.kt`,
`DocOrientationRecognizer.kt`, `TextLineOrientationRecognizer.kt`

- PaddleOCR is always required; MangaOCR and orientation models are loaded
  independently and never prevent the horizontal path from initializing.
- `vertical` without MangaOCR returns `MODEL_MISSING` with a Chinese download
  hint. `auto` falls back to horizontal when MangaOCR is not installed.
- Geometry routes tall columns, strong portrait boxes and stacked square-box
  columns to MangaOCR; otherwise it keeps PaddleOCR.
- A high-confidence 90/270 document-orientation result is a conservative
  vertical hint.
- The text-line model votes on up to eight large horizontal crops. Two confident
  180° votes, or one 180° vote at ≥0.99 confidence, trigger one 180° image
  rotation and a second detection pass.
- Model loading/session reuse and cancellation are covered; the shared
  `OrtEnvironment` is still never closed by an engine.

## Dart and UI

- `OcrRuntimePaths` and `runtimePaths`/`fingerprintForPaths` add optional
  MangaOCR/orientation paths. The photo-set cache fingerprint now changes when
  optional models are installed or deleted, while a missing optional model
  still yields a valid horizontal fingerprint.
- `OcrService` passes the optional paths to the plugin and exposes
  `mangaReady`/`docOrientationReady`.
- The model page enables the MangaOCR download (previously Phase-4-gated), adds
  the unknown-license confirmation before download, and keeps local import,
  delete, directory migration and status display.
- The photo set enables the “竖向” segment. Its helper reads
  “自动模式会根据文字方向选择横向或竖向识别。” when MangaOCR is ready, or
  “竖向识别需先在「模型设置」下载 MangaOCR 模型。” when it is not.
- No new UI layout was introduced; tokens and the existing photo-set composition
  are unchanged.

## Verification

```text
flutter analyze  -> No issues found
flutter test     -> 108 tests passed
flutter build apk --debug -> success
```

Device OCR suite (`integration_test/ocr_android_test.dart`, x86_64 API 36,
real PaddleOCR + MangaOCR + orientation models, 4/4 passed):

```text
PaddleOCR engine=paddle_v5 elapsed=329ms blocks=1 text="ありがとう"
MangaOCR auto engine=manga_ocr elapsed=253ms blocks=1 text="これはテストです"
MangaOCR vertical engine=manga_ocr elapsed=251ms blocks=1 text="これはテストです"
Upside-down engine=paddle_v5 elapsed=270ms blocks=1 text="ありがとう"
```

Manual emulator checks:

- model page: PaddleOCR 20.5 MB and MangaOCR 134.0 MB shown as installed; the
  MangaOCR helper says it enables vertical/auto routing;
- photo set: auto mode recognized the vertical synthetic bubble and displayed
  `これはテストです`; manual “竖向” re-ran MangaOCR and produced the same text;
- the horizontal path remained functional with the same image set;
- the temporary photo and original were deleted after verification.

## Known limitations

- No arm64 device is available; performance, memory and real manga quality are
  functional-only on x86_64.
- The bubble clusterer/crop planner are the compact Rikai implementation, not
  the full upstream mask/panel/free-text pipeline; dense real pages may need
  tuning. INT8 draft decoding is not implemented.
- The document-orientation model is used only as a vertical hint; 90/270 image
  rotation is not applied. Text-line 180° correction requires the optional
  orientation set and is limited to horizontal line boxes.
- MangaOCR weights are user-downloaded/imported, never bundled, and their
  upstream license is undeclared.
- Full corpus/history management, onboarding and release work remain Phase 5.
