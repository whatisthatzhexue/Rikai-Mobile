import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/features/agent/familiarization_sheet.dart';
import 'package:rikai_mobile/services/agent/agent_ui_strings.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_familiarization_service.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_profile_markdown.dart';

const _profile = DictionaryProfile(
  dictionaryId: 'dict-a',
  title: 'A',
  kind: '国語辞典',
  entryStructure: DictionaryEntryStructure(),
  searchBehavior: DictionarySearchBehavior(),
  language: 'zh',
);

void main() {
  testWidgets('the user can add a language pair before saving', (tester) async {
    final strings = AgentUiStrings.of(AgentUiLanguage.chinese);
    ProfileConfirmation? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showFamiliarizationSheet(
                  context,
                  profile: _profile,
                  markdown: profileToMarkdown(_profile),
                  strings: strings,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('语言对'), findsOneWidget);
    expect(find.text('未识别到语言对'), findsOneWidget);

    await tester.tap(find.byTooltip('添加语言对'));
    await tester.pump();
    expect(find.text('日语 → 中文'), findsOneWidget);

    await tester.ensureVisible(find.text('保存并信任'));
    await tester.tap(find.text('保存并信任'));
    await tester.pumpAndSettle();

    expect(result?.action, ProfileConfirmationAction.save);
    expect(result?.profile?.languagePairs.single.label, 'ja→zh');
    expect(result?.markdown, contains('- 语言: ja→zh'));
  });

  testWidgets('profile preview shows unsafe syntax as plain text', (
    tester,
  ) async {
    final strings = AgentUiStrings.of(AgentUiLanguage.chinese);
    const markdown =
        '# 词典档案\n'
        '**要点**\n'
        '- 列表\n'
        '<script>alert(1)</script>\n'
        '[链接](http://example.com)';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFamiliarizationSheet(
                context,
                profile: _profile,
                markdown: markdown,
                strings: strings,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('agent-profile-preview-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('修改'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.textContaining('<script>alert(1)</script>', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('[链接](http://example.com)', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('profile preview remains scrollable in portrait', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final strings = AgentUiStrings.of(AgentUiLanguage.chinese);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFamiliarizationSheet(
                context,
                profile: _profile,
                markdown: profileToMarkdown(_profile),
                strings: strings,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('agent-profile-preview-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('修改'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a detected pair updates the saved markdown', (
    tester,
  ) async {
    const profile = DictionaryProfile(
      dictionaryId: 'dict-a',
      title: 'A',
      kind: '国語辞典',
      entryStructure: DictionaryEntryStructure(),
      searchBehavior: DictionarySearchBehavior(),
      languagePairs: <DictionaryLanguagePair>[
        DictionaryLanguagePair(source: 'ja', target: 'ja', confidence: 0.7),
      ],
      language: 'zh',
    );
    final strings = AgentUiStrings.of(AgentUiLanguage.chinese);
    ProfileConfirmation? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showFamiliarizationSheet(
                  context,
                  profile: profile,
                  markdown: profileToMarkdown(profile),
                  strings: strings,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('日语 → 日语'), findsOneWidget);
    await tester.tap(find.byTooltip('删除'));
    await tester.pump();
    expect(find.text('日语 → 日语'), findsNothing);

    await tester.ensureVisible(find.text('保存并信任'));
    await tester.tap(find.text('保存并信任'));
    await tester.pumpAndSettle();

    expect(result?.profile?.languagePairs, isEmpty);
    expect(result?.markdown, isNot(contains('ja→ja')));
  });
}
