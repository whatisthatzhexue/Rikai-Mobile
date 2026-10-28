import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rikai_mobile/services/ocr/ocr_text_composer.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

const String _modelDir = String.fromEnvironment(
  'RIKAI_OCR_MODEL_DIR',
  defaultValue: '/sdcard/Download/rikai-models/paddle_v5',
);

Future<File> _renderSyntheticImage() async {
  const width = 800;
  const height = 240;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  final painter = TextPainter(
    text: const TextSpan(
      text: 'ありがとう',
      style: TextStyle(
        color: Colors.black,
        fontSize: 64,
        fontFamily: 'sans-serif',
        fontFamilyFallback: ['Noto Sans CJK JP', 'Noto Sans JP'],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, const Offset(32, 72));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/rikai-ocr-smoke.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> checkModels() async {
    final det = File('$_modelDir/det.onnx');
    final rec = File('$_modelDir/rec.onnx');
    final keys = File('$_modelDir/keys.yml');
    if (!det.existsSync() || !rec.existsSync() || !keys.existsSync()) {
      fail(
        'PaddleOCR models are missing. Push them to $_modelDir with:\n'
        'adb push build/ocr-models/paddle_v5 /sdcard/Download/rikai-models/',
      );
    }
  }

  testWidgets('PaddleOCR recognizes a synthetic Japanese line on Android', (
    tester,
  ) async {
    final det = File('$_modelDir/det.onnx');
    final rec = File('$_modelDir/rec.onnx');
    final keys = File('$_modelDir/keys.yml');
    if (!det.existsSync() || !rec.existsSync() || !keys.existsSync()) {
      fail(
        'PaddleOCR models are missing. Push them to $_modelDir with:\n'
        'adb push build/ocr-models/paddle_v5 /sdcard/Download/rikai-models/',
      );
    }

    final image = await _renderSyntheticImage();
    final ocr = RikaiOcr();
    final events = <OcrProgress>[];
    final subscription = ocr.progress.listen(events.add);
    try {
      final readiness = await ocr.initialize(
        detModelPath: det.path,
        recModelPath: rec.path,
        keysPath: keys.path,
      );
      // ignore: avoid_print
      print('OCR readiness=$readiness');
      expect(readiness['engine'], 'paddle_v5');

      final result = await ocr.recognize(
        imagePath: image.path,
        mode: OcrMode.horizontal,
      );
      final text = composeOcrText(result.blocks);
      // ignore: avoid_print
      print(
        'PaddleOCR engine=${result.engine} elapsed=${result.elapsedMs}ms '
        'blocks=${result.blocks.length} text="$text"',
      );
      for (final block in result.blocks) {
        // ignore: avoid_print
        print(
          'block conf=${block.confidence.toStringAsFixed(3)} '
          'rect=(${block.left},${block.top},${block.right},${block.bottom}) '
          '"${block.text}"',
        );
      }
      expect(result.engine, 'paddle_v5');
      expect(result.blocks, isNotEmpty);
      expect(text, isNotEmpty);
      expect(text.replaceAll('\n', ''), contains('ありがと'));
      expect(events.any((event) => event.stage == 'detect'), isTrue);
      expect(events.any((event) => event.stage == 'done'), isTrue);
    } finally {
      await subscription.cancel();
      await ocr.dispose();
      if (image.existsSync()) await image.delete();
    }
  });

  testWidgets('PaddleOCR cancellation returns CANCELLED', (tester) async {
    await checkModels();
    final det = File('$_modelDir/det.onnx');
    final rec = File('$_modelDir/rec.onnx');
    final keys = File('$_modelDir/keys.yml');
    final image = await _renderSyntheticImage();
    final ocr = RikaiOcr();
    var cancelRequested = false;
    final subscription = ocr.progress.listen((event) {
      if (!cancelRequested && event.stage == 'detect') {
        cancelRequested = true;
        ocr.cancel();
      }
    });
    try {
      await ocr.initialize(
        detModelPath: det.path,
        recModelPath: rec.path,
        keysPath: keys.path,
      );
      await expectLater(
        ocr.recognize(imagePath: image.path, mode: OcrMode.horizontal),
        throwsA(
          isA<OcrException>().having(
            (error) => error.code,
            'code',
            'CANCELLED',
          ),
        ),
      );
    } finally {
      await subscription.cancel();
      await ocr.dispose();
      if (image.existsSync()) await image.delete();
    }
  });
}
