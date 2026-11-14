import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/models/dict_info.dart';
import '../../core/models/lookup_models.dart';

typedef MdictResourceLoader = Future<Uint8List?> Function(String key);

/// HTML + base URL ready for an offline WebView.
class RenderedEntry {
  const RenderedEntry({required this.html, required this.baseUrl});

  final String html;
  final String baseUrl;
}

/// Cleans MDict HTML, injects CSS and rewrites MDD resources to local files.
///
/// The renderer never allows scripts, inline event handlers or network URLs.
/// MDD images are written to a cache directory shared by the dictionary id.
class EntryRenderer {
  EntryRenderer({
    required Directory cacheDirectory,
    required MdictResourceLoader resourceLoader,
  }) : _cacheDirectory = cacheDirectory,
       _resourceLoader = resourceLoader;

  static const String _transparentPixel =
      'data:image/png;base64,'
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4'
      '2mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

  static final RegExp _cssUrlPattern = RegExp(
    r'''url\(\s*(['"]?)(.*?)\1\s*\)''',
    caseSensitive: false,
  );
  static final RegExp _cssImportPattern = RegExp(
    r'@import[^;]+;',
    caseSensitive: false,
  );
  static final RegExp _audioExtensionPattern = RegExp(
    r'\.(?:mp3|wav|ogg|oga|m4a|aac|flac|opus|spx|webm)(?:[?#].*)?$',
    caseSensitive: false,
  );

  final Directory _cacheDirectory;
  final MdictResourceLoader _resourceLoader;

  Future<RenderedEntry> render({
    required DictionaryInfo dictionary,
    required List<LookupEntry> entries,
    String extraCss = '',
  }) async {
    final dictionaryDirectory = Directory(
      '${_cacheDirectory.path}/${dictionary.id}',
    );
    await dictionaryDirectory.create(recursive: true);

    final resourceCache = <String, Future<String?>>{};
    final dictionaryCss = await _loadDictionaryCss(
      dictionary,
      dictionaryDirectory,
      resourceCache,
    );

    final body = StringBuffer();
    var first = true;
    for (final entry in entries) {
      if (!first) body.write('<hr class="rikai-entry-divider">');
      first = false;
      final fragment = html_parser.parseFragment(entry.html);
      _sanitize(fragment);
      await _rewriteResources(fragment, dictionaryDirectory, resourceCache);
      body.write(fragment.outerHtml);
    }

    final html = _document(body.toString(), dictionaryCss, extraCss);
    final baseUrl = Uri.directory(dictionaryDirectory.path).toString();
    return RenderedEntry(html: html, baseUrl: baseUrl);
  }

  Future<String> _loadDictionaryCss(
    DictionaryInfo dictionary,
    Directory dictionaryDirectory,
    Map<String, Future<String?>> resourceCache,
  ) async {
    final buffer = StringBuffer();
    for (final path in dictionary.cssPaths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        var css = await file.readAsString();
        css = _stripCssImports(css);
        css = await _rewriteCssUrls(css, dictionaryDirectory, resourceCache);
        buffer.writeln(css);
      } catch (error) {
        debugPrint('[EntryRenderer] failed to read CSS $path: $error');
      }
    }
    return buffer.toString();
  }

  String _stripCssImports(String css) {
    return _stripStyleClose(css.replaceAll(_cssImportPattern, ''));
  }

  Future<String> _rewriteCssUrls(
    String css,
    Directory dictionaryDirectory,
    Map<String, Future<String?>> resourceCache,
  ) async {
    final matches = _cssUrlPattern.allMatches(css).toList();
    if (matches.isEmpty) return css;

    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in matches) {
      buffer.write(css.substring(cursor, match.start));
      cursor = match.end;
      final rawValue = (match.group(2) ?? '').trim();
      if (rawValue.isEmpty) {
        buffer.write(match.group(0));
        continue;
      }
      if (_isNetworkUrl(rawValue)) {
        buffer.write('url($_transparentPixel)');
        continue;
      }
      if (_isInlineUrl(rawValue)) {
        buffer.write(match.group(0));
        continue;
      }
      final fileUrl = await _resolveResource(
        rawValue,
        dictionaryDirectory,
        resourceCache,
      );
      buffer.write(
        fileUrl == null ? 'url($_transparentPixel)' : 'url("$fileUrl")',
      );
    }
    buffer.write(css.substring(cursor));
    return buffer.toString();
  }

  void _sanitize(dom.DocumentFragment fragment) {
    for (final element in fragment.querySelectorAll(
      'script, iframe, object, embed, form, link, meta, base, noscript',
    )) {
      element.remove();
    }
    for (final comment in fragment.nodes.whereType<dom.Comment>().toList()) {
      comment.remove();
    }

    for (final element in fragment.querySelectorAll('*')) {
      final attributes = element.attributes;
      for (final key in attributes.keys.toList()) {
        final name = key.toString().toLowerCase();
        final value = attributes[key] ?? '';
        if (name.startsWith('on') ||
            name == 'srcdoc' ||
            name == 'formaction' ||
            name == 'srcset') {
          attributes.remove(key);
          continue;
        }
        if (name == 'style' &&
            (value.toLowerCase().contains('expression(') ||
                _looksLikeScriptUrl(value))) {
          attributes.remove(key);
          continue;
        }
        if ((name == 'href' ||
                name == 'src' ||
                name == 'action' ||
                name == 'xlink:href') &&
            _looksLikeScriptUrl(value)) {
          attributes.remove(key);
          continue;
        }
        // `sound://` hrefs are rewritten into local <audio> controls below;
        // they must survive sanitisation so the MDD resource can be resolved.
      }
    }
  }

  Future<void> _rewriteResources(
    dom.DocumentFragment fragment,
    Directory dictionaryDirectory,
    Map<String, Future<String?>> resourceCache,
  ) async {
    for (final element in fragment.querySelectorAll('[src]')) {
      final rawSource = (element.attributes['src'] ?? '').trim();
      if (rawSource.isEmpty) continue;

      if (rawSource.startsWith('data:')) continue;
      if (_isNetworkUrl(rawSource)) {
        element.attributes['src'] = _transparentPixel;
        element.attributes['data-rikai-blocked'] = 'true';
        element.attributes['class'] = [
          element.attributes['class'],
          'rikai-blocked-resource',
        ].whereType<String>().join(' ');
        continue;
      }

      final fileUrl = await _resolveResource(
        rawSource,
        dictionaryDirectory,
        resourceCache,
      );
      if (fileUrl == null) {
        element.attributes['src'] = _transparentPixel;
        element.attributes['data-rikai-missing'] = rawSource;
        element.attributes['class'] = [
          element.attributes['class'],
          'rikai-missing-resource',
        ].whereType<String>().join(' ');
        final alt = element.attributes['alt'];
        if (alt == null || alt.isEmpty) {
          element.attributes['alt'] = '[图片缺失]';
        }
      } else {
        element.attributes['src'] = fileUrl;
      }
    }

    for (final element in fragment.querySelectorAll('[style]')) {
      final style = element.attributes['style'];
      if (style == null || !style.contains('url(')) continue;
      element.attributes['style'] = await _rewriteCssUrls(
        style,
        dictionaryDirectory,
        resourceCache,
      );
    }

    // Many Japanese dictionaries store pronunciation files in the MDD and
    // reference them as `sound://path.mp3`. JavaScript is disabled, so instead
    // of trying to call a dictionary player we turn the link into a native
    // HTML audio control backed by the extracted local file.
    for (final anchor in fragment.querySelectorAll('a[href]')) {
      final rawHref = (anchor.attributes['href'] ?? '').trim();
      if (!_isAudioReference(rawHref)) continue;
      // Do not leave a sound:// or '#' navigation target behind; the native
      // audio control is the only playback surface.
      anchor.attributes.remove('href');
      if (anchor.attributes['data-rikai-audio'] == 'true') continue;
      anchor.attributes['data-rikai-audio'] = 'true';

      final fileUrl = await _resolveResource(
        _audioResourceKey(rawHref),
        dictionaryDirectory,
        resourceCache,
      );
      if (fileUrl == null) {
        anchor.attributes['data-rikai-missing-audio'] = rawHref;
        continue;
      }
      final audio = dom.Element.tag('audio')
        ..attributes['controls'] = ''
        ..attributes['preload'] = 'none'
        ..attributes['src'] = fileUrl
        ..attributes['class'] = 'rikai-audio';
      final parent = anchor.parent;
      if (parent == null) continue;
      final index = parent.nodes.indexOf(anchor);
      if (index >= 0) parent.nodes.insert(index + 1, audio);
    }
  }

  static bool _isAudioReference(String raw) {
    final lower = raw.trim().toLowerCase();
    if (lower.startsWith('sound://')) return true;
    if (lower.startsWith('entry://') ||
        lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('//')) {
      return false;
    }
    return _audioExtensionPattern.hasMatch(lower);
  }

  static String _audioResourceKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.toLowerCase().startsWith('sound://')) {
      return trimmed.substring('sound://'.length);
    }
    return trimmed;
  }

  Future<String?> _resolveResource(
    String rawKey,
    Directory dictionaryDirectory,
    Map<String, Future<String?>> resourceCache,
  ) {
    final cached = resourceCache[rawKey];
    if (cached != null) return cached;

    final future = () async {
      try {
        final bytes = await _resourceLoader(rawKey);
        if (bytes == null || bytes.isEmpty) return null;
        final file = File(
          '${dictionaryDirectory.path}/${_cacheFileName(rawKey)}',
        );
        final exists = await file.exists();
        if (!exists || await file.length() != bytes.length) {
          await file.writeAsBytes(bytes, flush: false);
        }
        return Uri.file(file.path).toString();
      } catch (error) {
        debugPrint('[EntryRenderer] failed to load resource $rawKey: $error');
        return null;
      }
    }();

    resourceCache[rawKey] = future;
    return future;
  }

  static String _cacheFileName(String key) {
    final digest = sha1.convert(utf8.encode(key)).toString();
    var extension = '';
    final dot = key.lastIndexOf('.');
    if (dot >= 0 && dot < key.length - 1) {
      final raw = key.substring(dot + 1);
      if (raw.length <= 8 && RegExp(r'^[A-Za-z0-9]+$').hasMatch(raw)) {
        extension = '.${raw.toLowerCase()}';
      }
    }
    return '$digest$extension';
  }

  static bool _isNetworkUrl(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('//');
  }

  static bool _isInlineUrl(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('data:') ||
        lower.startsWith('about:') ||
        lower.startsWith('blob:') ||
        lower.startsWith('#');
  }

  static bool _looksLikeScriptUrl(String value) {
    final compact = value
        .replaceAll(RegExp(r'[\s\u0000-\u001f]'), '')
        .toLowerCase();
    return compact.startsWith('javascript:') ||
        compact.startsWith('vbscript:') ||
        compact.startsWith('data:text/html');
  }

  static String _document(String body, String dictionaryCss, String extraCss) {
    return '''
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5">
<style>$_appCss</style>
<style>${_stripStyleClose(dictionaryCss)}</style>
${extraCss.isEmpty ? '' : '<style>${_stripStyleClose(extraCss)}</style>'}
</head>
<body><div class="rikai-entry-body">$body</div></body>
</html>
''';
  }

  static String _stripStyleClose(String css) {
    return css.replaceAll(
      RegExp(r'</?\s*(?:style|script)[^>]*>', caseSensitive: false),
      '',
    );
  }

  static const String _appCss = '''
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: #ffffff; color: #181818; }
body {
  font-family: "Noto Sans CJK JP", "Noto Sans JP", "Noto Sans CJK SC", sans-serif;
  font-size: 16px;
  line-height: 1.7;
  -webkit-text-size-adjust: 100%;
}
.rikai-entry-body { padding: 16px; max-width: 720px; margin: 0 auto; }
img, video, canvas, svg { max-width: 100%; height: auto; }
img { display: block; margin: 8px 0; }
audio.rikai-audio { display: block !important; width: 100% !important; max-width: 360px; height: 36px !important; margin: 8px 0; visibility: visible !important; }
a { color: #0052D9; text-decoration: none; }
a:active { text-decoration: underline; }
table { max-width: 100%; border-collapse: collapse; }
td, th { word-break: break-word; }
ruby rt { font-size: 0.55em; color: #5C6470; }
.rikai-entry-divider { border: 0; border-top: 1px solid #DCE3EC; margin: 24px 0; }
.rikai-missing-resource { opacity: .35; }
.rikai-blocked-resource { display: none; }
pre { white-space: pre-wrap; word-break: break-word; }
''';
}
