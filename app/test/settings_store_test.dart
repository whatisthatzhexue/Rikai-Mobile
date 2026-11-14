import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/lookup_match_mode.dart';
import 'package:lexicandy/core/theme/app_fonts.dart';
import 'package:lexicandy/services/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults use Kiyosuna and unlimited dictionary entries', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    final settings = SettingsStore(preferences).load();

    expect(settings.fontFamily, AppFonts.kiyosuna);
    expect(settings.maxEntriesPerDictionary, 0);
    expect(settings.lookupMatchMode, LookupMatchMode.exact);
    expect(settings.showFurigana, isTrue);
    expect(settings.annotationRuleSetId, 'furigana');
    expect(settings.readerFontSize, 20);
    expect(settings.ocrMirror, '');
    expect(settings.ocrModelsDirectory, '');
    expect(settings.onboardingCompleted, isFalse);
    expect(settings.autoSaveOcr, isFalse);
    expect(settings.agentProfilesAutoAccept, isFalse);
  });

  test('persists font family and entry limit', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SettingsStore(preferences);

    await store.save(
      const AppSettings(
        fontFamily: AppFonts.system,
        maxEntriesPerDictionary: 5,
        lookupMatchMode: LookupMatchMode.prefix,
        ocrMirror: 'https://mirror.example',
        ocrModelsDirectory: '/storage/emulated/0/rikai-models',
        onboardingCompleted: true,
        autoSaveOcr: true,
        agentProfilesAutoAccept: true,
        annotationRuleSetId: 'furigana_pitch',
      ),
    );
    final restored = SettingsStore(preferences).load();

    expect(restored.annotationRuleSetId, 'furigana_pitch');
    expect(restored.fontFamily, AppFonts.system);
    expect(restored.maxEntriesPerDictionary, 5);
    expect(restored.lookupMatchMode, LookupMatchMode.prefix);
    expect(restored.ocrMirror, 'https://mirror.example');
    expect(restored.ocrModelsDirectory, '/storage/emulated/0/rikai-models');
    expect(restored.onboardingCompleted, isTrue);
    expect(restored.autoSaveOcr, isTrue);
    expect(restored.agentProfilesAutoAccept, isTrue);
  });

  test('an existing UniDic path counts as completed onboarding', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.unidic_path': '/sdcard/Download/unidic-cwj-202512',
    });
    final preferences = await SharedPreferences.getInstance();

    final settings = SettingsStore(preferences).load();

    expect(settings.onboardingCompleted, isTrue);
  });

  test('sanitizes unknown font and negative limits', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.app_font_family': 'Unknown Font',
      'flutter.mdict_max_entries_per_dictionary': -2,
    });
    final preferences = await SharedPreferences.getInstance();

    final restored = SettingsStore(preferences).load();

    expect(restored.fontFamily, AppFonts.kiyosuna);
    expect(restored.maxEntriesPerDictionary, 0);
  });

  test('legacy HarmonyOS font preference falls back to Kiyosuna', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.app_font_family': 'HarmonyOS Sans SC',
    });
    final preferences = await SharedPreferences.getInstance();

    final restored = SettingsStore(preferences).load();

    expect(restored.fontFamily, AppFonts.kiyosuna);
  });
}
