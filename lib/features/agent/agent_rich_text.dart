import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/rich_text_tags.dart';

/// Renders the validated rich-text summary. The caller must only pass text
/// whose tag-stripped form equals the original summary; malformed or modified
/// output is rejected before this widget is built.
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
    decoration: underline ? TextDecoration.underline : style.decoration,
    decorationColor: underline
        ? AgentTokens.richTextUnderlineColor
        : style.decorationColor,
    decorationThickness: underline
        ? AgentTokens.richTextUnderlineThickness
        : style.decorationThickness,
  );

  void addText(String value) {
    if (value.isEmpty) return;
    spans.add(TextSpan(text: value, style: effectiveStyle()));
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
          _rubySpan(base, reading, effectiveStyle(), textScaler: textScaler),
        );
      }
      // The formatter may leave the original `（reading）` after a RUBY pair
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

InlineSpan _rubySpan(
  String base,
  String reading,
  TextStyle baseStyle, {
  required TextScaler textScaler,
}) {
  final baseTextStyle = baseStyle.copyWith(height: 1.1);
  final readingStyle = baseStyle.copyWith(
    fontSize: AgentTokens.rubyReadingSize,
    color: baseStyle.color ?? AgentTokens.rubyReadingColor,
    height: 1,
    // Inherit BOLD from the surrounding span; a reading is never underlined.
    fontWeight: baseStyle.fontWeight,
    decoration: TextDecoration.none,
  );
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: Semantics(
      label: '$base（$reading）',
      excludeSemantics: true,
      child: _RubySpanWidget(
        base: base,
        reading: reading,
        baseStyle: baseTextStyle,
        readingStyle: readingStyle,
        textScaler: textScaler,
      ),
    ),
  );
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
    size = constraints.constrain(
      Size(base.size.width, base.size.height + reading.size.height),
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
    return constraints.constrain(
      Size(baseSize.width, baseSize.height + readingSize.height),
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
    final height = constraints
        .constrain(Size(baseSize.width, baseSize.height + readingSize.height))
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
