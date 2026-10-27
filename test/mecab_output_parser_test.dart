import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/mecab/mecab_output_parser.dart';

// Real MeCab/UniDic 2025.12 output captured on the Android emulator.
const String _taLine =
    'た\t助動詞,*,*,*,助動詞-タ,連体形-一般,タ,た,た,タ,た,タ,和,*,*,*,*,'
    '*,*,助動,タ,タ,タ,タ,*,"動詞%F2@1,形容詞%F4@-2",*,5948916285711041,21642';

const String _waLine =
    'は\t助詞,係助詞,*,*,*,*,ハ,は,は,ワ,は,ワ,和,*,*,*,*,*,*,係助,ハ,ハ,'
    'ハ,ハ,*,"動詞%F2@0,名詞%F1,形容詞%F2@-1",*,8059703733133824,29321';

void main() {
  group('splitMecabFeatures', () {
    test('keeps quoted comma fields together', () {
      final fields = splitMecabFeatures(
        '助動詞,*,*,*,助動詞-タ,連体形-一般,タ,た,た,タ,た,タ,和,*,*,*,*,*,'
        '*,助動,タ,タ,タ,タ,*,"動詞%F2@1,形容詞%F4@-2",*,5948916285711041,21642',
      );

      expect(fields, hasLength(29));
      expect(fields[25], '動詞%F2@1,形容詞%F4@-2');
      expect(fields[27], '5948916285711041');
      expect(fields[28], '21642');
    });

    test('handles a quoted field with two commas', () {
      final fields = splitMecabFeatures(
        '助詞,係助詞,*,*,*,*,ハ,は,は,ワ,は,ワ,和,*,*,*,*,*,*,係助,ハ,ハ,'
        'ハ,ハ,*,"動詞%F2@0,名詞%F1,形容詞%F2@-1",*,8059703733133824,29321',
      );

      expect(fields, hasLength(29));
      expect(fields[25], '動詞%F2@0,名詞%F1,形容詞%F2@-1');
    });

    test('unescapes doubled quotes', () {
      expect(splitMecabFeatures('a,"x""y",b'), ['a', 'x"y', 'b']);
    });

    test('keeps plain fields and empty values', () {
      expect(splitMecabFeatures('a,,b,'), ['a', '', 'b', '']);
      expect(splitMecabFeatures(''), isEmpty);
    });
  });

  group('parseMecabOutput', () {
    test('parses real UniDic rows', () {
      final nodes = parseMecabOutput('$_taLine\nEOS\n');

      expect(nodes, hasLength(1));
      expect(nodes.single.surface, 'た');
      expect(nodes.single.features, hasLength(29));
      expect(nodes.single.features[0], '助動詞');
      expect(nodes.single.features[20], 'タ');
    });

    test('parses multiple rows and skips EOS and malformed lines', () {
      final nodes = parseMecabOutput(
        '$_taLine\n$_waLine\nEOS\n\nnot-a-token\n',
      );

      expect(nodes.map((node) => node.surface).toList(), ['た', 'は']);
      expect(nodes.every((node) => node.features.length == 29), isTrue);
    });

    test('handles empty output', () {
      expect(parseMecabOutput(''), isEmpty);
      expect(parseMecabOutput('EOS'), isEmpty);
    });
  });
}
