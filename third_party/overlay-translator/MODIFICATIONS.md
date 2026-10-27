# Modifications to overlay-translator

Upstream: Screen Translator (屏译), Copyright 2026 ciddwd, Apache-2.0.
Source: https://github.com/ciddwd/overlay-translator

Rikai-Mobile extracts the headless OCR core only. The following upstream
layers are **not** included:

- Hilt/Compose UI, DataStore settings, overlay/floating-window rendering
- screen capture, MediaProjection, Accessibility, Shizuku, Root
- translation (LLM/cloud/ML Kit), ASR, TTS, glossary, dictionary packs
- bubble rendering, text erase/mask repair, capture loop and page stability
- cloud OCR engines (Baidu/Tencent/Youdao/Umi/Luna) and ML Kit OCR

Adapted OCR code (to be placed in `packages/rikai_ocr/android/...`):

- PP-OCRv5 DBNet detection, CTC recognition, crop/warp and DB post-processing
- manga-ocr ViT encoder + greedy decoder, bubble clustering, crop planning,
  tiling, fragment/consolidation policies
- orientation heuristics and PP-LCNet document/text-line orientation
- reading-order sorting (horizontal LTR, vertical RTL, manga bands)
- ONNX Runtime session/thread/buffer helpers

Changes required for extraction:

- Remove Hilt annotations and dependency injection; construct classes with an
  Android `Context` and a small `OcrConfig`.
- Replace `Settings`/`SettingsRepository` with immutable OCR settings.
- Replace `BuildConfig`, `R`, `LogRepository`, and Timber dependencies with
  local constants/logging where necessary.
- Split `PaddleOcrEngine` into detector and recognizer so the vertical pipeline
  can reuse detection without loading the recognizer.
- Replace upstream model installers with the Dart-side `ModelManager`.
- Own one application-scoped `OrtEnvironment`; do not close it per engine
  (upstream's `PaddleOcrEngine.close()` currently closes the shared environment).
- Remove experimental speculative decoding from the MVP (keep the FP32 decoder;
  the INT8 draft decoder can return later).

Upstream `LICENSE` and `NOTICE` are retained in this directory. Every copied
source file keeps its Apache-2.0 header and gets a short "Modified for
Rikai-Mobile" note.
