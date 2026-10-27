# ADR 0001: Unified ONNX Runtime OCR

- Status: accepted
- Date: 2026-10-26

## Context

Two upstream OCR implementations were available:

- overlay-translator: PaddleOCR PP-OCRv5 and manga-ocr, both through ONNX
  Runtime, with DBNet shared between horizontal and vertical paths.
- PaddleOCR4Android: Paddle Lite + OpenCV C++/JNI, NDK r21, arm-only, horizontal.

## Decision

Use one ONNX Runtime pipeline for MVP:

- PaddleOCR PP-OCRv5 det/rec for horizontal text.
- manga-ocr encoder/decoder for vertical text, sharing the same DBNet detector.
- PP-LCNet orientation models for rotated pages.

PaddleOCR4Android is kept as a documented optional `OcrBackend`; it is not
compiled in MVP.

## Consequences

- One native inference runtime; no OpenCV/Paddle Lite/NDK r21 build chain.
- Horizontal and vertical engines share detection and reading-order logic.
- PaddleOCR4Android's MIT license and notice are retained; its Paddle-Lite
  backend can be added later behind the same interface.
- MangaOCR weights are download-only and not redistributed.
