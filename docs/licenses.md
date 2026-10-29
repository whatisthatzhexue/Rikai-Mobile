# License notes

The authoritative attribution summary is [../THIRD_PARTY_NOTICES.md]. License
texts used by the in-app license page are under `assets/licenses/`.

- overlay-translator (OCR core): Apache-2.0, Copyright 2026 ciddwd
  (`third_party/overlay-translator/LICENSE`, `NOTICE`, `MODIFICATIONS.md`).
- PaddleOCR4Android: MIT, Copyright 2026 jangviktor-web
  (`third_party/paddleocr4android/LICENSE`); evaluated, not compiled in MVP.
- MeCab 0.996: BSD option of its GPL/LGPL/BSD tri-license; mecab_for_dart:
  BSD-3, Copyright 2024 CaptainDario (`packages/mecab_for_dart/`).
- ONNX Runtime: MIT; third-party notices in
  `assets/licenses/ONNX-Runtime-ThirdPartyNotices.txt`.
- PaddleOCR PP-OCRv5 / PP-LCNet models: Apache-2.0 (downloaded at runtime).
- manga-ocr ONNX (l0wgear): license not declared; downloaded at runtime, not
  redistributed; local import supported.
- dict_reader: MIT, Copyright 2024 Mumulhl.
- UniDic: GPL v2 / LGPL v2.1 / modified BSD; user-supplied, not distributed.
- MDict dictionaries: user-supplied; original content licenses apply.

## Phase 6 remote LLM providers (planned)

Phase 6 is not implemented. When it is added, the dictionary assistant will use a
user-supplied API key and a user-selected provider (for example DeepSeek or
Claude). Provider terms of service and privacy policies apply to requests; this
project does not redistribute LLM weights, API keys, prompts, or conversations.
Images will remain on-device and be converted by local OCR; only locally
extracted text, tokenization results, and dictionary tool results would be sent
when the user explicitly initiates a request. API keys must not be committed,
logged, or exported. If an SDK or other provider dependency is added later,
update this file, `THIRD_PARTY_NOTICES.md`, `NOTICE`, and `assets/licenses/`
as needed.
