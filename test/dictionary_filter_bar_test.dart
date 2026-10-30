import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/lookup/dictionary_filter_bar.dart';

const _dictionaries = [
  DictionaryInfo(id: 'a', title: '大修館明鏡', mdxPath: '/a.mdx'),
  DictionaryInfo(id: 'b', title: '大辞林', mdxPath: '/b.mdx'),
  DictionaryInfo(id: 'c', title: '漢検', mdxPath: '/c.mdx'),
];

Future<void> _pump(
  WidgetTester tester, {
  required List<DictionaryInfo> dictionaries,
  required Set<String> selectedIds,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: DictionaryFilterBar(
          dictionaries: dictionaries,
          selectedIds: selectedIds,
          mode: DictionarySelectionMode.multi,
          onToggle: (_) {},
          onSelectAll: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shortens titles to the unique prefix and uses brand color', (
    tester,
  ) async {
    await _pump(
      tester,
      dictionaries: _dictionaries,
      selectedIds: const {'a', 'b', 'c'},
    );

    expect(find.text('全选'), findsOneWidget);
    expect(find.text('查询词典'), findsNothing);
    expect(find.text('大修'), findsOneWidget);
    expect(find.text('大辞'), findsOneWidget);
    expect(find.text('漢'), findsOneWidget);
    final chip = tester.widget<FilterChip>(
      find.ancestor(of: find.text('大修'), matching: find.byType(FilterChip)),
    );
    expect(chip.selectedColor, AppColors.header);
  });

  testWidgets('changing the selection does not move dictionary chips', (
    tester,
  ) async {
    final dictionaries = [
      for (var index = 0; index < 9; index++)
        DictionaryInfo(id: '$index', title: '辞$index', mdxPath: '/$index.mdx'),
    ];
    await _pump(
      tester,
      dictionaries: dictionaries,
      selectedIds: const {'0', '1', '2'},
    );
    final before = tester.getTopLeft(find.text('辞8'));

    await _pump(
      tester,
      dictionaries: dictionaries,
      selectedIds: const {'3', '4', '5'},
    );
    final after = tester.getTopLeft(find.text('辞8'));

    expect(after, before);
  });
}
