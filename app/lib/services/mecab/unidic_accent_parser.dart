import '../../core/models/agent/agent_pitch.dart';

/// Parses UniDic 2025.12 accent fields into a display-safe pitch pattern.
///
/// `accentType` is feature 24 (`aType`): 0=flat, 1=initial-high, N=drop after
/// mora N. `reading` is the token reading (kana 20 preferred). Returns null
/// when the data is missing, non-numeric, out of range, or the reading cannot
/// be split into at least two morae. The caller must render plain text instead
/// of inventing a pitch.
AgentPitchAccent? parseUnidicAccent({
  required String accentType,
  required String reading,
}) {
  final type = int.tryParse(accentType.trim());
  if (type == null || type < 0) return null;
  final morae = splitJapaneseMorae(reading);
  if (morae.length < 2 || type > morae.length) return null;
  return AgentPitchAccent(
    accentType: type,
    moraCount: morae.length,
    moraPattern: _pattern(type, morae.length),
  );
}

/// Splits a kana reading into morae. Small ゃゅょ/ぁぃぅぇぉ attach to the
/// previous mora; っ/ん/ー count as one mora each. Non-kana characters are
/// ignored.
List<String> splitJapaneseMorae(String reading) {
  final morae = <String>[];
  for (final rune in reading.runes) {
    final char = _normalizeKana(String.fromCharCode(rune));
    if (!_isKana(char)) continue;
    if (_smallKana.contains(char) && morae.isNotEmpty) {
      morae[morae.length - 1] += char;
    } else {
      morae.add(char);
    }
  }
  return morae;
}

String _pattern(int accentType, int moraCount) {
  if (accentType == 0) {
    return 'L${'H' * (moraCount - 1)}';
  }
  if (accentType == 1) {
    return 'H${'L' * (moraCount - 1)}';
  }
  return 'L${'H' * (accentType - 1)}${'L' * (moraCount - accentType)}';
}

String _normalizeKana(String char) {
  final code = char.runes.single;
  // Katakana -> hiragana, preserving ー and other symbols.
  if (code >= 0x30A1 && code <= 0x30F6) {
    return String.fromCharCode(code - 0x60);
  }
  return char;
}

bool _isKana(String char) {
  if (char.isEmpty) return false;
  final code = char.runes.single;
  return (code >= 0x3041 && code <= 0x309F) ||
      code == 0x30FC ||
      (code >= 0x31F0 && code <= 0x31FF);
}

const String _smallKana = 'ゃゅょぁぃぅぇぉゎゕゖ';
