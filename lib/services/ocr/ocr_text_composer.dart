import 'package:rikai_ocr/rikai_ocr.dart';

/// Turns native line blocks into reader text.
///
/// The native detector emits one block per text line in reading order. We keep
/// line breaks so MeCab can preserve them and remove spaces that OCR inserted
/// inside Japanese runs. Japanese does not use word spacing, and those
/// artefacts make UniDic split compounds into single characters.
String composeOcrText(List<OcrBlock> blocks) {
  final lines = <String>[];
  for (final block in blocks) {
    final line = _normalizeLine(block.text);
    if (line.isEmpty) continue;
    lines.add(line);
  }
  return lines.join('\n').trim();
}

const String _japanese = r'[぀-ヿ㐀-䶿一-鿿豈-﫿々〆ヶ]';
const String _japanesePunctuation = r'[、。，．！？「」『』（）［］｛｝〈〉《》【】〔〕・…‥ー〜～：；]';
const String _invisible = r'[​-‍﻿]';

final RegExp _lineBreaks = RegExp(r'[\t\r\n]+');
final RegExp _repeatedSpaces = RegExp(r' {2,}');
final RegExp _invisibleCharacters = RegExp(_invisible);
final RegExp _spaceBetweenJapanese = RegExp('($_japanese) +(?=$_japanese)');
final RegExp _spaceBeforeJapanesePunctuation = RegExp(
  ' +($_japanesePunctuation)',
);
final RegExp _spaceAfterJapanesePunctuation = RegExp(
  '($_japanesePunctuation) +',
);

String _normalizeLine(String raw) {
  var line = raw
      .replaceAll(_invisibleCharacters, '')
      .replaceAll(_lineBreaks, ' ')
      .replaceAll('　', ' ')
      .replaceAll(_repeatedSpaces, ' ');
  line = line.replaceAllMapped(
    _spaceBetweenJapanese,
    (match) => match.group(1) ?? '',
  );
  line = line.replaceAllMapped(
    _spaceBeforeJapanesePunctuation,
    (match) => match.group(1) ?? '',
  );
  // Collapse spaces after Japanese punctuation only; Latin text keeps its
  // normal word spacing.
  line = line.replaceAllMapped(
    _spaceAfterJapanesePunctuation,
    (match) => match.group(1) ?? '',
  );
  return line.trim();
}
