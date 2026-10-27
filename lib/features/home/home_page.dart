import 'package:flutter/material.dart';

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
            onPressed: () => _comingSoon(context, '设置'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            '日语阅读 · 离线查词',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '拍照或输入日文，使用 UniDic 分词注音，点击单词查询 MDict 词典。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _ActionCard(
            icon: Icons.photo_camera_outlined,
            title: '拍照识别',
            subtitle: '横向 PaddleOCR / 纵向 MangaOCR',
            onTap: () => _comingSoon(context, '拍照识别'),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.text_fields,
            title: '输入文本',
            subtitle: '直接分词、注音、查词',
            onTap: () => _comingSoon(context, '文本输入'),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.search,
            title: '查词',
            subtitle: '在多本 MDict 词典中搜索',
            onTap: () => _comingSoon(context, '查词'),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.history,
            title: '语料',
            subtitle: '保存照片、OCR 文本和分词结果',
            onTap: () => _comingSoon(context, '语料'),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('开始前', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
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
          const SizedBox(height: 16),
          Text(
            'Phase 0 脚手架：功能页面将在后续阶段接入。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature 将在后续阶段接入')),
    );
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
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
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
