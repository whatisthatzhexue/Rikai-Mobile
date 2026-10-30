import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/services/agent/familiarization/profile_fingerprint.dart';

void main() {
  test('dictionary fingerprint changes when the MDX stat changes', () async {
    final directory = await Directory.systemTemp.createTemp('rikai-agent-fp');
    addTearDown(() => directory.delete(recursive: true));
    final mdx = File(p.join(directory.path, 'dict.mdx'));
    await mdx.writeAsString('a');
    final dictionary = DictionaryInfo(
      id: 'dict_a',
      title: 'A',
      mdxPath: mdx.path,
      entryCount: 10,
      encoding: 'UTF-8',
    );

    final first = await dictionaryProfileFingerprint(dictionary);
    await mdx.writeAsString('ab');
    final second = await dictionaryProfileFingerprint(dictionary);
    expect(second, isNot(first));
  });

  test(
    'UniDic fingerprint is stable and path hash ignores trailing slashes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rikai-unidic-fp',
      );
      addTearDown(() => directory.delete(recursive: true));
      await File(p.join(directory.path, 'sys.dic')).writeAsString('sys');
      await File(p.join(directory.path, 'matrix.bin')).writeAsString('matrix');

      final first = await unidicProfileFingerprint(directory.path);
      final second = await unidicProfileFingerprint('${directory.path}/');
      expect(second, first);
      expect(
        unidicPathHash('${directory.path}/'),
        unidicPathHash(directory.path),
      );
    },
  );
}
