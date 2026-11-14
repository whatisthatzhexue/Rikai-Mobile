# Third-party notices

Rikai-Mobile is built on the following open-source projects and models. This
file is a summary; the authoritative license texts are in `assets/licenses/`
and `third_party/*/LICENSE` (repository files, not bundled into the app; the
in-app license page shows a summary).

## Adapted code

| Component | License | Copyright | Location |
|---|---|---|---|
| overlay-translator (Screen Translator) | Apache-2.0 | 2026 ciddwd | `third_party/overlay-translator/` |
| PaddleOCR4Android | MIT | 2026 jangviktor-web | `third_party/paddleocr4android/` |
| mecab_for_dart | BSD-3-Clause | 2024 CaptainDario | `packages/mecab_for_dart/` |
| MeCab 0.996 | GPL/LGPL/BSD (BSD used) | Taku Kudo, NTT | `packages/mecab_for_dart/src/` |

## Runtime

| Component | License | Notes |
|---|---|---|
| ONNX Runtime | MIT | `ai.onnxruntime:onnxruntime-android:1.28.0`; see `assets/licenses/ONNX-Runtime-ThirdPartyNotices.txt` |
| PaddleOCR PP-OCRv5 models | Apache-2.0 | Downloaded at runtime, not in git |
| PP-LCNet orientation models | Apache-2.0 | Downloaded at runtime, not in git |
| manga-ocr ONNX (l0wgear) | Not declared | Downloaded at runtime, not redistributed; local import supported |
| dict_reader | MIT | Pure-Dart MDict parser |
| Kiyosuna Sans (KT Kiyosuna Sans) | SIL OFL 1.1 | Bundled Light/Bold fonts; Copyright (c) 2024 WATANABE Reiya; see `app/assets/fonts/KiyosunaSans/README.md` |
| Flutter packages | Various | Listed by Flutter's license page |

## User-supplied, not distributed

- **UniDic** — GPL v2 / LGPL v2.1 / modified BSD; Copyright NINJAL.
- **MDict dictionaries** — original content licenses apply.

## Modifications

See `third_party/overlay-translator/MODIFICATIONS.md`,
`third_party/paddleocr4android/README.md`, and
`packages/mecab_for_dart/MODIFICATIONS.md`.
