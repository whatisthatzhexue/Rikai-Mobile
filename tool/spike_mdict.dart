// Development-only spike: open a real MDX/MDD in place and measure lookup.
//
// Usage:
//   dart run tool/spike_mdict.dart "<path to .mdx>" [word]
//
// The dictionary is never copied or committed. This script only prints
// metadata and a short entry length.
import 'dart:io';

import 'package:dict_reader/dict_reader.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/spike_mdict.dart <mdx> [word]');
    exitCode = 2;
    return;
  }

  final path = args[0];
  final word = args.length > 1 ? args[1] : '東京';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('not found: $path');
    exitCode = 2;
    return;
  }

  final reader = DictReader(path);
  final sw = Stopwatch()..start();
  await reader.initDict();
  sw.stop();
  stdout.writeln('init: ${sw.elapsedMilliseconds} ms');
  stdout.writeln('entries: ${reader.numEntries}');
  stdout.writeln('header.title: ${reader.header['Title']}');
  stdout.writeln('header.encoding: ${reader.header['Encoding']}');
  stdout.writeln('header.version: ${reader.header['GeneratedByEngineVersion']}');
  stdout.writeln('rss: ${ProcessInfo.currentRss ~/ (1024 * 1024)} MB');

  final lookup = Stopwatch()..start();
  final hits = await reader.locateAll(word);
  lookup.stop();
  stdout.writeln('locateAll("$word"): ${hits.length} hit(s) in '
      '${lookup.elapsedMicroseconds / 1000} ms');

  for (final hit in hits.take(3)) {
    final resolved = await _resolve(reader, hit);
    final html = resolved.html;
    final text = html.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    stdout.writeln('  entry ${hit.keyText} -> ${resolved.key} '
        'chars=${html.length} '
        'text="${text.length > 100 ? text.substring(0, 100) : text}"');
  }

  final suggestions = reader.search(word, limit: 10);
  stdout.writeln('prefix suggestions: $suggestions');

  final lower = word.toLowerCase();
  if (lower != word) {
    stdout.writeln('normalized lookup("$lower"): '
        '${await reader.locateAll(lower)}');
  }

  await reader.close();
}

Future<({String key, String html})> _resolve(
  DictReader reader,
  RecordOffsetInfo hit, [
  int depth = 0,
]) async {
  final html = await reader.readOneMdx(hit);
  final redirect = RegExp(r'^@@@LINK=(.+)$').firstMatch(html.trim());
  if (redirect != null && depth < 3) {
    final target = redirect.group(1)!;
    final next = await reader.locate(target);
    if (next != null) {
      return _resolve(reader, next, depth + 1);
    }
  }
  return (key: hit.keyText, html: html);
}
