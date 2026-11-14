import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/ocr_model.dart';
import 'package:rikai_mobile/core/models/ocr_model_copy.dart';

void main() {
  test('manifest has no display copy and every set has trilingual copy', () {
    final raw = File('assets/models/manifest.json').readAsStringSync();
    expect(raw.contains('"displayName"'), isFalse);
    expect(raw.contains('"licenseNote"'), isFalse);

    final manifest = OcrModelManifest.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    expect(
      OcrModelCopy.knownSetIds.toSet(),
      manifest.sets.keys.toSet(),
      reason: 'copy ids must match manifest set ids',
    );
    for (final setId in manifest.sets.keys) {
      for (final language in OcrModelCopyLanguage.values) {
        expect(
          OcrModelCopy.displayName(setId, language: language),
          isNotEmpty,
          reason: '$setId $language',
        );
      }
    }
    expect(
      manifest.sets['manga_ocr']!.licenseNote,
      OcrModelCopy.licenseNote('manga_ocr'),
    );
    expect(OcrModelCopy.licenseLabel('UNKNOWN'), '许可未声明');
  });
}
