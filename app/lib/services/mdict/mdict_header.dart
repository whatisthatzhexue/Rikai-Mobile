import 'mdict_worker.dart';

/// Validates the small subset of an MDX/MDD header that the app can safely
/// open. `Encrypted: 2` is intentionally accepted: several real dictionaries
/// use it for a record-block layout that `dict_reader` can read, while value 1
/// still means an unsupported key-encrypted file.
void validateMdictHeader(Map<String, String> header) {
  final versionText = header['GeneratedByEngineVersion'] ?? '';
  final version = double.tryParse(versionText);
  if (version != null && version >= 3.0) {
    throw MdictException(
      MdictErrorCode.unsupportedFormat,
      '暂不支持 MDict $versionText 词典',
    );
  }

  final encrypted = (header['Encrypted'] ?? 'No').trim().toLowerCase();
  if (encrypted.isNotEmpty &&
      encrypted != 'no' &&
      encrypted != '0' &&
      encrypted != '2') {
    throw MdictException(
      MdictErrorCode.encrypted,
      '暂不支持加密词典（Encrypted=${header['Encrypted']}）',
    );
  }
}
