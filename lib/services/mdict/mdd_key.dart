/// Candidate MDD resource keys for an HTML `src`/CSS `url(...)` reference.
///
/// MDict MDD keys normally look like `\JC_Z24Z\A471.png` while entries refer to
/// them as `JC_Z24Z/A471.png` or `3913.png`. The worker tries these variants
/// with `DictReader.locate`.
library;

List<String> mddKeyCandidates(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];

  var decoded = trimmed;
  try {
    decoded = Uri.decodeFull(trimmed);
  } catch (_) {
    // Keep the undecoded value; some dictionaries contain literal '%'.
  }

  var value = decoded;
  for (final prefix in ['file://', 'file:']) {
    if (value.toLowerCase().startsWith(prefix)) {
      value = value.substring(prefix.length);
      break;
    }
  }
  value = value.split('#').first.split('?').first;
  while (value.startsWith('/') || value.startsWith(r'\')) {
    value = value.substring(1);
  }

  final windowsForm = '\\${value.replaceAll('/', r'\')}';
  final slashForm = value.replaceAll(r'\', '/');

  final candidates = <String>{
    trimmed,
    decoded,
    value,
    windowsForm,
    slashForm,
    windowsForm.toLowerCase(),
    windowsForm.toUpperCase(),
    slashForm.toLowerCase(),
  };
  candidates.removeWhere((candidate) => candidate.isEmpty);
  return candidates.toList(growable: false);
}
