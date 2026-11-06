import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/rich_text_tags.dart';

/// Renders display text containing RUBY/BOLD/UNDERLINE. Model-formatted text
/// must already have passed the tag-stripped diff guard; locally converted
/// text must preserve the base characters. Malformed model output is rejected
/// before this widget is built.
class AgentRichText extends StatelessWidget {
  const AgentRichText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final effectiveStyle = style ?? const TextStyle();
    return Text.rich(
      TextSpan(
        style: effectiveStyle,
        children: buildAgentRichTextSpans(
          text,
          effectiveStyle,
          textScaler: MediaQuery.textScalerOf(context),
        ),
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

List<InlineSpan> buildAgentRichTextSpans(
  String text,
  TextStyle style, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final spans = <InlineSpan>[];
  final matches = richTextTagPattern.allMatches(text).toList(growable: false);
  var cursor = 0;
  var bold = false;
  var underline = false;

  TextStyle effectiveStyle() => style.copyWith(
    fontWeight: bold ? FontWeight.w600 : style.fontWeight,
    // UNDERLINE is painted by _UnderlineSpanWidget at a fixed offset from the
    // alphabetic baseline; TextStyle decoration uses font-specific underline
    // metrics, which differ between kanji and punctuation such as `；`.
    decoration: TextDecoration.none,
    decorationColor: null,
    decorationThickness: null,
  );

  void addText(String value) {
    if (value.isEmpty) return;
    final textStyle = effectiveStyle();
    if (underline) {
      // A WidgetSpan is laid out as one inline object and cannot wrap inside
      // itself. Long underlined phrases therefore used to overflow instead of
      // breaking mid-line. Split long runs at character/word boundaries so the
      // rich-text line breaker can wrap between the resulting inline spans,
      // while keeping short runs atomic (one baseline-aligned underline).
      for (final chunk in _underlineChunks(value)) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _UnderlineSpanWidget(
              color: AgentTokens.richTextUnderlineColor,
              thickness: AgentTokens.richTextUnderlineThickness,
              offset: textScaler.scale(AgentTokens.richTextUnderlineOffset),
              child: Text(
                chunk,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                textScaler: textScaler,
                style: textStyle,
              ),
            ),
          ),
        );
      }
      return;
    }
    spans.add(TextSpan(text: value, style: textStyle));
  }

  var index = 0;
  while (index < matches.length) {
    final match = matches[index];
    addText(text.substring(cursor, match.start));
    final tag = (match.group(1) ?? '').toLowerCase();
    if (tag.startsWith('ruby=')) {
      var closeIndex = -1;
      for (var probe = index + 1; probe < matches.length; probe++) {
        if ((matches[probe].group(1) ?? '').toLowerCase() == '/ruby') {
          closeIndex = probe;
          break;
        }
      }
      if (closeIndex < 0) {
        addText(match.group(0) ?? '');
        cursor = match.end;
        index++;
        continue;
      }
      final close = matches[closeIndex];
      final reading = cleanReading(
        (match.group(1) ?? '').substring('ruby='.length),
      );
      final rawBase = text.substring(match.end, close.start);
      final base = rubyDisplayBase(rawBase, reading);
      if (reading.isEmpty || base.isEmpty || reading == base) {
        addText(
          rawBase.isEmpty ? text.substring(match.start, close.end) : rawBase,
        );
      } else {
        spans.add(
          _rubySpan(
            base,
            reading,
            effectiveStyle(),
            textScaler: textScaler,
            underline: underline,
          ),
        );
      }
      // The formatter may leave the original bracket reading after a RUBY pair
      // when it wraps only the base word. Hide that duplicate annotation.
      cursor = skipDuplicateRubyReading(text, close.end, reading);
      index = closeIndex + 1;
      continue;
    }
    if (tag == 'bold') {
      bold = true;
    } else if (tag == '/bold') {
      bold = false;
    } else if (tag == 'underline') {
      underline = true;
    } else if (tag == '/underline') {
      underline = false;
    } else {
      addText(match.group(0) ?? '');
    }
    cursor = match.end;
    index++;
  }
  addText(text.substring(cursor));
  return spans;
}

/// Splits an underlined run into chunks that the paragraph can wrap between.
///
/// Short runs stay as one chunk so a word like `重点` keeps a single
/// underline widget (and one semantics node). Longer runs are split into CJK
/// characters, Latin/digit words and whitespace so Japanese can wrap at any
/// character without breaking an English word in the middle.
List<String> _underlineChunks(String value) {
  if (value.runes.length <= 4) return <String>[value];
  final chunks = <String>[];
  final buffer = StringBuffer();
  var inLatinWord = false;

  void flush() {
    if (buffer.isEmpty) return;
    chunks.add(buffer.toString());
    buffer.clear();
  }

  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final isLatin = _underlineLatinWordPart.hasMatch(char);
    if (isLatin) {
      if (!inLatinWord) flush();
      buffer.write(char);
      inLatinWord = true;
      continue;
    }
    flush();
    inLatinWord = false;
    chunks.add(char);
  }
  flush();
  return chunks;
}

final RegExp _underlineLatinWordPart = RegExp(r"[A-Za-z0-9À-ÖØ-öø-ÿĀ-ž'’\-]");

InlineSpan _rubySpan(
  String base,
  String reading,
  TextStyle baseStyle, {
  required TextScaler textScaler,
  required bool underline,
}) {
  // Keep the base's line metrics identical to the surrounding inline text.
  // A shorter height here (for example 1.1) shifts the reported baseline and
  // makes ruby-bearing runs sit slightly below plain runs.
  final baseTextStyle = baseStyle;
  final readingStyle = baseStyle.copyWith(
    fontSize: AgentTokens.rubyReadingSize,
    color: baseStyle.color ?? AgentTokens.rubyReadingColor,
    height: 1,
    // Inherit BOLD from the surrounding span; a reading is never underlined.
    fontWeight: baseStyle.fontWeight,
    decoration: TextDecoration.none,
  );
  final ruby = _RubySpanWidget(
    base: base,
    reading: reading,
    baseStyle: baseTextStyle,
    readingStyle: readingStyle,
    textScaler: textScaler,
  );
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: Semantics(
      label: '$base（$reading）',
      excludeSemantics: true,
      child: underline
          ? _UnderlineSpanWidget(
              color: AgentTokens.richTextUnderlineColor,
              thickness: AgentTokens.richTextUnderlineThickness,
              offset: textScaler.scale(AgentTokens.richTextUnderlineOffset),
              child: ruby,
            )
          : ruby,
    ),
  );
}

/// Paints UNDERLINE at a fixed distance below the child's alphabetic baseline.
/// [TextStyle.decoration] uses font underline metrics, so a full-width `；`
/// can sit at a different height than a kanji. A fixed baseline-relative line
/// keeps every glyph consistent, including RUBY bases.
class _UnderlineSpanWidget extends SingleChildRenderObjectWidget {
  const _UnderlineSpanWidget({
    required Widget child,
    required this.color,
    required this.thickness,
    required this.offset,
  }) : super(child: child);

  final Color color;
  final double thickness;
  final double offset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderUnderlineSpan(color: color, thickness: thickness, offset: offset);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderUnderlineSpan renderObject,
  ) {
    renderObject
      ..color = color
      ..thickness = thickness
      ..offset = offset;
  }
}

class _RenderUnderlineSpan extends RenderProxyBox {
  _RenderUnderlineSpan({
    required Color color,
    required double thickness,
    required double offset,
  }) : _color = color,
       _thickness = thickness,
       _offset = offset;

  Color _color;
  double _thickness;
  double _offset;
  double? _baseline;

  /// Diagnostics used by widget tests to prove the custom line was painted at
  /// a real baseline (rather than silently skipped).
  int paintCount = 0;
  double? lastPaintedBaseline;

  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  set thickness(double value) {
    if (_thickness == value) return;
    _thickness = value;
    markNeedsPaint();
  }

  set offset(double value) {
    if (_offset == value) return;
    _offset = value;
    markNeedsPaint();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final value = child?.computeDistanceToActualBaseline(baseline);
    if (value != null) _baseline = value;
    return value;
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final value = child?.computeDryBaseline(constraints, baseline);
    if (value != null) _baseline = value;
    return value;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final baseline = _baseline;
    if (baseline == null || size.width <= 0) return;
    final paint = Paint()
      ..color = _color
      ..strokeWidth = _thickness
      ..strokeCap = StrokeCap.square;
    final y = offset.dy + baseline + _offset;
    context.canvas.drawLine(
      Offset(offset.dx, y),
      Offset(offset.dx + size.width, y),
      paint,
    );
    paintCount++;
    lastPaintedBaseline = baseline;
  }
}

/// Lays the reading above the base while reporting the base text's baseline.
/// A plain [Stack] reports the highest child baseline, which would align the
/// small reading with the line and push the base down.
class _RubySpanWidget extends MultiChildRenderObjectWidget {
  _RubySpanWidget({
    required String base,
    required String reading,
    required TextStyle baseStyle,
    required TextStyle readingStyle,
    required TextScaler textScaler,
  }) : super(
         children: <Widget>[
           Text(
             base,
             maxLines: 1,
             softWrap: false,
             textScaler: textScaler,
             style: baseStyle,
           ),
           Text(
             reading,
             maxLines: 1,
             softWrap: false,
             overflow: TextOverflow.visible,
             textAlign: TextAlign.center,
             textScaler: textScaler,
             style: readingStyle,
           ),
         ],
       );

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRubySpan();

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {}
}

class _RubySpanParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderRubySpan extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RubySpanParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RubySpanParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RubySpanParentData) {
      child.parentData = _RubySpanParentData();
    }
  }

  @override
  void performLayout() {
    final base = firstChild;
    final reading = base == null ? null : childAfter(base);
    if (base == null || reading == null) {
      size = constraints.smallest;
      return;
    }
    final childConstraints = constraints.loosen();
    base.layout(childConstraints, parentUsesSize: true);
    reading.layout(childConstraints, parentUsesSize: true);
    // The reading may be wider than the base (for example 漢字 → かんじ).
    // Sizing the ruby to the base alone makes the reading overflow into the
    // next word, where it overlaps that word's ruby. Reserve the union width
    // and centre both parts inside it.
    final contentWidth = base.size.width > reading.size.width
        ? base.size.width
        : reading.size.width;
    size = constraints.constrain(
      Size(contentWidth, base.size.height + reading.size.height),
    );
    (base.parentData! as _RubySpanParentData).offset = Offset(
      (size.width - base.size.width) / 2,
      size.height - base.size.height,
    );
    (reading.parentData! as _RubySpanParentData).offset = Offset(
      (size.width - reading.size.width) / 2,
      0,
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final base = firstChild;
    final reading = base == null ? null : childAfter(base);
    if (base == null || reading == null) return constraints.smallest;
    final childConstraints = constraints.loosen();
    final baseSize = base.getDryLayout(childConstraints);
    final readingSize = reading.getDryLayout(childConstraints);
    final contentWidth = baseSize.width > readingSize.width
        ? baseSize.width
        : readingSize.width;
    return constraints.constrain(
      Size(contentWidth, baseSize.height + readingSize.height),
    );
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final base = firstChild;
    final reading = base == null ? null : childAfter(base);
    if (base == null || reading == null) return null;
    final childConstraints = constraints.loosen();
    final baseBaseline = base.getDryBaseline(childConstraints, baseline);
    if (baseBaseline == null) return null;
    final baseSize = base.getDryLayout(childConstraints);
    final readingSize = reading.getDryLayout(childConstraints);
    final contentWidth = baseSize.width > readingSize.width
        ? baseSize.width
        : readingSize.width;
    final height = constraints
        .constrain(Size(contentWidth, baseSize.height + readingSize.height))
        .height;
    return height - baseSize.height + baseBaseline;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final base = firstChild;
    if (base == null) return null;
    final baseBaseline = base.getDistanceToActualBaseline(baseline);
    if (baseBaseline == null) return null;
    final parentData = base.parentData! as _RubySpanParentData;
    return parentData.offset.dy + baseBaseline;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
