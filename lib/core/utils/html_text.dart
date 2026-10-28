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
