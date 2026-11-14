/// Katakana <-> hiragana helpers used for furigana and dictionary lookup.
library;

const int _katakanaA = 0x30A1; // ァ
const int _katakanaRo = 0x30F6; // ヶ
const int _hiraganaA = 0x3041; // ぁ

/// Converts full-width katakana to hiragana.
///
/// Prolonged sound marks (ー), middle dots (・), and already-hiragana text are
/// preserved. The four rare wa/wi/we/wo katakana and the iteration marks are
/// mapped explicitly because they have no contiguous Unicode hiragana block.
String katakanaToHiragana(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= _katakanaA && rune <= _katakanaRo) {
      buffer.writeCharCode(rune - 0x60);
      continue;
    }
    switch (rune) {
      case 0x30F7: // ヷ
        buffer.write('わ');
        break;
      case 0x30F8: // ヸ
        buffer.write('ゐ');
        break;
      case 0x30F9: // ヹ
        buffer.write('ゑ');
        break;
      case 0x30FA: // ヺ
        buffer.write('を');
        break;
      case 0x30FD: // ヽ
        buffer.write('ゝ');
        break;
      case 0x30FE: // ヾ
        buffer.write('ゞ');
        break;
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Converts hiragana to katakana. Used for lookup variants.
String hiraganaToKatakana(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= _hiraganaA && rune <= 0x3096) {
      buffer.writeCharCode(rune + 0x60);
      continue;
    }
    switch (rune) {
      case 0x309D: // ゝ
        buffer.write('ヽ');
        break;
      case 0x309E: // ゞ
        buffer.write('ヾ');
        break;
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// True when [input] contains at least one hiragana or katakana character.
bool containsKana(String input) {
  for (final rune in input.runes) {
    if (rune >= 0x3041 && rune <= 0x3096) return true;
    if (rune >= 0x30A1 && rune <= 0x30FA) return true;
  }
  return false;
}
