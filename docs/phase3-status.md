# Phase 3 status

Date: 2026-10-28
Project root: `C:\Projects\Rikai-Mobile`
Device: `Medium_Phone_API_36.1` (x86_64 emulator, API 36). No arm64 device.

## Completed

### Native PaddleOCR pipeline (`packages/rikai_ocr`)

- `RikaiOcrPlugin.kt` — `rikai/ocr` MethodChannel and `rikai/ocr_progress`
  EventChannel. Commands: `initialize`, `recognize`, `cancel`, `dispose`.
  Recognitions are serialized; cancellation is checked between detector
  crops/lines; results are delivered on the main thread.
- `PaddleOcrEngine.kt` — PP-OCRv5 mobile ONNX detector + CTC recognizer:
  - BitmapFactory sampled decode, EXIF orientation correction, longest side
    2048, and a 960-px / 32-aligned DBNet input.
  - DBNet probability map → pure-Kotlin `DBPostprocessor` quads (no OpenCV).
  - `PaddleRotateCrop` perspective/bicubic crop, 48-px recognition height,
    dynamic width up to 3200, BGR normalization, CTC greedy decode.
  - Line ordering and a 0.15 confidence floor. Output blocks carry text, rect,
    four points, confidence and orientation.
- `CtcDictionary.kt` — parses the PP-OCRv5 `inference.yml` character dict
  (18,383 characters; first key is U+3000, preserved).
- `OcrRuntime` owns one application-scoped `OrtEnvironment`; engines close only
  their own sessions. `consumer-rules.pro` keeps `ai.onnxruntime.**`.
- Actual OCR is horizontal. Requesting `vertical` returns `UNSUPPORTED_MODE`;
  the UI says vertical is a later phase.

### Model management (Dart)

- `lib/core/models/ocr_model.dart` — manifest/model-set/file models.
- `lib/services/ocr/model_manager.dart`:
  - `getExternalFilesDir()/models/{set}` storage; no model is bundled.
  - manifest URLs in order (hf-mirror, then Hugging Face), optional custom
    mirror prefix, `.part` resume via HTTP Range, size/SHA-256 validation,
    atomic rename.
  - local import of selected files, delete, status, and Paddle path resolution.
  - development override `--dart-define=RIKAI_OCR_MODELS_DIR=...` (empty in
    normal builds).
- `assets/models/manifest.json` remains the source of truth; `paddle_v5` is
  about 20.5 MiB. Model binaries are ignored by git.

### UI

- Home `拍照识别` opens `/capture`.
- Capture page: camera/gallery via `image_picker`, preview, auto/horizontal
  direction selection, model status/download/management, progress and cancel.
- OCR text is passed to the reader through `ReaderRouteArgs`; the reader
  replaces its draft with the OCR text, then the existing MeCab/MDict flow is
  used.
- `OCR 模型` settings page lists PaddleOCR, MangaOCR (Phase 4) and optional
  orientation models with download/import/delete/cancel. MangaOCR is shown as
  license-undeclared and is not downloadable in Phase 3.
- Model download errors are shown with a short user-facing message; missing
  models do not block text input or dictionary lookup.

## Verification

Host ORT smoke (Python, downloaded models under `build/ocr-models/`):

```text
det output (1,1,64,480), min=0.0 max=1.0 mean=0.118
rec output (1,40,18385), decoded "ありがとう", score=0.9983
```

Device integration test (`integration_test/ocr_android_test.dart`, 2 tests):

```text
OCR readiness={engine: paddle_v5, detInput: x, recInput: x, keys: 18383, threads: 4}
PaddleOCR engine=paddle_v5 elapsed=320ms blocks=1 text="ありがとう"
block conf=1.000 rect=(25.0,78.0,351.0,164.0) "ありがとう"
```

The second device test cancels during detection and asserts the native channel
returns `CANCELLED` without crashing.

Full app flow with the real UniDic:
`拍照识别 → 从相册选择 → 开始识别 → 文本阅读 → 分词 → 点击词条`.
The test image produced `ありがとう\n東京で食べた。`; the reader rendered
`ありがとう`, `東京（とうきょう）`, `食べ（たべ）`, `た`, `で`, `。`, and the
token lookup sheet opened with the reading duplicate suppressed.

Automated checks:

```text
flutter analyze  -> No issues found
flutter test     -> 97 tests passed
flutter build apk --debug -> success
```

Unit coverage added for the manifest, OCR text composition, and model download
including a real HTTP Range resume via a local `HttpServer`.

## Known limitations

- No arm64 device; timings are x86_64 functional smoke results.
- The emulator used for the device run cannot resolve `hf-mirror.com` or
  `huggingface.co`, so the live model download was not verified on-device.
  Host `curl` download succeeded; the local HTTP server tests verify resume,
  size, SHA-256 and atomic install. A network-capable device still needs a
  real download test.
- Model files staged with `adb push` must be placed in an app-owned directory;
  shell-created directories under `Android/data` are not readable by the app.
  Create the directory by launching the app/model manager first, or use the
  in-app download/import.
- OCR is horizontal. Vertical MangaOCR, automatic orientation routing and
  document/text-line orientation models are Phase 4.
- OCR result coordinates are in the EXIF-corrected, max-2048 image; no overlay
  editor yet.
- Camera capture was not automated in an integration test; gallery selection
  and the native OCR pipeline were exercised on the emulator.
- Model download UI was exercised with staged files; live retry/mirror fallback
  remains a network-device test.

## Next

Phase 4: MangaOCR encoder/decoder, vertical RTL reading order, bubble/crop
planning, automatic horizontal/vertical routing, and the orientation models.
