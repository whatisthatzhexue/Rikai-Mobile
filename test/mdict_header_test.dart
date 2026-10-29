import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/mdict/mdict_header.dart';
import 'package:rikai_mobile/services/mdict/mdict_worker.dart';

void main() {
  test(
    'accepts the record-layout value Encrypted=2 used by real dictionaries',
    () {
      expect(
        () => validateMdictHeader({
          'GeneratedByEngineVersion': '2.0',
          'Encrypted': '2',
        }),
        returnsNormally,
      );
    },
  );

  test('accepts unencrypted headers and rejects key-encrypted v3 files', () {
    expect(
      () => validateMdictHeader({
        'GeneratedByEngineVersion': '2.0',
        'Encrypted': 'No',
      }),
      returnsNormally,
    );
    expect(
      () => validateMdictHeader({
        'GeneratedByEngineVersion': '3.0',
        'Encrypted': 'No',
      }),
      throwsA(
        isA<MdictException>().having(
          (error) => error.code,
          'code',
          MdictErrorCode.unsupportedFormat,
        ),
      ),
    );
    expect(
      () => validateMdictHeader({
        'GeneratedByEngineVersion': '2.0',
        'Encrypted': '1',
      }),
      throwsA(
        isA<MdictException>().having(
          (error) => error.code,
          'code',
          MdictErrorCode.encrypted,
        ),
      ),
    );
  });
}
