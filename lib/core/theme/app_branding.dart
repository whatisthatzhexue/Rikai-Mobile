import 'package:flutter/widgets.dart';

/// Product display name. Simplified Chinese systems show 释书糖; other
/// languages use LexiCandy. The Android launcher label is localized separately
/// in `android/app/src/main/res/values-zh/strings.xml`.
abstract final class AppBranding {
  static const String englishName = 'LexiCandy';
  static const String chineseName = '释书糖';

  static String nameForLocale(Locale locale) =>
      _isSimplifiedChinese(locale) ? chineseName : englishName;

  static bool _isSimplifiedChinese(Locale locale) {
    if (locale.languageCode != 'zh') return false;
    if (locale.scriptCode == 'Hant') return false;
    if (locale.scriptCode == 'Hans') return true;
    const simplifiedCountries = <String>{'CN', 'SG', 'MY'};
    final country = locale.countryCode;
    if (country != null) return simplifiedCountries.contains(country);
    return true;
  }

  static String get name => nameForLocale(
    WidgetsBinding.instance.platformDispatcher.locale,
  );
}
