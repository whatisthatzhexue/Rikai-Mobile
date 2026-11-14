import 'dart:convert';

import 'package:rikai_ocr/rikai_ocr.dart';

import '../../core/models/capture_photo.dart';
import '../../services/storage/history_store.dart';

/// Serializes OCR blocks exactly as the corpus detail/history consumer expects.
String encodePhotoBlocks(PhotoOcrResult? result) {
  final blocks = result?.blocks ?? const <OcrBlock>[];
  return jsonEncode(
    blocks.map((block) {
      return {
        'text': block.text,
        'left': block.left,
        'top': block.top,
        'right': block.right,
        'bottom': block.bottom,
        'confidence': block.confidence,
        'orientation': block.orientation,
        'points': block.points,
      };
    }).toList(),
  );
}

/// Writes one photo session into the corpus using that photo's own OCR mode.
Future<void> saveCapturePhotoToCorpus({
  required HistoryStore history,
  required CapturePhoto photo,
  required PhotoOcrResult? result,
}) {
  return history.savePhoto(
    sourceImagePath: photo.filePath,
    text: result?.text ?? '',
    engine: result?.engine ?? 'paddle_v5',
    mode: photo.mode.name,
    orientation: result?.blocks.isNotEmpty == true
        ? result!.blocks.first.orientation
        : 'unknown',
    blocksJson: encodePhotoBlocks(result),
  );
}
