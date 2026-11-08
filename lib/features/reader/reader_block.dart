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
        for (final (index, token) in tokens.indexed)
          TokenChip(
            token: token,
            fontSize: fontSize,
            showFurigana: showFurigana,
            annotationRules: annotationRules,
            annotationTarget: annotationTarget,
            suppressPitch: _suppressPitch(tokens, index),
            onTap: onTokenTap,
          ),
      ],
    );
  }
}

/// UniDic pitch is word-local, while the displayed reading can depend on the
/// following token. For inflected verbs/adjectives before another non-punctuation
/// token, the isolated accent can be misleading. Keep onbin verb forms (イ音便/
/// 促音便/撥音便 etc.) because their accent is more stable; dictionary forms
/// are unaffected.
bool _suppressPitch(List<Token> tokens, int index) {
  if (index < 0 || index + 1 >= tokens.length) return false;
  final token = tokens[index];
  final next = tokens[index + 1];
  if (next.isPunctuationOrSymbol) return false;
  final isInflectedVerb =
      token.pos1 == '動詞' && token.surface.trim() != token.lemma.trim();
  final isInflectedAdjective =
      token.pos1 == '形容詞' && token.surface.trim() != token.lemma.trim();
  if (!isInflectedVerb && !isInflectedAdjective) return false;
  if (isInflectedVerb && token.cForm.contains('音便')) return false;
  return true;
}
