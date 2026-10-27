import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/app.dart';

void main() {
  testWidgets('home page shows the main entry points', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RikaiApp()));

    expect(find.text('Rikai'), findsOneWidget);
    expect(find.text('拍照识别'), findsOneWidget);
    expect(find.text('输入文本'), findsOneWidget);
    expect(find.text('查词'), findsOneWidget);
    expect(find.text('语料'), findsOneWidget);
  });
}
