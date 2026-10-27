import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Result codes for UniDic path validation.
enum UnidicValidationCode {
  valid,
  notConfigured,
  notFound,
  missingFiles,
  unreadable,
  invalidDictionary,
  unsupportedVersion,
  unsupportedCharset,
  emptyDictionary,
}

/// Outcome of validating a user-supplied UniDic directory.
class UnidicValidation {
  const UnidicValidation({
    required this.code,
    required this.path,
    this.message = '',
    this.missingFiles = const [],
    this.fileSizes = const {},
    this.version,
    this.charset,
    this.entryCount,
  });

  final UnidicValidationCode code;
  final String path;
  final String message;
  final List<String> missingFiles;
  final Map<String, int> fileSizes;
  final int? version;
  final String? charset;
  final int? entryCount;

  bool get isValid => code == UnidicValidationCode.valid;

  /// User-facing summary for the settings page.
  String get summary {
    if (message.isNotEmpty) return message;
    switch (code) {
      case UnidicValidationCode.valid:
        return 'UniDic 校验通过';
      case UnidicValidationCode.notConfigured:
        return '尚未填写 UniDic 目录';
      case UnidicValidationCode.notFound:
        return '目录不存在或无法访问';
      case UnidicValidationCode.missingFiles:
        return '缺少文件：${missingFiles.join('、')}';
      case UnidicValidationCode.unreadable:
        return '无法读取 UniDic 文件';
      case UnidicValidationCode.invalidDictionary:
        return '不是有效的 MeCab 二进制词典';
      case UnidicValidationCode.unsupportedVersion:
        return '不支持的词典版本：$version（需要 102）';
      case UnidicValidationCode.unsupportedCharset:
        return '不支持的编码：$charset（需要 UTF-8）';
      case UnidicValidationCode.emptyDictionary:
        return '词典不包含任何词条';
    }
  }
}

/// Validates a UniDic directory without modifying it.
///
/// MeCab loads `sys.dic` with mmap, so the checks here mirror the header checks
/// performed by `Dictionary::open()` in the vendored MeCab source: magic XOR
/// file size, format version 102, UTF-8 charset, a non-empty lexicon and a
/// consistent file length. The directory itself is never written to.
class UnidicValidator {
  const UnidicValidator._();

  static const List<String> requiredFiles = [
    'sys.dic',
    'matrix.bin',
    'char.bin',
    'unk.dic',
    'dicrc',
  ];

  static const int _dictionaryMagicId = 0xef718f77;
  static const int _expectedVersion = 102;
  static const int _headerSize = 72;

  /// Trims whitespace and a trailing path separator, and accepts `file://`.
  static String normalizePath(String input) {
    var path = input.trim();
    if (path.startsWith('file://')) path = path.substring('file://'.length);
    while (path.length > 1 && (path.endsWith('/') || path.endsWith(r'\'))) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  static String _join(String directory, String name) {
    if (directory.endsWith('/') || directory.endsWith(r'\')) {
      return '$directory$name';
    }
    return '$directory/$name';
  }

  static Future<UnidicValidation> validate(String rawPath) async {
    final path = normalizePath(rawPath);
    if (path.isEmpty) {
      return const UnidicValidation(
        code: UnidicValidationCode.notConfigured,
        path: '',
      );
    }

    final hasDirectory = await Directory(path).exists();
    if (!hasDirectory) {
      return UnidicValidation(
        code: UnidicValidationCode.notFound,
        path: path,
        message: '目录不存在或无法访问（若路径正确，请确认已授予所有文件访问）',
      );
    }

    final missing = <String>[];
    final sizes = <String, int>{};
    for (final name in requiredFiles) {
      final file = File(_join(path, name));
      try {
        if (!await file.exists()) {
          missing.add(name);
          continue;
        }
        final size = await file.length();
        sizes[name] = size;
        if (size == 0) missing.add(name);
      } on FileSystemException catch (error) {
        return UnidicValidation(
          code: UnidicValidationCode.unreadable,
          path: path,
          message: '读取 $name 失败：${error.message}',
          fileSizes: Map.unmodifiable(sizes),
        );
      }
    }
    if (missing.isNotEmpty) {
      return UnidicValidation(
        code: UnidicValidationCode.missingFiles,
        path: path,
        missingFiles: List.unmodifiable(missing),
        fileSizes: Map.unmodifiable(sizes),
      );
    }

    RandomAccessFile? reader;
    try {
      final sysDic = File(_join(path, 'sys.dic'));
      reader = await sysDic.open();
      final fileLength = await reader.length();
      if (fileLength < _headerSize) {
        return UnidicValidation(
          code: UnidicValidationCode.invalidDictionary,
          path: path,
          message: 'sys.dic 过小，文件可能损坏',
          fileSizes: Map.unmodifiable(sizes),
        );
      }
      final header = await reader.read(_headerSize);
      if (header.length < _headerSize) {
        return UnidicValidation(
          code: UnidicValidationCode.invalidDictionary,
          path: path,
          message: 'sys.dic 文件头不完整',
          fileSizes: Map.unmodifiable(sizes),
        );
      }

      final data = ByteData.sublistView(header);
      final magic = data.getUint32(0, Endian.little);
      final version = data.getUint32(4, Endian.little);
      final entryCount = data.getUint32(12, Endian.little);
      final leftSize = data.getUint32(16, Endian.little);
      final rightSize = data.getUint32(20, Endian.little);
      final doubleArraySize = data.getUint32(24, Endian.little);
      final tokenSize = data.getUint32(28, Endian.little);
      final featureSize = data.getUint32(32, Endian.little);

      final charsetBytes = header.sublist(40, _headerSize);
      final nulIndex = charsetBytes.indexOf(0);
      final charset = utf8
          .decode(
            charsetBytes.sublist(
              0,
              nulIndex < 0 ? charsetBytes.length : nulIndex,
            ),
            allowMalformed: true,
          )
          .trim();

      final base = UnidicValidation(
        code: UnidicValidationCode.invalidDictionary,
        path: path,
        fileSizes: Map.unmodifiable(sizes),
        version: version,
        charset: charset,
        entryCount: entryCount,
      );

      if ((magic ^ fileLength) != _dictionaryMagicId) {
        return _withMessage(base, 'sys.dic 文件头校验失败，文件可能不完整或不是 MeCab 二进制词典');
      }
      if (version != _expectedVersion) {
        return _withCode(base, UnidicValidationCode.unsupportedVersion);
      }
      if (charset.toUpperCase() != 'UTF-8') {
        return _withCode(base, UnidicValidationCode.unsupportedCharset);
      }
      if (entryCount == 0) {
        return _withCode(base, UnidicValidationCode.emptyDictionary);
      }
      if (leftSize == 0 || rightSize == 0) {
        return _withMessage(base, 'sys.dic 的连接矩阵尺寸无效');
      }
      final expectedLength =
          _headerSize + doubleArraySize + tokenSize + featureSize;
      if (expectedLength != fileLength) {
        return _withMessage(base, 'sys.dic 长度与文件头声明不一致（可能复制不完整）');
      }

      return UnidicValidation(
        code: UnidicValidationCode.valid,
        path: path,
        fileSizes: Map.unmodifiable(sizes),
        version: version,
        charset: charset,
        entryCount: entryCount,
      );
    } on FileSystemException catch (error) {
      return UnidicValidation(
        code: UnidicValidationCode.unreadable,
        path: path,
        message: '读取 sys.dic 失败：${error.message}',
        fileSizes: Map.unmodifiable(sizes),
      );
    } finally {
      await reader?.close();
    }
  }

  static UnidicValidation _withMessage(UnidicValidation base, String message) {
    return UnidicValidation(
      code: base.code,
      path: base.path,
      message: message,
      fileSizes: base.fileSizes,
      version: base.version,
      charset: base.charset,
      entryCount: base.entryCount,
    );
  }

  static UnidicValidation _withCode(
    UnidicValidation base,
    UnidicValidationCode code,
  ) {
    return UnidicValidation(
      code: code,
      path: base.path,
      fileSizes: base.fileSizes,
      version: base.version,
      charset: base.charset,
      entryCount: base.entryCount,
    );
  }
}
