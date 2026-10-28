import 'package:flutter/material.dart';

import '../../core/models/lookup_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/html_text.dart';

/// Grouped lookup hits shared by the reader sheet and the search page.
class LookupHitList extends StatelessWidget {
  const LookupHitList({
    super.key,
    required this.groups,
    required this.onOpenEntry,
    required this.onOpenAll,
  });

  final List<DictionaryLookupGroup> groups;
  final void Function(DictionaryLookupGroup group, LookupEntry entry)
  onOpenEntry;
  final ValueChanged<DictionaryLookupGroup> onOpenAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.menu_book_outlined,
                  size: AppSizes.iconSmall,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    group.dictionary.title,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${group.entries.length} 条',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (group.entries.length >= 2)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onOpenAll(group),
                icon: const Icon(Icons.list_alt, size: AppSizes.iconSmall),
                label: Text('查看全部（${group.entries.length} 条）'),
              ),
            ),
          for (final entry in group.entries)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                title: Text(
                  entry.headword.isNotEmpty ? entry.headword : entry.matchedKey,
                ),
                subtitle: Text(
                  htmlToPlainText(entry.html, maxLength: 90),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenEntry(group, entry),
              ),
            ),
          if (group.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                group.error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
