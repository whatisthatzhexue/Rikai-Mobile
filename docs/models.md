# OCR models

Models are **not** committed. `assets/models/manifest.json` is the source of
truth for URLs, sizes, SHA-256 hashes, licenses, and mirror order. The app
downloads to `getExternalFilesDir()/models/` by default; the model page can
switch to a user-selected directory (migrating existing models by default).

Phase 3 uses `paddle_v5` (det + rec + keys). Phase 4 adds the optional
`manga_ocr` vertical recognizer and the optional `orientation` doc/text-line
models; all local paths are resolved by the Dart `OcrModelManager`. A missing
optional set keeps horizontal OCR working. The native plugin never downloads
anything itself.

Phase 4.5 keeps optional ONNX sessions lazy: `initialize` loads PaddleOCR only,
and the MangaOCR/orientation sessions are created when auto/vertical mode needs
them (or by an explicit background `prepare`). Horizontal-only use therefore
does not pay the 140 MB MangaOCR session cost. Runtime readiness and the model
page's installed-status check use file existence and pinned size; downloads,
imports and migrations still verify SHA-256, cached per path/size/mtime. The
native ONNX loader is the final content check for existing files.

| Set | Files | Approx. size | License | Source |
|---|---|---:|---|---|
| `paddle_v5` | `det.onnx`, `rec.onnx`, `keys.yml` | 22 MB | Apache-2.0 | PaddlePaddle/PP-OCRv5_mobile_*_onnx (pinned revisions) |
| `manga_ocr` | `encoder_model.onnx`, `decoder_model.onnx`, `vocab.txt`, 4 JSON files | 140 MB | **Not declared** | `l0wgear/manga-ocr-2025-onnx` |
| `orientation` | `doc_ori.onnx`, `textline_ori.onnx` | 7.5 MB | Apache-2.0 | PaddlePaddle/PP-LCNet_*_onnx |

## Mirror behavior

- Default order: `https://hf-mirror.com`, then `https://huggingface.co`.
- A custom mirror prefix can be set in settings.
- Download is resumable (HTTP Range), writes a `.part` file, verifies size and
  the pinned SHA-256, then renames atomically. A 416 or mismatched
  `Content-Range` resets the partial file.
- If all sources fail, the user can import local files. Upstream
  `inference.onnx`/`inference.yml` names are matched to det/rec/keys by role,
  pinned size and extension; already valid files are reused.

## Verified PaddleOCR build (2026-10-28)

The checked-in manifest pins `PP-OCRv5_mobile_det_onnx` revision
`e6f4fa85...` and `PP-OCRv5_mobile_rec_onnx` revision `ed152b8b...`.
`keys.yml` has 18,383 characters; the recognizer emits 18,385 classes
(blank + 18,383 keys + space). The first key is U+3000 and must not be trimmed.
Host ORT smoke: det `(1,1,64,480)`, rec `(1,40,18385)`, synthetic
`ありがとう` decoded at score 0.9983. Android plugin test: 320 ms, 1 block,
confidence 1.000. See `docs/phase3-status.md`.

## MangaOCR license

All seven MangaOCR file hashes are pinned in the manifest (2026-10-29). Phase 4
routes the encoder/decoder/vocab into the native vertical pipeline. The model
card still has no declared license; hashes do not change the redistribution
policy.

The upstream `kha-white/manga-ocr-base` project is Apache-2.0, but the
`l0wgear/manga-ocr-2025-onnx` model card does not declare a license. Rikai-Mobile
does not redistribute it. The download screen shows this warning and asks for
confirmation. Users may import an ONNX export they produced themselves from the
Apache-2.0 model.

## Phase 6 remote LLM configuration (planned)

Phase 6 is not implemented. Unlike OCR models, the planned dictionary assistant
does not add local LLM weights to `assets/models/manifest.json` or the model
directory. LLM inference is hosted by a user-selected provider.

Planned configuration:

- provider (DeepSeek, Claude, or an OpenAI-compatible endpoint);
- base URL where applicable;
- API key (secure storage only, never in this repository or logs);
- `smallModel` for simple lookup/formatting tasks;
- `complexModel` for reasoning and rule generation.

The existing OCR model manager remains unchanged. The Agent must never use a
provider's image/vision endpoint, and its model configuration must not be
required for the offline OCR/UniDic/MDict core. See
`docs/phase6-agent-design.md` for privacy and acceptance details.

## Not used

- `detector-v4-s_int8.onnx` (comic bubble detector): only needed for overlay
  bubble rendering, not OCR.
- ML Kit, cloud OCR, Paddle Lite `.nb` models.
