/// Coarse script-based source-language hint.
///
/// This is intentionally not a full language classifier. It lets the evidence
/// builder skip UniDic for clearly non-Japanese scripts (Latin, Hangul,
/// Cyrillic, Thai, Arabic, Greek) without pretending to support those
/// languages. Han-only text is ambiguous between Chinese and kanji-only
/// Japanese; the app keeps the Japanese tokenizer for that case.
enum ScriptLanguage {
  japanese('ja'),
  latin('latin'),
  korean('ko'),
  cyrillic('cyrillic'),
  thai('th'),
  arabic('ar'),
  greek('el');

  const ScriptLanguage(this.wireName);

  final String wireName;
}

ScriptLanguage? detectScriptLanguage(String text) {
  var han = 0;
  var hiragana = 0;
  var katakana = 0;
  var latin = 0;
  var hangul = 0;
  var cyrillic = 0;
  var greek = 0;
  var thai = 0;
  var arabic = 0;

  for (final rune in text.runes) {
    if (rune >= 0x3040 && rune <= 0x309F) {
      hiragana++;
    } else if ((rune >= 0x30A0 && rune <= 0x30FF) ||
        (rune >= 0x31F0 && rune <= 0x31FF) ||
        (rune >= 0xFF66 && rune <= 0xFF9F)) {
      katakana++;
    } else if ((rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x20000 && rune <= 0x2FA1F)) {
      han++;
    } else if ((rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x3130 && rune <= 0x318F) ||
        (rune >= 0xAC00 && rune <= 0xD7AF)) {
      hangul++;
    } else if ((rune >= 0x0400 && rune <= 0x052F)) {
      cyrillic++;
    } else if ((rune >= 0x0370 && rune <= 0x03FF) ||
        (rune >= 0x1F00 && rune <= 0x1FFF)) {
      greek++;
    } else if (rune >= 0x0E00 && rune <= 0x0E7F) {
      thai++;
    } else if ((rune >= 0x0600 && rune <= 0x06FF) ||
        (rune >= 0x0750 && rune <= 0x077F) ||
        (rune >= 0x08A0 && rune <= 0x08FF)) {
      arabic++;
    } else if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A) ||
        (rune >= 0x00C0 && rune <= 0x024F) ||
        (rune >= 0x1E00 && rune <= 0x1EFF)) {
      latin++;
    }
  }

  if (hiragana + katakana > 0) return ScriptLanguage.japanese;
  if (hangul > 0) return ScriptLanguage.korean;
  if (cyrillic > 0) return ScriptLanguage.cyrillic;
  if (thai > 0) return ScriptLanguage.thai;
  if (arabic > 0) return ScriptLanguage.arabic;
  if (greek > 0) return ScriptLanguage.greek;
  if (latin > 0 && han == 0) return ScriptLanguage.latin;
  // Han-only or Han-dominant text without kana is ambiguous. Keep the
  // Japanese tokenizer for the app's primary reading use case.
  return null;
}

/// Whether the local UniDic tokenizer should be attempted for [text].
bool shouldUseJapaneseTokenizer(String text) {
  final language = detectScriptLanguage(text);
  return language == null || language == ScriptLanguage.japanese;
}

/// Han-only text is ambiguous between Chinese and kanji-only Japanese.
///
/// The app keeps the Japanese tokenizer for its primary use case, but callers
/// must tell the model that UniDic readings/structure are not certain.
bool isHanOnlyAmbiguous(String text) {
  var han = 0;
  var otherLetters = 0;
  for (final rune in text.runes) {
    final isHan =
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x20000 && rune <= 0x2FA1F);
    if (isHan) {
      han++;
      continue;
    }
    final isOtherLetter =
        (rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0x31F0 && rune <= 0x31FF) ||
        (rune >= 0xFF66 && rune <= 0xFF9F) ||
        (rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x3130 && rune <= 0x318F) ||
        (rune >= 0xAC00 && rune <= 0xD7AF) ||
        (rune >= 0x0400 && rune <= 0x052F) ||
        (rune >= 0x0370 && rune <= 0x03FF) ||
        (rune >= 0x1F00 && rune <= 0x1FFF) ||
        (rune >= 0x0E00 && rune <= 0x0E7F) ||
        (rune >= 0x0600 && rune <= 0x06FF) ||
        (rune >= 0x0750 && rune <= 0x077F) ||
        (rune >= 0x08A0 && rune <= 0x08FF) ||
        (rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A) ||
        (rune >= 0x00C0 && rune <= 0x024F) ||
        (rune >= 0x1E00 && rune <= 0x1EFF);
    if (isOtherLetter) otherLetters++;
  }
  return han > 0 && otherLetters == 0;
}
