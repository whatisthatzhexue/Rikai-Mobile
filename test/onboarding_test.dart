import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/app.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _storageChannel = MethodChannel('rikai/storage_permission');

Future<void> _pumpApp(WidgetTester tester, {required bool completed}) async {
  SharedPreferences.setMockInitialValues({
    'flutter.app_onboarding_completed': completed,
  });
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
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('first launch guides setup and requires acknowledgement', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpApp(tester, completed: false);

    expect(find.text('欢迎使用 Rikai'), findsOneWidget);
    expect(find.text('准备清单'), findsOneWidget);
    expect(find.text('UniDic 分词词典'), findsOneWidget);

    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始使用'),
    );
    expect(start.onPressed, isNull);

    await tester.tap(find.text('我已阅读并理解上述边界与许可说明'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开始使用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();

    expect(find.text('主页'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('app_onboarding_completed'), isTrue);
  });

  testWidgets('onboarding fits a narrow portrait screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpApp(tester, completed: false);

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('开始使用'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('开始使用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skipping onboarding goes straight to the home page', (
    tester,
  ) async {
    await _pumpApp(tester, completed: false);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(find.text('主页'), findsOneWidget);
  });
}
