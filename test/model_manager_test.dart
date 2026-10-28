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

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rikai-model-test-');
    payload = Uint8List.fromList(
      List<int>.generate(4096, (index) => (index * 31 + 7) & 0xff),
    );
    rangeRequests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      var start = 0;
      if (range != null) {
        rangeRequests++;
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      }
      if (start >= payload.length) {
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
          'bytes $start-${payload.length - 1}/${payload.length}',
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
}
