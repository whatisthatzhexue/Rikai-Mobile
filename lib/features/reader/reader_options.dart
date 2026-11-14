import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/annotation_rules.dart';
import '../../core/ui/lexicandy_toast.dart';
import '../../state/providers.dart';

/// Shared reading options menu: furigana visibility and reading font size.
///
/// The text reader and the photo-set result use the same settings so their
/// rendering stays identical.
class ReaderOptionsMenu extends ConsumerWidget {
  const ReaderOptionsMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return PopupMenuButton<String>(
      tooltip: '阅读选项',
      icon: const Icon(Icons.tune),
      onSelected: (value) {
        final notifier = ref.read(appSettingsProvider.notifier);
        if (value == 'furigana') {
          final next = !settings.showFurigana;
          notifier.setShowFurigana(next);
          if (next &&
              settings.annotationRuleSetId == AnnotationRuleSets.noneId) {
            notifier.setAnnotationRuleSet(AnnotationRuleSets.basicId);
          }
        } else if (value.startsWith('style:')) {
          final id = value.substring('style:'.length);
          final showPitchHint =
              id == AnnotationRuleSets.pitchId &&
              settings.annotationRuleSetId != AnnotationRuleSets.pitchId;
          notifier.setAnnotationRuleSet(id);
          notifier.setShowFurigana(id != AnnotationRuleSets.noneId);
          if (showPitchHint) {
            LexiCandyToast.show(context, '单词音调数据来自UniDic，复合单词的音调请以词典为准。');
          }
        } else if (value.startsWith('size:')) {
          notifier.setReaderFontSize(
            double.parse(value.substring('size:'.length)),
          );
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem<String>(
          value: 'furigana',
          checked: settings.showFurigana,
          child: const Text('显示注音'),
        ),
        const PopupMenuDivider(),
        for (final ruleSet in AnnotationRuleSets.selectable)
          CheckedPopupMenuItem<String>(
            value: 'style:${ruleSet.id}',
            checked: settings.annotationRuleSetId == ruleSet.id,
            child: Text(ruleSet.name),
          ),
        const PopupMenuDivider(),
        for (final size in const [16.0, 20.0, 24.0, 28.0])
          CheckedPopupMenuItem<String>(
            value: 'size:$size',
            checked: settings.readerFontSize == size,
            child: Text('字号 ${size.toInt()}'),
          ),
      ],
    );
  }
}
