import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/corpus_entry.dart';
import '../../core/theme/app_tokens.dart';
import '../../state/providers.dart';
import '../capture/capture_buttons.dart';
import '../reader/reader_options.dart';
import 'corpus_detail_page.dart';

class CorpusPage extends ConsumerWidget {
  const CorpusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(corpusEntriesProvider);
    final settings = ref.watch(appSettingsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('语料'),
        actions: const [ReaderOptionsMenu()],
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('语料读取失败', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(corpusEntriesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: AppSizes.emptyIcon,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('还没有保存的语料', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '在照片集右下角点击保存，照片和 OCR 文本会出现在这里。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () => context.push('/capture'),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('去拍照'),
                    ),
                  ],
                ),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.78,
            ),
            itemCount: list.length,
            itemBuilder: (context, index) => _CorpusCard(
              entry: list[index],
              fontSize: settings.readerFontSize,
              onOpen: () => context.push(
                '/corpus-detail',
                extra: CorpusDetailRouteArgs(list[index]),
              ),
              onCopy: list[index].text.isEmpty
                  ? null
                  : () => _copyText(context, list[index].text),
              onDelete: () => _delete(context, ref, list[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _copyText(BuildContext context, String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制全文')));
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CorpusEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条语料？'),
        content: const Text('照片副本和 OCR 文本会从本机删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onHeader,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(historyStoreProvider).delete(entry);
    ref.invalidate(corpusEntriesProvider);
  }
}

class _CorpusCard extends StatelessWidget {
  const _CorpusCard({
    required this.entry,
    required this.fontSize,
    required this.onOpen,
    required this.onCopy,
    required this.onDelete,
  });

  final CorpusEntry entry;
  final double fontSize;
  final VoidCallback onOpen;
  final VoidCallback? onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date =
        '${entry.createdAt.year}-'
        '${entry.createdAt.month.toString().padLeft(2, '0')}-'
        '${entry.createdAt.day.toString().padLeft(2, '0')}';
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: AppColors.surfaceMuted,
                    child: entry.imagePath.isEmpty
                        ? const Center(child: Icon(Icons.broken_image_outlined))
                        : Image.file(
                            File(entry.imagePath),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                          ),
                  ),
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: CaptureRoundButton(
                      tooltip: '删除语料',
                      icon: Icons.delete_outline,
                      background: AppColors.error,
                      size: AppSizes.corpusAction,
                      iconSize: AppSizes.icon,
                      onPressed: onDelete,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.text.isEmpty ? '（无 OCR 文本）' : entry.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: fontSize.clamp(14, 18),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          date,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: AppTypography.helper,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      PhotoCopyButton(onPressed: onCopy, label: '复制'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
