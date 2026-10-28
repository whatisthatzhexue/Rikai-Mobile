import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/theme/app_fonts.dart';
import 'package:rikai_mobile/services/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults use HarmonyOS and unlimited dictionary entries', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    final settings = SettingsStore(preferences).load();

    expect(settings.fontFamily, AppFonts.harmony);
    expect(settings.maxEntriesPerDictionary, 0);
    expect(settings.showFurigana, isTrue);
    expect(settings.readerFontSize, 20);
    expect(settings.ocrMirror, '');
  });

  test('persists font family and entry limit', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SettingsStore(preferences);

    await store.save(
      const AppSettings(
        fontFamily: AppFonts.system,
        maxEntriesPerDictionary: 5,
        ocrMirror: 'https://mirror.example',
      ),
    );
    final restored = SettingsStore(preferences).load();

    expect(restored.fontFamily, AppFonts.system);
    expect(restored.maxEntriesPerDictionary, 5);
    expect(restored.ocrMirror, 'https://mirror.example');
  });

  test('sanitizes unknown font and negative limits', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.app_font_family': 'Unknown Font',
      'flutter.mdict_max_entries_per_dictionary': -2,
    });
    final preferences = await SharedPreferences.getInstance();

    final restored = SettingsStore(preferences).load();

    expect(restored.fontFamily, AppFonts.harmony);
    expect(restored.maxEntriesPerDictionary, 0);
  });
}
