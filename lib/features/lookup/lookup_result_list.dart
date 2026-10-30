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
              top: AppSpacing.xs,
              bottom: AppSpacing.xxs,
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
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${group.entries.length} 条',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (group.entries.length >= 2)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onOpenAll(group),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.chip),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.list_alt, size: AppSizes.iconSmall),
                label: Text('查看全部（${group.entries.length} 条）'),
              ),
            ),
          for (final entry in group.entries)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: InkWell(
                onTap: () => onOpenEntry(group, entry),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              // Some dictionaries redirect to internal ids
                              // such as `00044` or `@daijirin2-...`; the
                              // matched key is the human-readable title shown
                              // by the entry page.
                              entry.matchedKey.isNotEmpty
                                  ? entry.matchedKey
                                  : entry.headword,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              htmlToPlainText(entry.html, maxLength: 90),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: AppTypography.helper,
                                height: 1.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: AppSpacing.sm),
                        child: Icon(Icons.chevron_right, size: AppSizes.icon),
                      ),
                    ],
                  ),
                ),
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
