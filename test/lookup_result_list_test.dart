import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/lookup_models.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/lookup/lookup_result_list.dart';

const DictionaryInfo _dictionary = DictionaryInfo(
  id: 'dict',
  title: 'Test Dictionary',
  mdxPath: '/tmp/test.mdx',
);

const LookupEntry _alpha = LookupEntry(
  matchedKey: 'Alpha',
  headword: 'Alpha',
  html: '<div>first definition</div>',
);

const LookupEntry _beta = LookupEntry(
  matchedKey: 'Beta',
  headword: 'Beta',
  html: '<div>second definition</div>',
);

void main() {
  testWidgets('a single result tap opens only that entry', (tester) async {
    LookupEntry? opened;
    DictionaryLookupGroup? openedAll;
    const group = DictionaryLookupGroup(
      dictionary: _dictionary,
      entries: [_alpha, _beta],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: LookupHitList(
            groups: const [group],
            onOpenEntry: (_, entry) => opened = entry,
            onOpenAll: (group) => openedAll = group,
          ),
        ),
      ),
    );

    expect(find.text('查看全部（2 条）'), findsOneWidget);

    final nameText = tester.widget<Text>(find.text('Test Dictionary'));
    final countText = tester.widget<Text>(find.text('2 条'));
    expect(nameText.style?.fontSize, 16);
    expect(countText.style?.fontSize, 16);
    expect(countText.style?.color, nameText.style?.color);
    final entryText = tester.widget<Text>(find.text('Alpha'));
    expect(entryText.style?.fontSize, 24);

    await tester.tap(find.text('Alpha'));
    expect(opened, _alpha);
    expect(openedAll, isNull);

    await tester.tap(find.text('查看全部（2 条）'));
    expect(openedAll, group);
  });

  testWidgets('uses the matched word instead of an internal redirect id', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: LookupHitList(
            groups: const [
              DictionaryLookupGroup(
                dictionary: _dictionary,
                entries: [
                  LookupEntry(
                    matchedKey: '愛',
                    headword: '00044',
                    html: '<div>definition</div>',
                  ),
                ],
              ),
            ],
            onOpenEntry: (_, _) {},
            onOpenAll: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('愛'), findsOneWidget);
    expect(find.text('00044'), findsNothing);
  });

  testWidgets('a single-entry group has no 查看全部 button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: LookupHitList(
            groups: const [
              DictionaryLookupGroup(dictionary: _dictionary, entries: [_alpha]),
            ],
            onOpenEntry: (_, _) {},
            onOpenAll: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('查看全部'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });
}
