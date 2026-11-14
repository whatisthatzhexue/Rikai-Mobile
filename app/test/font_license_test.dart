import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/theme/font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled Kiyosuna Sans OFL text is registered', () async {
    registerBundledFontLicenses();

    final matches = await LicenseRegistry.licenses
        .where((entry) => entry.packages.contains('Kiyosuna Sans'))
        .toList();
    expect(matches, isNotEmpty);

    final text = matches.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL OPEN FONT LICENSE'));
    expect(text, contains('WATANABE Reiya'));
    expect(text, contains('KT Kiyosuna Sans'));
  });
}
