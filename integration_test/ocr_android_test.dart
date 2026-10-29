import 'dart:io';
import 'dart:math' as math;
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

Future<Directory> _installedModelsDirectory() async {
  return Directory(_modelDir).parent;
}

Future<File> _renderSyntheticImage({bool upsideDown = false}) async {
  const width = 800;
  const height = 240;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  if (upsideDown) {
    canvas.translate(width.toDouble(), height.toDouble());
    canvas.rotate(math.pi);
  }
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
  final file = File(
    '${directory.path}/rikai-ocr-smoke${upsideDown ? '-180' : ''}.png',
  );
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

/// A mixed page: one horizontal caption on the left and a vertical manga
/// column on the right. Auto mode must route each region independently.
Future<File> _renderSyntheticMixedPage() async {
  const width = 800;
  const height = 800;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  final horizontal = TextPainter(
    text: const TextSpan(
      text: 'ありがとう',
      style: TextStyle(
        color: Colors.black,
        fontSize: 56,
        fontFamily: 'sans-serif',
        fontFamilyFallback: ['Noto Sans CJK JP', 'Noto Sans JP'],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  horizontal.paint(canvas, const Offset(32, 64));
  const vertical = ['こ', 'れ', 'は', 'テ', 'ス', 'ト', 'で', 'す'];
  for (var index = 0; index < vertical.length; index++) {
    final painter = TextPainter(
      text: TextSpan(
        text: vertical[index],
        style: const TextStyle(
          color: Colors.black,
          fontSize: 52,
          fontFamily: 'sans-serif',
          fontFamilyFallback: ['Noto Sans CJK JP', 'Noto Sans JP'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(660, 48 + index * 92.0));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/rikai-ocr-mixed-page.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

/// A multi-line page rotated 90° clockwise. A single short line is too sparse
/// for the document-orientation classifier, while a real page has enough
/// structure to produce a confident 90/270 label.
Future<File> _renderSyntheticSidewaysPage({bool clockwise = true}) async {
  const pageWidth = 800;
  const pageHeight = 1200;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (clockwise) {
    canvas.translate(pageHeight.toDouble(), 0);
    canvas.rotate(math.pi / 2);
  } else {
    canvas.translate(0, pageWidth.toDouble());
    canvas.rotate(-math.pi / 2);
  }
  canvas.drawRect(
    Rect.fromLTWH(0, 0, pageWidth.toDouble(), pageHeight.toDouble()),
    Paint()..color = Colors.white,
  );
  for (var line = 0; line < 8; line++) {
    final painter = TextPainter(
      text: const TextSpan(
        text: 'ありがとう',
        style: TextStyle(
          color: Colors.black,
          fontSize: 56,
          fontFamily: 'sans-serif',
          fontFamilyFallback: ['Noto Sans CJK JP', 'Noto Sans JP'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(48, 48 + line * 130.0));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(pageHeight, pageWidth);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final directory = await getTemporaryDirectory();
  final file = File(
    '${directory.path}/rikai-ocr-sideways-page-${clockwise ? '90' : '270'}.png',
  );
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

/// A single vertical Japanese column, similar to a manga speech bubble crop.
Future<File> _renderSyntheticVerticalImage() async {
  const width = 180;
  const height = 620;
  const chars = ['こ', 'れ', 'は', 'テ', 'ス', 'ト', 'で', 'す'];
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  for (var index = 0; index < chars.length; index++) {
    final painter = TextPainter(
      text: TextSpan(
        text: chars[index],
        style: const TextStyle(
          color: Colors.black,
          fontSize: 56,
          fontFamily: 'sans-serif',
          fontFamilyFallback: ['Noto Sans CJK JP', 'Noto Sans JP'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset((width - painter.width) / 2, 24 + index * 70.0),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/rikai-ocr-vertical.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

Future<Map<String, Object?>> _initializeMangaAwareOcr(RikaiOcr ocr) async {
  final models = await _installedModelsDirectory();
  final paddle = Directory('${models.path}/paddle_v5');
  final manga = Directory('${models.path}/manga_ocr');
  final orientation = Directory('${models.path}/orientation');
  File? optional(String path) {
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  return ocr.initialize(
    detModelPath: File('${paddle.path}/det.onnx').path,
    recModelPath: File('${paddle.path}/rec.onnx').path,
    keysPath: File('${paddle.path}/keys.yml').path,
    mangaEncoderPath: optional('${manga.path}/encoder_model.onnx')?.path,
    mangaDecoderPath: optional('${manga.path}/decoder_model.onnx')?.path,
    mangaVocabPath: optional('${manga.path}/vocab.txt')?.path,
    docOrientationPath: optional('${orientation.path}/doc_ori.onnx')?.path,
    textLineOrientationPath: optional(
      '${orientation.path}/textline_ori.onnx',
    )?.path,
  );
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

  testWidgets('horizontal OCR keeps optional sessions lazy', (tester) async {
    final image = await _renderSyntheticImage();
    final ocr = RikaiOcr();
    try {
      final readiness = await _initializeMangaAwareOcr(ocr);
      if (readiness['mangaAvailable'] != true) {
        fail(
          'MangaOCR models are missing. Push build/ocr-models/manga_ocr to '
          '${(await _installedModelsDirectory()).path}/manga_ocr',
        );
      }
      expect(readiness['mangaLoaded'], isFalse);

      await ocr.recognize(imagePath: image.path, mode: OcrMode.horizontal);
      final afterHorizontal = await ocr.prepare(mode: OcrMode.horizontal);
      expect(afterHorizontal['mangaLoaded'], isFalse);

      final afterAuto = await ocr.prepare(mode: OcrMode.auto);
      expect(afterAuto['mangaLoaded'], isTrue);
    } finally {
      await ocr.dispose();
      if (image.existsSync()) await image.delete();
    }
  });

  testWidgets('MangaOCR recognizes a synthetic vertical bubble on Android', (
    tester,
  ) async {
    final models = await _installedModelsDirectory();
    final manga = Directory('${models.path}/manga_ocr');
    for (final name in [
      'encoder_model.onnx',
      'decoder_model.onnx',
      'vocab.txt',
    ]) {
      if (!File('${manga.path}/$name').existsSync()) {
        fail(
          'MangaOCR models are missing. Push them to ${manga.path}/ with:\n'
          'adb push build/ocr-models/manga_ocr/. ${manga.path}/',
        );
      }
    }

    final image = await _renderSyntheticVerticalImage();
    final ocr = RikaiOcr();
    try {
      final readiness = await _initializeMangaAwareOcr(ocr);
      // ignore: avoid_print
      print('MangaOCR readiness=$readiness');
      expect(readiness['mangaReady'], isTrue);
      expect(readiness['mangaLoaded'], isFalse);

      final autoResult = await ocr.recognize(
        imagePath: image.path,
        mode: OcrMode.auto,
      );
      final autoText = composeOcrText(autoResult.blocks);
      // ignore: avoid_print
      print(
        'MangaOCR auto engine=${autoResult.engine} '
        'elapsed=${autoResult.elapsedMs}ms blocks=${autoResult.blocks.length} '
        'text="$autoText"',
      );
      expect(autoResult.engine, 'manga_ocr');
      expect(autoResult.blocks, isNotEmpty);
      expect(autoText, isNotEmpty);
      expect(autoText, contains('これは'));
      final warmed = await ocr.prepare(mode: OcrMode.auto);
      expect(warmed['mangaLoaded'], isTrue);

      final verticalResult = await ocr.recognize(
        imagePath: image.path,
        mode: OcrMode.vertical,
      );
      final verticalText = composeOcrText(verticalResult.blocks);
      // ignore: avoid_print
      print(
        'MangaOCR vertical engine=${verticalResult.engine} '
        'elapsed=${verticalResult.elapsedMs}ms blocks=${verticalResult.blocks.length} '
        'text="$verticalText"',
      );
      expect(verticalResult.engine, 'manga_ocr');
      expect(verticalText, contains('これは'));
    } finally {
      await ocr.dispose();
      if (image.existsSync()) await image.delete();
    }
  });

  testWidgets('auto OCR routes horizontal and vertical regions separately', (
    tester,
  ) async {
    final image = await _renderSyntheticMixedPage();
    final ocr = RikaiOcr();
    try {
      final readiness = await _initializeMangaAwareOcr(ocr);
      if (readiness['mangaAvailable'] != true) {
        fail(
          'MangaOCR models are missing. Push build/ocr-models/manga_ocr to '
          '${(await _installedModelsDirectory()).path}/manga_ocr',
        );
      }
      await ocr.prepare(mode: OcrMode.auto);
      final result = await ocr.recognize(
        imagePath: image.path,
        mode: OcrMode.auto,
      );
      final text = composeOcrText(result.blocks);
      // ignore: avoid_print
      print(
        'Mixed engine=${result.engine} elapsed=${result.elapsedMs}ms '
        'blocks=${result.blocks.length} text="$text"',
      );
      for (final block in result.blocks) {
        // ignore: avoid_print
        print(
          'mixed block orientation=${block.orientation} '
          'rect=(${block.left},${block.top},${block.right},${block.bottom}) '
          '"${block.text}"',
        );
      }
      expect(result.engine, 'paddle_v5+manga_ocr');
      expect(text, contains('ありがとう'));
      expect(text, contains('これは'));
    } finally {
      await ocr.dispose();
      if (image.existsSync()) await image.delete();
    }
  });

  testWidgets('auto OCR corrects a 90-degree sideways page', (tester) async {
    final image = await _renderSyntheticSidewaysPage();
    final ocr = RikaiOcr();
    try {
      final readiness = await _initializeMangaAwareOcr(ocr);
      // ignore: avoid_print
      print('Sideways readiness=$readiness');
      if (readiness['docOrientationReady'] != true) {
        fail(
          'Document orientation model is missing. Push build/ocr-models/'
          'orientation to ${(await _installedModelsDirectory()).path}/orientation',
        );
      }
      final result = await ocr.recognize(
        imagePath: image.path,
        mode: OcrMode.auto,
      );
      final text = composeOcrText(result.blocks);
      // ignore: avoid_print
      print(
        'Sideways engine=${result.engine} elapsed=${result.elapsedMs}ms '
        'blocks=${result.blocks.length} text="$text"',
      );
      expect(result.engine, 'paddle_v5');
      expect(text, contains('ありがとう'));
    } finally {
      await ocr.dispose();
      if (image.existsSync()) await image.delete();
    }
  });

  testWidgets('auto OCR corrects a 270-degree sideways page', (tester) async {
    final image = await _renderSyntheticSidewaysPage(clockwise: false);
    final ocr = RikaiOcr();
    try {
      final readiness = await _initializeMangaAwareOcr(ocr);
      if (readiness['docOrientationReady'] != true) {
        fail(
          'Document orientation model is missing. Push build/ocr-models/'
          'orientation to ${(await _installedModelsDirectory()).path}/orientation',
        );
      }
      final result = await ocr.recognize(
        imagePath: image.path,
        mode: OcrMode.auto,
      );
      final text = composeOcrText(result.blocks);
      // ignore: avoid_print
      print(
        'Sideways 270 engine=${result.engine} elapsed=${result.elapsedMs}ms '
        'blocks=${result.blocks.length} text="$text"',
      );
      expect(result.engine, 'paddle_v5');
      expect(text, contains('ありがとう'));
    } finally {
      await ocr.dispose();
      if (image.existsSync()) await image.delete();
    }
  });

  testWidgets('auto OCR corrects an upside-down horizontal page', (
    tester,
  ) async {
    final image = await _renderSyntheticImage(upsideDown: true);
    final ocr = RikaiOcr();
    try {
      final readiness = await _initializeMangaAwareOcr(ocr);
      // ignore: avoid_print
      print('Orientation readiness=$readiness');
      if (readiness['textLineOrientationReady'] != true) {
        fail(
          'Text-line orientation model is missing. Push build/ocr-models/'
          'orientation to ${(await _installedModelsDirectory()).path}/orientation',
        );
      }
      final result = await ocr.recognize(
        imagePath: image.path,
        mode: OcrMode.auto,
      );
      final text = composeOcrText(result.blocks);
      // ignore: avoid_print
      print(
        'Upside-down engine=${result.engine} '
        'elapsed=${result.elapsedMs}ms blocks=${result.blocks.length} '
        'text="$text"',
      );
      expect(result.engine, 'paddle_v5');
      expect(text, contains('ありがとう'));
    } finally {
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
