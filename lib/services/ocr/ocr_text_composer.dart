import 'package:rikai_ocr/rikai_ocr.dart';

/// Turns native line blocks into reader text.
///
/// The native detector emits one block per text line in reading order. We keep
/// line breaks so MeCab can preserve them, normalise accidental whitespace, and
/// drop empty/consecutive duplicate lines produced by overlapping detector boxes.
String composeOcrText(List<OcrBlock> blocks) {
  final lines = <String>[];
  for (final block in blocks) {
    final line = block.text
        .replaceAll(RegExp(r'[\t\r\n]+'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
    if (line.isEmpty) continue;
    if (lines.isNotEmpty && lines.last == line) continue;
    lines.add(line);
  }
  return lines.join('\n').trim();
}
