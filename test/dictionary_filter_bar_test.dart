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

void main() {
  testWidgets('shortens titles to the unique prefix and uses brand color', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DictionaryFilterBar(
            dictionaries: _dictionaries,
            selectedIds: const {'a', 'b', 'c'},
            mode: DictionarySelectionMode.multi,
            onToggle: (_) {},
            onSelectAll: () {},
            onModeChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('全选'), findsOneWidget);
    expect(find.text('大修'), findsOneWidget);
    expect(find.text('大辞'), findsOneWidget);
    expect(find.text('漢'), findsOneWidget);
    final chip = tester.widget<FilterChip>(
      find.ancestor(of: find.text('大修'), matching: find.byType(FilterChip)),
    );
    expect(chip.selectedColor, AppColors.header);
  });
}
