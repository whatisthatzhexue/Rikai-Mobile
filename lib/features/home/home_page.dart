import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_tokens.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rikai'),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Text('日语阅读 · 离线查词', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '拍照或输入日文，使用 UniDic 分词注音，点击单词查询 MDict 词典。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _ActionCard(
            icon: Icons.photo_camera_outlined,
            title: '拍照识别',
            subtitle: '横向 PaddleOCR / 纵向 MangaOCR',
            onTap: () => _comingSoon(context, '拍照识别'),
          ),
          const SizedBox(height: AppSpacing.md),
          _ActionCard(
            icon: Icons.text_fields,
            title: '输入文本',
            subtitle: '直接分词、注音、查词',
            onTap: () => context.push('/reader'),
          ),
          const SizedBox(height: AppSpacing.md),
          _ActionCard(
            icon: Icons.search,
            title: '查词',
            subtitle: '在多本 MDict 词典中搜索',
            onTap: () => context.push('/search'),
          ),
          const SizedBox(height: AppSpacing.md),
          _ActionCard(
            icon: Icons.history,
            title: '语料',
            subtitle: '保存照片、OCR 文本和分词结果',
            onTap: () => _comingSoon(context, '语料'),
          ),
          const SizedBox(height: AppSpacing.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('开始前', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  const _ChecklistItem(
                    icon: Icons.menu_book_outlined,
                    text: '在设置中填写 UniDic 目录（约 1.3GB，原地读取）',
                  ),
                  const _ChecklistItem(
                    icon: Icons.library_books_outlined,
                    text: '添加 MDict 词典（.mdx，可选 .mdd/.css）',
                  ),
                  const _ChecklistItem(
                    icon: Icons.download_outlined,
                    text: '下载 OCR 模型（PaddleOCR ~22MB、MangaOCR ~140MB）',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '离线分词、注音与 MDict 查词已接入；OCR 与语料将在后续阶段接入。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature 将在后续阶段接入')));
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        leading: Icon(icon, size: AppSizes.iconLarge, color: AppColors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, size: AppSizes.icon),
        onTap: onTap,
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSizes.iconSmall),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
