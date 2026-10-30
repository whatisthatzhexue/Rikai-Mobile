import 'package:html/parser.dart' as html_parser;

/// Extracts readable text from a dictionary HTML fragment.
String htmlToPlainText(String html, {int maxLength = 0}) {
  final fragment = html_parser.parseFragment(html);
  final text = (fragment.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (maxLength > 0 && text.length > maxLength) {
    return '${text.substring(0, maxLength)}…';
  }
  return text;
}

/// Cleans dictionary text before it is shown to the user or sent to the model.
///
/// Removes replacement/control/private-use characters and debug prefixes that
/// some dictionaries include, collapses whitespace, and applies a hard cap.
String cleanDictionaryText(String text, {int maxLength = 400}) {
  var cleaned = text
      .replaceAll(
        RegExp(
          r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F'
          r'-�]',
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.startsWith('Instance of ') || cleaned.startsWith('Exception ')) {
    cleaned = '';
  }
  if (maxLength > 0 && cleaned.length > maxLength) {
    cleaned = '${cleaned.substring(0, maxLength)}…';
  }
  return cleaned;
}
