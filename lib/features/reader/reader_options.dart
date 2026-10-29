import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          notifier.setShowFurigana(!settings.showFurigana);
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
