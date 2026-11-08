import 'package:flutter/material.dart';

import '../../core/models/annotation_rules.dart';
import '../../core/models/token.dart';
import '../../core/theme/app_tokens.dart';
import 'token_chip.dart';

/// A line of tokens wrapped to the available width.
class ReaderBlock extends StatelessWidget {
  const ReaderBlock({
    super.key,
    required this.tokens,
    required this.fontSize,
    required this.showFurigana,
    this.annotationRules = AnnotationRuleSets.basic,
    this.annotationTarget = AnnotationTarget.reader,
    this.onTokenTap,
  });

  final List<Token> tokens;
  final double fontSize;
  final bool showFurigana;
  final AnnotationRuleSet annotationRules;
  final AnnotationTarget annotationTarget;
  final ValueChanged<Token>? onTokenTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final token in tokens)
          TokenChip(
            token: token,
            fontSize: fontSize,
            showFurigana: showFurigana,
            annotationRules: annotationRules,
            annotationTarget: annotationTarget,
            onTap: onTokenTap,
          ),
      ],
    );
  }
}
