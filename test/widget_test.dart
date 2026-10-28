import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/app.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _storageChannel = MethodChannel('rikai/storage_permission');

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const RikaiApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (call) async {
          if (call.method == 'getStorageAccessStatus') {
            return <String, Object?>{
              'sdkInt': 33,
              'allFilesAccess': false,
              'legacyRead': false,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, null);
  });

  testWidgets('home page shows the main entry points', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Rikai'), findsOneWidget);
    expect(find.text('拍照识别'), findsOneWidget);
    expect(find.text('输入文本'), findsOneWidget);
    expect(find.text('查词'), findsOneWidget);
    expect(find.text('语料'), findsOneWidget);
  });

  testWidgets('text entry navigates to the reader and reports missing UniDic', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('输入文本'));
    await tester.pumpAndSettle();
    expect(find.text('文本阅读'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '食べた東京');
    await tester.tap(find.text('分词'));
    await tester.pumpAndSettle();

    expect(find.text('尚未配置 UniDic'), findsOneWidget);
    expect(find.text('打开设置'), findsOneWidget);
  });

  testWidgets('settings page can persist a UniDic path', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('UniDic'), findsOneWidget);
    expect(find.text('校验并保存'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      '/sdcard/Download/unidic-cwj-202512',
    );
    await tester.tap(find.text('校验并保存'));
    await tester.pump();
    // The validator performs real file-system I/O; give it a real event-loop
    // turn before pumping the resulting UI.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('校验失败'), findsOneWidget);
    expect(
      find.textContaining('/sdcard/Download/unidic-cwj-202512'),
      findsWidgets,
    );
  });

  testWidgets('search page shows the empty dictionary state', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('查词'));
    await tester.pumpAndSettle();

    expect(find.text('尚未添加 MDict 词典'), findsOneWidget);
    expect(find.text('管理词典'), findsOneWidget);
  });

  testWidgets('dictionary management opens from settings', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理词典'));
    await tester.pumpAndSettle();

    expect(find.text('MDict 词典'), findsOneWidget);
    expect(find.text('尚未添加词典'), findsOneWidget);
    expect(find.text('添加词典'), findsOneWidget);
  });
}
