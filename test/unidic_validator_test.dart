import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/mecab/unidic_validator.dart';

const int _headerSize = 72;
const int _doubleArraySize = 24;
const int _tokenSize = 32;
const int _featureSize = 64;

Future<Directory> _createDictionary({
  int version = 102,
  String charset = 'UTF-8',
  int entryCount = 1234,
  bool validMagic = true,
  bool writeMatrix = true,
  int extraBytes = 0,
}) async {
  final directory = await Directory.systemTemp.createTemp('rikai_unidic_');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  final declaredLength =
      _headerSize + _doubleArraySize + _tokenSize + _featureSize;
  final actualLength = declaredLength + extraBytes;
  final bytes = Uint8List(actualLength);
  final data = ByteData.sublistView(bytes);
  final magic = validMagic ? (0xef718f77 ^ actualLength) : 0x12345678;
  data.setUint32(0, magic, Endian.little);
  data.setUint32(4, version, Endian.little);
  data.setUint32(12, entryCount, Endian.little);
  data.setUint32(16, 1, Endian.little); // left context size
  data.setUint32(20, 1, Endian.little); // right context size
  data.setUint32(24, _doubleArraySize, Endian.little);
  data.setUint32(28, _tokenSize, Endian.little);
  data.setUint32(32, _featureSize, Endian.little);
  final charsetBytes = charset.codeUnits;
  bytes.setRange(40, 40 + charsetBytes.length, charsetBytes);

  await File('${directory.path}/sys.dic').writeAsBytes(bytes);
  await File('${directory.path}/char.bin').writeAsBytes([1]);
  await File('${directory.path}/unk.dic').writeAsBytes([1]);
  await File('${directory.path}/dicrc').writeAsString('charset = UTF-8\n');
  if (writeMatrix) {
    await File('${directory.path}/matrix.bin').writeAsBytes([1, 2, 3, 4]);
  }
  return directory;
}

void main() {
  test('accepts a well-formed dictionary and reports metadata', () async {
    final directory = await _createDictionary(entryCount: 1027505);

    final result = await UnidicValidator.validate(directory.path);

    expect(result.isValid, isTrue);
    expect(result.code, UnidicValidationCode.valid);
    expect(result.entryCount, 1027505);
    expect(result.version, 102);
    expect(result.charset, 'UTF-8');
    expect(result.fileSizes.keys, containsAll(UnidicValidator.requiredFiles));
    expect(result.fileSizes['matrix.bin'], 4);
  });

  test('accepts a trailing separator and file:// prefix', () async {
    final directory = await _createDictionary();

    final withSlash = await UnidicValidator.validate('${directory.path}/');
    final withScheme = await UnidicValidator.validate(
      'file://${directory.path}',
    );

    expect(withSlash.isValid, isTrue);
    expect(withScheme.isValid, isTrue);
  });

  test('reports an unconfigured path', () async {
    final result = await UnidicValidator.validate('   ');

    expect(result.isValid, isFalse);
    expect(result.code, UnidicValidationCode.notConfigured);
  });

  test('reports a missing directory', () async {
    final result = await UnidicValidator.validate(
      '${Directory.systemTemp.path}/rikai-does-not-exist',
    );

    expect(result.isValid, isFalse);
    expect(result.code, UnidicValidationCode.notFound);
  });

  test('reports missing required files', () async {
    final directory = await _createDictionary(writeMatrix: false);

    final result = await UnidicValidator.validate(directory.path);

    expect(result.isValid, isFalse);
    expect(result.code, UnidicValidationCode.missingFiles);
    expect(result.missingFiles, ['matrix.bin']);
  });

  test('rejects a broken magic value', () async {
    final directory = await _createDictionary(validMagic: false);

    final result = await UnidicValidator.validate(directory.path);

    expect(result.isValid, isFalse);
    expect(result.code, UnidicValidationCode.invalidDictionary);
    expect(result.message, contains('文件头校验失败'));
  });

  test('rejects an unsupported dictionary version', () async {
    final directory = await _createDictionary(version: 101);

    final result = await UnidicValidator.validate(directory.path);

    expect(result.isValid, isFalse);
    expect(result.code, UnidicValidationCode.unsupportedVersion);
    expect(result.version, 101);
  });

  test('rejects a non UTF-8 dictionary', () async {
    final directory = await _createDictionary(charset: 'EUC-JP');

    final result = await UnidicValidator.validate(directory.path);

    expect(result.isValid, isFalse);
    expect(result.code, UnidicValidationCode.unsupportedCharset);
    expect(result.charset, 'EUC-JP');
  });

  test('rejects an empty lexicon', () async {
    final directory = await _createDictionary(entryCount: 0);

    final result = await UnidicValidator.validate(directory.path);

    expect(result.isValid, isFalse);
    expect(result.code, UnidicValidationCode.emptyDictionary);
  });

  test('rejects a truncated or padded sys.dic', () async {
    final directory = await _createDictionary(extraBytes: 8);

    final result = await UnidicValidator.validate(directory.path);

    expect(result.isValid, isFalse);
    expect(result.code, UnidicValidationCode.invalidDictionary);
    expect(result.message, contains('长度与文件头声明不一致'));
  });

  test('normalizes paths without touching the file system', () {
    expect(
      UnidicValidator.normalizePath('  /sdcard/Download/unidic/  '),
      '/sdcard/Download/unidic',
    );
    expect(
      UnidicValidator.normalizePath('file:///sdcard/Download/unidic'),
      '/sdcard/Download/unidic',
    );
    expect(UnidicValidator.normalizePath('/'), '/');
  });
}
