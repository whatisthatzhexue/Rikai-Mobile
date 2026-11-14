import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/lookup_match_mode.dart';
import '../../state/providers.dart';

/// Book-icon title-bar entry for the global lookup matching mode.
///
/// The menu mirrors [ReaderOptionsMenu]: a popup with one checked item per
/// mode, so the interaction is familiar across reading surfaces.
class LookupModeMenu extends ConsumerWidget {
  const LookupModeMenu({super.key, this.onChanged});

  final ValueChanged<LookupMatchMode>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      appSettingsProvider.select((settings) => settings.lookupMatchMode),
    );
    return PopupMenuButton<LookupMatchMode>(
      tooltip: '搜索模式：${mode.label}',
      icon: const Icon(Icons.menu_book_outlined),
      onSelected: (next) {
        ref.read(appSettingsProvider.notifier).setLookupMatchMode(next);
        onChanged?.call(next);
      },
      itemBuilder: (context) => [
        for (final option in LookupMatchMode.values)
          CheckedPopupMenuItem<LookupMatchMode>(
            value: option,
            checked: option == mode,
            child: Text(option.label),
          ),
      ],
    );
  }
}
