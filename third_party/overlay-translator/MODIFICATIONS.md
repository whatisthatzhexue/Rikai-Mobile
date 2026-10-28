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

Adapted OCR code in `packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/`:

| File | Upstream basis | Rikai modification |
|---|---|---|
| `DBPostprocessor.kt` | `ocr/DBPostprocessor.kt` | Package rename; removed mask/frame support, optional support quads and the column-split path. Keeps connected components, hull, min-area rect, score check and unclip. |
| `PaddleRotateCrop.kt` | `ocr/PaddleRotateCrop.kt` | Package rename and reduced visibility; same OpenCV-compatible perspective/bicubic sampling. |
| `PaddleOcrEngine.kt` | `ocr/PaddleOcrEngine.kt`, `PaddleDetectionSizing.kt` | New trimmed Phase 3 pipeline; no Hilt/Settings/Timber; sampled decode and EXIF handling; session ownership; 960-px detector; batch size one; no bubble/mask/overlay logic. |
| `CtcDictionary.kt` | Paddle dictionary/CTC helpers in `PaddleOcrEngine.kt` | Extracted YAML `character_dict` parser and greedy CTC decoder; preserves U+3000 as the first key. |
| `PaddleDetectionSizing.kt` | `ocr/PaddleDetectionSizing.kt` | Reduced to the fixed 960-px mobile input plan. |

Not yet copied (planned for Phase 4): manga-ocr encoder/decoder, bubble
clustering, crop planning, tiling, fragment consolidation, orientation models,
and vertical RTL reading order.

Additional changes for extraction:

- The Flutter plugin owns one `OrtEnvironment` for the app lifetime and closes
  only its own sessions (upstream closed the shared environment per engine).
- Model installation is handled by the Dart `OcrModelManager`; native code
  receives local paths only.
- Image decode, EXIF correction and max-2048 scaling happen in the plugin.
- Vertical mode is not wired yet; it returns `UNSUPPORTED_MODE` until Phase 4.

Upstream `LICENSE` and `NOTICE` are retained in this directory. Adapted files
include an Apache-2.0 header and a "Modified for Rikai-Mobile" note.
