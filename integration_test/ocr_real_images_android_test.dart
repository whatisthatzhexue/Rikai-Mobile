import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rikai_mobile/services/ocr/ocr_text_composer.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

const String _imageRoot = '/sdcard/Download/rikai-test-images';
const String _modelRoot = '/sdcard/Download/rikai-models';

Future<List<File>> _waitForImages() async {
  final directory = Directory(_imageRoot);
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final images =
          directory
              .listSync()
              .whereType<File>()
              .where((file) => file.path.toLowerCase().endsWith('.jpg'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (images.length >= 7) return images;
    } catch (_) {
      // The host grants All Files Access while the session is installing.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('Test images are not readable at $_imageRoot');
}

Future<Map<String, Object?>> _initialize(RikaiOcr ocr) {
  final paddle = Directory('$_modelRoot/paddle_v5');
  final manga = Directory('$_modelRoot/manga_ocr');
  final orientation = Directory('$_modelRoot/orientation');
  String? optional(File file) => file.existsSync() ? file.path : null;
  return ocr.initialize(
    detModelPath: '${paddle.path}/det.onnx',
    recModelPath: '${paddle.path}/rec.onnx',
    keysPath: '${paddle.path}/keys.yml',
    mangaEncoderPath: optional(File('${manga.path}/encoder_model.onnx')),
    mangaDecoderPath: optional(File('${manga.path}/decoder_model.onnx')),
    mangaVocabPath: optional(File('${manga.path}/vocab.txt')),
    docOrientationPath: optional(File('${orientation.path}/doc_ori.onnx')),
    textLineOrientationPath: optional(
      File('${orientation.path}/textline_ori.onnx'),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runs the provided real-page regression images', (tester) async {
    final images = await _waitForImages();
    final ocr = RikaiOcr();
    try {
      final readiness = await _initialize(ocr);
      expect(readiness['engine'], 'paddle_v5');
      for (final image in images) {
        for (final mode in OcrMode.values) {
          try {
            final result = await ocr.recognize(
              imagePath: image.path,
              mode: mode,
            );
            final text = composeOcrText(result.blocks).replaceAll('\n', ' / ');
            final confidence = result.blocks.isEmpty
                ? 0.0
                : result.blocks
                          .map((block) => block.confidence)
                          .reduce((a, b) => a + b) /
                      result.blocks.length;
            // ignore: avoid_print
            print(
              '${image.uri.pathSegments.last} ${mode.name} '
              'engine=${result.engine} ${result.elapsedMs}ms '
              'blocks=${result.blocks.length} '
              'conf=${confidence.toStringAsFixed(3)} '
              'text="${text.length > 140 ? '${text.substring(0, 140)}…' : text}"',
            );
            expect(result.engine, isNot('paddle_v5+manga_ocr'));
          } on OcrException catch (error) {
            // A mode may legitimately lack a model; report it without failing
            // the whole image sweep.
            // ignore: avoid_print
            print(
              '${image.uri.pathSegments.last} ${mode.name} '
              'OCR_ERROR ${error.code} ${error.message}',
            );
          }
        }
      }
    } finally {
      await ocr.dispose();
    }
  });
}
