import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/theme/app_branding.dart';

void main() {
  test('Simplified Chinese uses 释书糖, other languages use LexiCandy', () {
    expect(AppBranding.nameForLocale(const Locale('zh', 'CN')), '释书糖');
    expect(AppBranding.nameForLocale(const Locale('zh')), '释书糖');
    expect(AppBranding.nameForLocale(const Locale('zh', 'SG')), '释书糖');
    expect(AppBranding.nameForLocale(const Locale('zh', 'TW')), 'LexiCandy');
    expect(AppBranding.nameForLocale(const Locale('zh', 'HK')), 'LexiCandy');
    expect(
      AppBranding.nameForLocale(
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'CN',
        ),
      ),
      'LexiCandy',
    );
    expect(AppBranding.nameForLocale(const Locale('en', 'US')), 'LexiCandy');
    expect(AppBranding.nameForLocale(const Locale('ja')), 'LexiCandy');
  });
}
