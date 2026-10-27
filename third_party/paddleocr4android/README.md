# PaddleOCR4Android — evaluation and optional backend

Upstream: PaddleOCR4Android, Copyright 2026 jangviktor-web, MIT License.
Source: https://github.com/jangviktor-web/PaddleOCR4Android

The upstream `:PaddleOCR4Android` module is a plain Android library:

- Paddle Lite C++/JNI with OpenCV 4.2.0 statically linked
- Prebuilt `libpaddle_light_api_shared.so` etc.; arm64-v8a / armeabi-v7a only
- Builds with NDK r21e (Paddle Lite symbols conflict with newer NDKs)
- PP-OCRv5 mobile `det.nb` / `cls.nb` / `rec.nb` + `ppocr_keys_ocrv5.txt`
- Horizontal text only; label file is read from Android assets

Rikai-Mobile's MVP uses the same PP-OCRv5 model family through ONNX Runtime
(shared with manga-ocr) instead of Paddle Lite. This avoids a second inference
runtime, the OpenCV static library, the NDK r21 build chain, and the missing
x86_64 ABI. `OcrBackend` remains an extension point; this module can be built
as an AAR and plugged in later without changing the Flutter-facing API.

Nothing from this repository is compiled into the MVP. The MIT license is
retained in `LICENSE`.
