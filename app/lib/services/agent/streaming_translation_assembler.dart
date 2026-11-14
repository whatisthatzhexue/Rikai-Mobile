import '../../core/utils/rich_text_tags.dart';

/// Consumes the main analysis text stream and emits only complete
/// `[TRANSLATION]...[/TRANSLATION]` blocks.
///
/// This is deliberately narrower than the full task-level streaming plan:
/// segment blocks are not exposed until they have passed the normal
/// parse/validate path. The preview is display-only and never enters history or
/// a provider request.
class StreamingTranslationAssembler {
  StreamingTranslationAssembler({
    required Set<String> quoteIds,
    required void Function(String text) onPreview,
  }) : _quoteIds = Set<String>.of(quoteIds),
       _onPreview = onPreview;

  static final RegExp _translation = RegExp(
    r'\[TRANSLATION\b([^\]]*)\]([\s\S]*?)\[/TRANSLATION\]',
    caseSensitive: false,
  );
  static final RegExp _quote = RegExp(
    r'''\bquote(?:_id)?\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s\]]+))''',
    caseSensitive: false,
  );

  final Set<String> _quoteIds;
  final void Function(String text) _onPreview;
  final StringBuffer _buffer = StringBuffer();
  final Set<String> _emitted = <String>{};

  /// Appends one provider delta. Scanning is skipped until a `]` appears,
  /// because a complete block cannot close without one.
  void add(String delta) {
    if (delta.isEmpty) return;
    _buffer.write(delta);
    if (delta.contains(']')) _scan();
  }

  /// Resynchronizes after a stream continuation trim. Already emitted previews
  /// stay visible; replayed prefix blocks are deduplicated by quote+text.
  void reset(String prefix) {
    _buffer
      ..clear()
      ..write(prefix);
  }

  /// Scans any final complete block after the provider stream closes.
  void flush() => _scan();

  void _scan() {
    final text = _buffer.toString();
    for (final match in _translation.allMatches(text)) {
      final attrs = match.group(1) ?? '';
      final quoteId = _quoteId(attrs);
      if (quoteId.isEmpty || !_quoteIds.contains(quoteId)) continue;
      final body = localReadingsToRuby(match.group(2) ?? '').trim();
      if (body.isEmpty) continue;
      final key = '$quoteId\u0000$body';
      if (!_emitted.add(key)) continue;
      _onPreview(body);
    }
  }

  String _quoteId(String attrs) {
    final match = _quote.firstMatch(attrs);
    if (match == null) return '';
    return (match.group(1) ?? match.group(2) ?? match.group(3) ?? '').trim();
  }
}
