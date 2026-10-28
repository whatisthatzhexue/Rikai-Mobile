# OCR models

Models are **not** committed. `assets/models/manifest.json` is the source of
truth for URLs, sizes, licenses, and mirror order. The app downloads to
`getExternalFilesDir()/models/` and supports local import.

Phase 3 uses only `paddle_v5` (det + rec + keys). MangaOCR and orientation
models are listed for Phase 4; they are not routed to the native pipeline yet.
The native plugin receives local paths from the Dart `OcrModelManager` and
never downloads anything itself.

| Set | Files | Approx. size | License | Source |
|---|---|---:|---|---|
| `paddle_v5` | `det.onnx`, `rec.onnx`, `keys.yml` | 22 MB | Apache-2.0 | PaddlePaddle/PP-OCRv5_mobile_*_onnx (pinned revisions) |
| `manga_ocr` | `encoder_model.onnx`, `decoder_model.onnx`, `vocab.txt`, 4 JSON files | 140 MB | **Not declared** | `l0wgear/manga-ocr-2025-onnx` |
| `orientation` | `doc_ori.onnx`, `textline_ori.onnx` | 7.5 MB | Apache-2.0 | PaddlePaddle/PP-LCNet_*_onnx |

## Mirror behavior

- Default order: `https://hf-mirror.com`, then `https://huggingface.co`.
- A custom mirror prefix can be set in settings.
- Download is resumable (HTTP Range), writes a `.part` file, verifies size and
  optional SHA-256, then renames atomically.
- If all sources fail, the user can pick local files in the model manager.

## Verified PaddleOCR build (2026-10-28)

The checked-in manifest pins `PP-OCRv5_mobile_det_onnx` revision
`e6f4fa85...` and `PP-OCRv5_mobile_rec_onnx` revision `ed152b8b...`.
`keys.yml` has 18,383 characters; the recognizer emits 18,385 classes
(blank + 18,383 keys + space). The first key is U+3000 and must not be trimmed.
Host ORT smoke: det `(1,1,64,480)`, rec `(1,40,18385)`, synthetic
`ありがとう` decoded at score 0.9983. Android plugin test: 266 ms, 1 block,
confidence 1.000. See `docs/phase3-status.md`.

## MangaOCR license

The upstream `kha-white/manga-ocr-base` project is Apache-2.0, but the
`l0wgear/manga-ocr-2025-onnx` model card does not declare a license. Rikai-Mobile
does not redistribute it. The download screen shows this warning and asks for
confirmation. Users may import an ONNX export they produced themselves from the
Apache-2.0 model.

## Not used

- `detector-v4-s_int8.onnx` (comic bubble detector): only needed for overlay
  bubble rendering, not OCR.
- ML Kit, cloud OCR, Paddle Lite `.nb` models.
