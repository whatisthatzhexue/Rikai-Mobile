import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:rikai_mobile/services/capture/capture_storage.dart';

void main() {
  late Directory root;
  late CaptureStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rikai-capture-storage-');
    storage = CaptureStorage(temporaryDirectory: () async => root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('rotates a private session copy clockwise and overwrites it', () async {
    final directory = await storage.sessionDirectory();
    final file = File(p.join(directory.path, 'photo.png'));
    final source = img.Image(width: 2, height: 1);
    source.setPixelRgba(0, 0, 255, 0, 0, 255);
    source.setPixelRgba(1, 0, 0, 0, 255, 255);
    await file.writeAsBytes(img.encodePng(source), flush: true);

    await storage.rotateSessionPhoto(file.path);

    final decoded = img.decodeImage(await file.readAsBytes());
    expect(decoded, isNotNull);
    expect(decoded!.width, 1);
    expect(decoded.height, 2);
    // Clockwise: the original left (red) becomes the top pixel.
    expect(decoded.getPixel(0, 0).r, 255);
    expect(decoded.getPixel(0, 0).g, 0);
    expect(decoded.getPixel(0, 1).b, 255);
  });

  test('refuses to rotate a path outside the session directory', () async {
    final outside = File(p.join(root.path, 'outside.png'));
    await outside.writeAsBytes(
      img.encodePng(img.Image(width: 2, height: 2)),
      flush: true,
    );
    await expectLater(
      storage.rotateSessionPhoto(outside.path),
      throwsA(isA<FileSystemException>()),
    );
  });
}
