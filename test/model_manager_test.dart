import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/ocr_model.dart';
import 'package:rikai_mobile/services/ocr/model_manager.dart';

final class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile(this._file, this.name, this._length);

  final File _file;
  final int _length;

  @override
  final String name;

  @override
  Uri get uri => _file.uri;

  @override
  XFile get xFile => XFile(_file.path);

  @override
  int? lengthSync() => _length;

  @override
  Future<int?> length() async => _length;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      _file.openRead().map(Uint8List.fromList);
}

void main() {
  late Directory root;
  late HttpServer server;
  late Uint8List payload;
  var rangeRequests = 0;
  var force416 = false;
  var badContentRange = false;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rikai-model-test-');
    payload = Uint8List.fromList(
      List<int>.generate(4096, (index) => (index * 31 + 7) & 0xff),
    );
    rangeRequests = 0;
    force416 = false;
    badContentRange = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      var start = 0;
      if (range != null) {
        rangeRequests++;
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      }
      if (force416 || start >= payload.length) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await request.response.close();
        return;
      }
      request.response.statusCode = range == null
          ? HttpStatus.ok
          : HttpStatus.partialContent;
      request.response.headers.contentType = ContentType.binary;
      if (range != null) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          badContentRange
              ? 'bytes 999-${payload.length - 1}/${payload.length}'
              : 'bytes $start-${payload.length - 1}/${payload.length}',
        );
      }
      request.response.contentLength = payload.length - start;
      request.response.add(payload.sublist(start));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (root.existsSync()) await root.delete(recursive: true);
  });

  OcrModelSet setUpSet(String url) => OcrModelSet(
    id: 'paddle_v5',
    displayName: 'PaddleOCR',
    license: 'Apache-2.0',
    files: [
      OcrModelFile(
        name: 'det.onnx',
        urls: [url],
        size: payload.length,
        sha256: sha256.convert(payload).toString(),
      ),
    ],
  );

  test('downloads, verifies and installs a model file', () async {
    final set = setUpSet(
      'http://${server.address.address}:${server.port}/det.onnx',
    );
    final manager = OcrModelManager(rootDirectory: () async => root);
    final progress = <OcrModelDownloadProgress>[];

    await manager.downloadSet(set, onProgress: progress.add);

    final file = File('${root.path}/models/paddle_v5/det.onnx');
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), payload);
    expect(rangeRequests, 0);
    expect(progress, isNotEmpty);
    final status = await manager.status(set);
    expect(status.isInstalled, isTrue);
    expect(status.installedBytes, payload.length);
  });

  test('resumes a partial .part download with a Range request', () async {
    final set = setUpSet(
      'http://${server.address.address}:${server.port}/det.onnx',
    );
    final directory = Directory('${root.path}/models/paddle_v5');
    await directory.create(recursive: true);
    final part = File('${directory.path}/det.onnx.part');
    await part.writeAsBytes(payload.sublist(0, 900), flush: true);

    final manager = OcrModelManager(rootDirectory: () async => root);
    await manager.downloadSet(set);

    expect(rangeRequests, greaterThan(0));
    final file = File('${directory.path}/det.onnx');
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), payload);
  });

  test('status is read-only and an empty set is never installed', () async {
    final manager = OcrModelManager(
      rootDirectory: () async => root,
      availableSpace: (_) async => 1000,
    );
    const empty = OcrModelSet(
      id: 'empty',
      displayName: 'Empty',
      license: 'Apache-2.0',
      files: [],
    );
    final status = await manager.status(empty);
    expect(status.isInstalled, isFalse);
    expect(Directory('${root.path}/models').existsSync(), isFalse);

    final check = await manager.validateModelsDirectory(
      '${root.path}/new-models',
      requiredBytes: 2000,
    );
    expect(check.ok, isFalse);
    expect(check.message, contains('剩余空间不足'));
  });

  test('migrates models to a new directory and can move them', () async {
    final set = setUpSet('https://example.invalid/det.onnx');
    final sourceDirectory = Directory('${root.path}/models/paddle_v5');
    await sourceDirectory.create(recursive: true);
    await File('${sourceDirectory.path}/det.onnx').writeAsBytes(payload);
    final destination = Directory('${root.path}/migrated');
    final manager = OcrModelManager(rootDirectory: () async => root);
    final progress = <OcrModelMigrationProgress>[];

    await manager.migrateModels(
      sets: [set],
      destinationPath: destination.path,
      move: true,
      onProgress: progress.add,
    );

    final moved = File('${destination.path}/paddle_v5/det.onnx');
    expect(moved.existsSync(), isTrue);
    expect(moved.readAsBytesSync(), payload);
    expect(File('${sourceDirectory.path}/det.onnx').existsSync(), isFalse);
    expect(progress, isNotEmpty);

    final newManager = OcrModelManager(
      modelsDirectory: () async => destination.path,
    );
    expect((await newManager.status(set)).isInstalled, isTrue);
  });

  test('a 416 or mismatched Content-Range resets the partial file', () async {
    final set = setUpSet(
      'http://${server.address.address}:${server.port}/det.onnx',
    );
    final directory = Directory('${root.path}/models/paddle_v5');
    await directory.create(recursive: true);
    final part = File('${directory.path}/det.onnx.part');
    await part.writeAsBytes(payload.sublist(0, 900), flush: true);
    force416 = true;
    final manager = OcrModelManager(rootDirectory: () async => root);
    await expectLater(
      manager.downloadSet(set),
      throwsA(isA<OcrModelException>()),
    );
    expect(part.existsSync(), isFalse);

    await part.writeAsBytes(payload.sublist(0, 900), flush: true);
    force416 = false;
    badContentRange = true;
    await expectLater(
      manager.downloadSet(set),
      throwsA(isA<OcrModelException>()),
    );
    expect(part.existsSync(), isFalse);
  });

  test('uses a custom mirror before the manifest URLs', () async {
    final set = setUpSet('https://example.invalid/det.onnx');
    final manager = OcrModelManager(rootDirectory: () async => root);

    await manager.downloadSet(
      set,
      customMirror: 'http://${server.address.address}:${server.port}',
    );

    final file = File('${root.path}/models/paddle_v5/det.onnx');
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), payload);
  });

  test('imports selected local files and verifies their hash', () async {
    final set = setUpSet('https://example.invalid/det.onnx');
    final source = File('${root.path}/picked.onnx');
    await source.writeAsBytes(payload, flush: true);
    final manager = OcrModelManager(rootDirectory: () async => root);

    await manager.importSet(set, [
      _TestPlatformFile(source, 'det.onnx', payload.length),
    ]);

    final installed = File('${root.path}/models/paddle_v5/det.onnx');
    expect(installed.existsSync(), isTrue);
    expect(installed.readAsBytesSync(), payload);
    final status = await manager.status(set);
    expect(status.isInstalled, isTrue);
  });

  test('imports upstream inference.onnx names by role and size', () async {
    final detBytes = Uint8List.fromList(List<int>.filled(101, 1));
    final recBytes = Uint8List.fromList(List<int>.filled(203, 2));
    final keysBytes = Uint8List.fromList(List<int>.filled(53, 3));
    final detSource = File('${root.path}/det-download.onnx');
    final recSource = File('${root.path}/rec-download.onnx');
    final keysSource = File('${root.path}/keys-download.yml');
    await detSource.writeAsBytes(detBytes, flush: true);
    await recSource.writeAsBytes(recBytes, flush: true);
    await keysSource.writeAsBytes(keysBytes, flush: true);
    final set = OcrModelSet(
      id: 'paddle_v5',
      displayName: 'PaddleOCR',
      license: 'Apache-2.0',
      files: [
        OcrModelFile(
          name: 'det.onnx',
          urls: const ['https://example.invalid/det'],
          size: detBytes.length,
          sha256: sha256.convert(detBytes).toString(),
        ),
        OcrModelFile(
          name: 'rec.onnx',
          urls: const ['https://example.invalid/rec'],
          size: recBytes.length,
          sha256: sha256.convert(recBytes).toString(),
        ),
        OcrModelFile(
          name: 'keys.yml',
          urls: const ['https://example.invalid/keys'],
          size: keysBytes.length,
          sha256: sha256.convert(keysBytes).toString(),
        ),
      ],
    );
    final manager = OcrModelManager(rootDirectory: () async => root);

    await manager.importSet(set, [
      _TestPlatformFile(detSource, 'inference.onnx', detBytes.length),
      _TestPlatformFile(recSource, 'inference.onnx', recBytes.length),
      _TestPlatformFile(keysSource, 'inference.yml', keysBytes.length),
    ]);

    final directory = Directory('${root.path}/models/paddle_v5');
    expect(File('${directory.path}/det.onnx').readAsBytesSync(), detBytes);
    expect(File('${directory.path}/rec.onnx').readAsBytesSync(), recBytes);
    expect(File('${directory.path}/keys.yml').readAsBytesSync(), keysBytes);
    expect((await manager.status(set)).isInstalled, isTrue);
  });

  test(
    'import keeps already installed files and only fills the gaps',
    () async {
      final detBytes = Uint8List.fromList(List<int>.filled(101, 4));
      final recBytes = Uint8List.fromList(List<int>.filled(203, 5));
      final set = OcrModelSet(
        id: 'paddle_v5',
        displayName: 'PaddleOCR',
        license: 'Apache-2.0',
        files: [
          OcrModelFile(
            name: 'det.onnx',
            urls: const ['https://example.invalid/det'],
            size: detBytes.length,
            sha256: sha256.convert(detBytes).toString(),
          ),
          OcrModelFile(
            name: 'rec.onnx',
            urls: const ['https://example.invalid/rec'],
            size: recBytes.length,
            sha256: sha256.convert(recBytes).toString(),
          ),
        ],
      );
      final directory = Directory('${root.path}/models/paddle_v5');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/det.onnx',
      ).writeAsBytes(detBytes, flush: true);
      final recSource = File('${root.path}/rec-download.onnx');
      await recSource.writeAsBytes(recBytes, flush: true);
      final manager = OcrModelManager(rootDirectory: () async => root);

      await manager.importSet(set, [
        _TestPlatformFile(recSource, 'inference.onnx', recBytes.length),
      ]);

      expect(File('${directory.path}/det.onnx').readAsBytesSync(), detBytes);
      expect(File('${directory.path}/rec.onnx').readAsBytesSync(), recBytes);
      expect((await manager.status(set)).isInstalled, isTrue);
    },
  );
}
