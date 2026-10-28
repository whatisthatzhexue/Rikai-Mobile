import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_tokens.dart';
import 'app_drawer.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('主页'),
        centerTitle: true,
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
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          _HomeActionButton(
            icon: Icons.photo_camera_outlined,
            label: '拍照识别',
            onTap: () => context.push('/capture'),
          ),
          const SizedBox(height: AppSpacing.md),
          _HomeActionButton(
            icon: Icons.text_fields,
            label: '输入文本',
            onTap: () => context.push('/reader'),
          ),
          const SizedBox(height: AppSpacing.md),
          _HomeActionButton(
            icon: Icons.search,
            label: '查词',
            onTap: () => context.push('/search'),
          ),
          const SizedBox(height: AppSpacing.md),
          _HomeActionButton(
            icon: Icons.history,
            label: '语料',
            onTap: () => _comingSoon(context, '语料'),
          ),
          const SizedBox(height: AppSpacing.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('使用前须知', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  const _ChecklistItem(
                    icon: Icons.menu_book_outlined,
                    text: '在设置中填写分词词典（UniDic）目录',
                  ),
                  const _ChecklistItem(
                    icon: Icons.library_books_outlined,
                    text: '添加 MDict 词典（.mdx；同目录的 .mdd/.css 会自动发现）',
                  ),
                  const _ChecklistItem(
                    icon: Icons.download_outlined,
                    text: '下载 OCR 模型后可拍照识别',
                  ),
                ],
              ),
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

class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: AppTypography.homeAction,
      height: AppTypography.homeActionHeightRatio,
      fontWeight: FontWeight.w600,
      color: AppColors.onHeader,
    );

    return SizedBox(
      width: double.infinity,
      height: AppSizes.homeActionHeight,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.header,
          foregroundColor: AppColors.onHeader,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: AppSizes.homeActionIcon,
              color: AppColors.onHeader,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(label, style: textStyle),
          ],
        ),
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
          Icon(icon, size: AppSizes.iconSmall, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
