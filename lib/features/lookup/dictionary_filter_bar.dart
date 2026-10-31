import 'package:flutter/material.dart';

import '../../core/models/dict_info.dart';
import '../../core/models/dictionary_selection.dart';
import '../../core/theme/app_tokens.dart';

export '../../core/models/dictionary_selection.dart'
    show DictionarySelectionMode;

/// Compact, wrapping dictionary selector shared by the search page and the
/// reader lookup sheet. Names are shortened to the shortest unique prefix so
/// several Japanese dictionary titles fit in one row (or wrap naturally).
class DictionaryFilterBar extends StatelessWidget {
  const DictionaryFilterBar({
    super.key,
    required this.dictionaries,
    required this.selectedIds,
    required this.mode,
    required this.onToggle,
    required this.onSelectAll,
  });

  /// Three full rows plus half of the fourth are visible; the remainder
  /// scrolls vertically. The half row is intentional: it signals that more
  /// dictionaries exist below the fold.
  static const double visibleRows = AppSizes.dictionaryFilterVisibleRows;

  final List<DictionaryInfo> dictionaries;
  final Set<String> selectedIds;
  final DictionarySelectionMode mode;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    if (dictionaries.isEmpty) return const SizedBox.shrink();
    final titles = dictionaries.map((dictionary) => dictionary.title).toList();
    final selectedAll = dictionaries.every(
      (dictionary) => selectedIds.contains(dictionary.id),
    );
    final singleSelection =
        mode == DictionarySelectionMode.single && selectedIds.length == 1;
    final maxHeight =
        AppSizes.dictionaryFilterRow * visibleRows +
        AppSpacing.xxs * (visibleRows - 1);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        primary: false,
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            _DictionaryChip(
              label: '全选',
              selected: selectedAll,
              onTap: onSelectAll,
              icon: Icons.select_all,
            ),
            for (var index = 0; index < dictionaries.length; index++)
              _DictionaryChip(
                label: _shortTitle(titles[index], titles),
                selected: selectedIds.contains(dictionaries[index].id),
                dimmed:
                    singleSelection &&
                    !selectedIds.contains(dictionaries[index].id),
                onTap: () => onToggle(dictionaries[index].id),
              ),
          ],
        ),
      ),
    );
  }

  static String _shortTitle(String title, List<String> titles) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '词典';
    if (titles.length <= 1) return trimmed;
    final runes = trimmed.runes.toList(growable: false);
    for (var length = 1; length <= runes.length; length++) {
      final prefix = String.fromCharCodes(runes.take(length));
      var unique = true;
      for (final other in titles) {
        if (other == title) continue;
        if (other.trim().startsWith(prefix)) {
          unique = false;
          break;
        }
      }
      if (unique) return prefix;
    }
    return trimmed;
  }
}

/// Single/multi-select mode control. Lives in the parent's title area rather
/// than inside the chip list, so the chips can start at the very top.
class DictionarySelectionModeToggle extends StatelessWidget {
  const DictionarySelectionModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
    this.onDark = false,
  });

  final DictionarySelectionMode mode;
  final ValueChanged<DictionarySelectionMode> onChanged;

  /// True inside the deep-blue AppBar: unselected labels are white.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedForeground = onDark
        ? AppColors.header
        : AppColors.onPrimaryContainer;
    final unselectedForeground = onDark
        ? AppColors.onHeader
        : AppColors.textPrimary;
    final selectedBackground = onDark
        ? AppColors.surface
        : AppColors.primaryContainer;
    final borderColor = onDark
        ? AppColors.onHeader.withValues(alpha: 0.55)
        : AppColors.border;
    return SegmentedButton<DictionarySelectionMode>(
      segments: const [
        ButtonSegment(value: DictionarySelectionMode.multi, label: Text('多选')),
        ButtonSegment(value: DictionarySelectionMode.single, label: Text('单选')),
      ],
      selected: {mode},
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? selectedForeground
              : unselectedForeground,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? selectedBackground
              : AppColors.transparent,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: borderColor)),
        textStyle: WidgetStatePropertyAll(theme.textTheme.bodySmall),
      ),
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _DictionaryChip extends StatelessWidget {
  const _DictionaryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dimmed = false,
    this.icon,
  });

  final String label;
  final bool selected;
  final bool dimmed;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: SizedBox(
        height: AppSizes.dictionaryFilterRow,
        child: FilterChip(
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => onTap(),
          backgroundColor: AppColors.surface,
          selectedColor: AppColors.header,
          side: BorderSide(
            color: selected ? AppColors.header : AppColors.border,
          ),
          shape: const StadiumBorder(),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          avatar: icon == null
              ? null
              : Icon(
                  icon,
                  size: AppSizes.iconSmall,
                  color: selected
                      ? AppColors.onHeader
                      : AppColors.textSecondary,
                ),
          label: Text(
            label,
            maxLines: 1,
            // Keep the width identical in both states so neighbouring chips
            // never move when the user changes the selection.
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: selected ? AppColors.onHeader : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
