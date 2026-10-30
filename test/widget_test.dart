import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/app.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _storageChannel = MethodChannel('rikai/storage_permission');

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'flutter.app_onboarding_completed': true,
  });
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: RikaiApp(key: UniqueKey()),
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
              'allFilesAccess': true,
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

    expect(find.text('主页'), findsOneWidget);
    expect(find.text('使用前须知'), findsOneWidget);
    expect(find.text('拍照识别'), findsOneWidget);
    expect(find.text('查句子'), findsOneWidget);
    expect(find.text('查单词'), findsOneWidget);
    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('词典助手'), findsOneWidget);
    // The usage notice sits above the action grid.
    expect(
      tester.getTopLeft(find.text('使用前须知')).dy,
      lessThan(tester.getTopLeft(find.text('拍照识别')).dy),
    );
    // Detailed intro/footer copy was removed by the UI revision.
    expect(find.textContaining('日语阅读 · 离线查词'), findsNothing);
    expect(find.textContaining('Phase 0'), findsNothing);
  });

  testWidgets('drawer switches font and opens help/copyright', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    final drawer = tester.widget<Drawer>(find.byType(Drawer));
    final drawerShape = drawer.shape as RoundedRectangleBorder;
    expect(drawerShape.borderRadius, BorderRadius.zero);
    expect(find.text('自定义字体'), findsOneWidget);
    expect(find.text('帮助'), findsOneWidget);
    expect(find.text('著作权信息'), findsOneWidget);

    await tester.tap(find.text('自定义字体'));
    await tester.pumpAndSettle();
    expect(find.text('系统默认'), findsOneWidget);
    await tester.tap(find.text('系统默认'));
    await tester.pumpAndSettle();

    final homeContext = tester.element(find.text('主页'));
    expect(
      Theme.of(homeContext).textTheme.bodyMedium?.fontFamily,
      isNot('HarmonyOS Sans SC'),
    );

    await tester.tap(find.text('帮助'));
    await tester.pumpAndSettle();
    expect(find.text('使用前须知'), findsOneWidget);
    expect(find.text('文本阅读'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('著作权信息'));
    await tester.pumpAndSettle();
    expect(find.text('第三方组件'), findsOneWidget);
  });

  testWidgets('text entry navigates to the reader and reports missing UniDic', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('查句子'));
    await tester.pumpAndSettle();
    expect(find.text('文本阅读'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);

    final readerScaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    expect(readerScaffold.backgroundColor, AppColors.surface);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.decoration?.filled, isFalse);
    final controls = tester.widget<Container>(
      find.byKey(const Key('reader-controls-surface')),
    );
    final decoration = controls.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.surface);
    expect((decoration.border! as Border).bottom.color, AppColors.divider);

    await tester.enterText(find.byType(TextField), '食べた東京');
    await tester.tap(find.text('分词'));
    await tester.pumpAndSettle();

    expect(find.text('尚未配置 UniDic'), findsOneWidget);
    expect(find.text('打开设置'), findsOneWidget);
    expect(find.byTooltip('复制全文'), findsNothing);
    expect(find.text('复制'), findsOneWidget);
  });

  testWidgets('reader draft survives leaving and reopening the page', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('查句子'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '下書きのテキスト');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('查句子'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '下書きのテキスト');
  });

  testWidgets('settings page can persist a UniDic path', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('UniDic 分词'), findsOneWidget);
    expect(find.text('校验并保存'), findsOneWidget);
    expect(find.textContaining('应用会递归查找并校验'), findsOneWidget);
    expect(find.text('应用外部私有目录'), findsOneWidget);
    expect(find.byType(Card), findsNothing);

    final mdictY = tester.getTopLeft(find.text('MDict 词典')).dy;
    final displayY = tester.getTopLeft(find.text('阅读显示')).dy;
    final unidicY = tester.getTopLeft(find.text('UniDic 分词')).dy;
    final storageY = tester.getTopLeft(find.text('存储权限')).dy;
    expect(mdictY < displayY, isTrue);
    expect(displayY < unidicY, isTrue);
    expect(unidicY < storageY, isTrue);

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

    await tester.tap(find.text('每词典词条上限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 条'));
    await tester.pumpAndSettle();
    expect(find.text('最多 5 条'), findsOneWidget);
  });

  testWidgets('search page shows the empty dictionary state', (tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('查单词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查单词'));
    await tester.pumpAndSettle();

    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.decoration?.hintText, '搜索……');
    expect(find.text('尚未添加 MDict 词典'), findsOneWidget);
    expect(find.text('管理词典'), findsOneWidget);
    expect(find.text('查询词典'), findsNothing);
    expect(find.text('多选'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });

  testWidgets('dictionary management opens from settings', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理词典'));
    await tester.pumpAndSettle();

    expect(find.text('MDict 词典'), findsOneWidget);
    expect(find.text('尚未添加词典'), findsOneWidget);
    expect(find.text('从文件夹导入'), findsOneWidget);
    expect(find.text('手动添加词典'), findsOneWidget);
  });

  testWidgets('search controls fit portrait and landscape widths', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in const [Size(360, 640), Size(800, 360)]) {
      await tester.binding.setSurfaceSize(size);
      await _pumpApp(tester);
      await tester.ensureVisible(find.text('查单词'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查单词'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('多选'), findsOneWidget);
      expect(find.text('查询词典'), findsNothing);
    }
  });

  testWidgets('reader controls fit landscape', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('查句子'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查句子'));
    await tester.pumpAndSettle();

    expect(find.text('文本阅读'), findsOneWidget);
    expect(find.text('分词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual dictionary dialog does not open the keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('管理词典'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理词典'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加词典'));
    await tester.pumpAndSettle();

    expect(find.text('添加 MDict 词典'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the max-entries dialog keeps 10 reachable in landscape', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('每词典词条上限'),
      find.byType(ListView).first,
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('每词典词条上限'));
    await tester.pumpAndSettle();

    expect(find.text('10 条'), findsOneWidget);
    await tester.ensureVisible(find.text('10 条'));
    await tester.tap(find.text('10 条'));
    await tester.pumpAndSettle();

    expect(find.text('最多 10 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
