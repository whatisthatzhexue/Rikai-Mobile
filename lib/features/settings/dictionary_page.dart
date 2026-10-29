import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/dict_info.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/mdict/mdict_worker.dart';
import '../../state/providers.dart';
import 'dictionary_import_page.dart';

class DictionaryPage extends ConsumerStatefulWidget {
  const DictionaryPage({super.key});

  @override
  ConsumerState<DictionaryPage> createState() => _DictionaryPageState();
}

enum _DictionaryAction { moveUp, moveDown, revalidate, delete }

class _DictionaryPageState extends ConsumerState<DictionaryPage> {
  Future<void> _addDictionary() async {
    final info = await showDialog<DictionaryInfo>(
      context: context,
      builder: (context) => _AddDictionaryDialog(
        onSubmit: (path) =>
            ref.read(dictionaryRepositoryProvider.notifier).addDictionary(path),
      ),
    );
    if (!mounted || info == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加 ${info.title}（${_formatCount(info.entryCount)} 条）'),
      ),
    );
  }

  Future<void> _importFromFolder() async {
    final summary = await context.push<DictionaryImportSummary>(
      '/dictionary-import',
    );
    if (!mounted || summary == null) return;
    setState(() {});
    if (summary.failed == 0 && !summary.cancelled) return;
    final messenger = ScaffoldMessenger.of(context);
    final String message;
    if (summary.failed > 0 && summary.imported > 0) {
      message = '已导入 ${summary.imported} 本，${summary.failed} 本失败';
    } else if (summary.failed > 0) {
      message = '导入失败 ${summary.failed} 本';
    } else if (summary.imported > 0) {
      message = '已导入 ${summary.imported} 本（已取消剩余）';
    } else {
      message = '已取消导入';
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _revalidate(DictionaryInfo dictionary) async {
    final updated = await ref
        .read(dictionaryRepositoryProvider.notifier)
        .revalidate(dictionary.id);
    if (!mounted || updated == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated.isAvailable
              ? '校验通过：${_formatCount(updated.entryCount)} 条'
              : _displayDictionaryError(updated.lastError),
        ),
      ),
    );
  }

  Future<void> _delete(DictionaryInfo dictionary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除词典？'),
        content: Text('将从列表中移除「${dictionary.title}」，不会删除磁盘上的词典文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(dictionaryRepositoryProvider.notifier)
        .removeDictionary(dictionary.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已移除「${dictionary.title}」')));
  }

  @override
  Widget build(BuildContext context) {
    final dictionaries = ref.watch(dictionaryRepositoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MDict 词典'),
        actions: [
          IconButton(
            tooltip: '从文件夹导入',
            onPressed: _importFromFolder,
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: '添加词典',
            onPressed: _addDictionary,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: dictionaries.isEmpty
          ? _DictionaryEmpty(onAdd: _addDictionary, onImport: _importFromFolder)
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                Text(
                  '词典按原路径读取，不复制文件；启用的词典用于阅读区与查词。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final dictionary in dictionaries)
                  _DictionaryCard(
                    dictionary: dictionary,
                    onEnabledChanged: (enabled) {
                      ref
                          .read(dictionaryRepositoryProvider.notifier)
                          .setEnabled(dictionary.id, enabled);
                    },
                    onAction: (action) {
                      switch (action) {
                        case _DictionaryAction.moveUp:
                          ref
                              .read(dictionaryRepositoryProvider.notifier)
                              .move(dictionary.id, -1);
                          break;
                        case _DictionaryAction.moveDown:
                          ref
                              .read(dictionaryRepositoryProvider.notifier)
                              .move(dictionary.id, 1);
                          break;
                        case _DictionaryAction.revalidate:
                          _revalidate(dictionary);
                          break;
                        case _DictionaryAction.delete:
                          _delete(dictionary);
                          break;
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

class _DictionaryCard extends StatelessWidget {
  const _DictionaryCard({
    required this.dictionary,
    required this.onEnabledChanged,
    required this.onAction,
  });

  final DictionaryInfo dictionary;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<_DictionaryAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = [
      '${_formatCount(dictionary.entryCount)} 条',
      if (dictionary.encoding.isNotEmpty) dictionary.encoding,
      if (dictionary.engineVersion.isNotEmpty)
        'MDict ${dictionary.engineVersion}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dictionary.title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(metadata, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Switch(value: dictionary.enabled, onChanged: onEnabledChanged),
                PopupMenuButton<_DictionaryAction>(
                  tooltip: '词典操作',
                  onSelected: onAction,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _DictionaryAction.moveUp,
                      child: Text('上移'),
                    ),
                    const PopupMenuItem(
                      value: _DictionaryAction.moveDown,
                      child: Text('下移'),
                    ),
                    const PopupMenuItem(
                      value: _DictionaryAction.revalidate,
                      child: Text('重新校验'),
                    ),
                    PopupMenuItem(
                      value: _DictionaryAction.delete,
                      child: Text(
                        '删除',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _MetaTag(
                  label: dictionary.hasResources
                      ? '资源 ${dictionary.mddPaths.length}'
                      : '无资源',
                ),
                _MetaTag(label: '样式 ${dictionary.cssPaths.length}'),
                if (!dictionary.isAvailable)
                  const _MetaTag(label: '路径不可用', isError: true),
              ],
            ),
            if (dictionary.lastError.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  _displayDictionaryError(dictionary.lastError),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.label, this.isError = false});

  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: isError ? AppColors.error : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _DictionaryEmpty extends StatelessWidget {
  const _DictionaryEmpty({required this.onAdd, required this.onImport});

  final VoidCallback onAdd;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_books_outlined,
              size: AppSizes.emptyIcon,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('尚未添加词典', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '添加 .mdx 文件即可查词。同目录下的同名 .mdd 与 .css 会自动发现。'
              '词典原地读取，不复制文件。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.folder_open_outlined, size: AppSizes.icon),
              label: const Text('从文件夹导入'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: AppSizes.icon),
              label: const Text('手动添加词典'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddDictionaryDialog extends StatefulWidget {
  const _AddDictionaryDialog({required this.onSubmit});

  final Future<DictionaryInfo> Function(String path) onSubmit;

  @override
  State<_AddDictionaryDialog> createState() => _AddDictionaryDialogState();
}

class _AddDictionaryDialogState extends State<_AddDictionaryDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    try {
      final directoryPath = await FilePicker.getDirectoryPath(
        dialogTitle: '选择词典所在文件夹',
      );
      if (!mounted || directoryPath == null) return;

      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        setState(() => _error = '无法访问该文件夹');
        return;
      }
      final mdxFiles = <String>[];
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.mdx')) {
          mdxFiles.add(entity.path);
        }
      }
      if (!mounted) return;
      if (mdxFiles.isEmpty) {
        setState(() => _error = '该文件夹中没有 .mdx 文件');
        return;
      }
      if (mdxFiles.length == 1) {
        _controller.text = mdxFiles.first;
        setState(() => _error = '');
        return;
      }

      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('选择词典文件'),
          children: [
            for (final path in mdxFiles)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(path),
                child: Text(dictionaryFileName(path)),
              ),
          ],
        ),
      );
      if (!mounted || selected == null) return;
      _controller.text = selected;
      setState(() => _error = '');
    } on PlatformException {
      if (!mounted) return;
      setState(() => _error = '无法打开文件管理器，请稍后重试');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '选择文件夹失败，请确认文件夹可访问');
    }
  }

  Future<void> _submit() async {
    final path = _controller.text.trim();
    if (path.isEmpty) {
      setState(() => _error = '请输入 .mdx 文件路径');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });

    try {
      final info = await widget.onSubmit(path);
      if (!mounted) return;
      Navigator.of(context).pop(info);
    } on MdictException catch (error) {
      if (!mounted) return;
      setState(() => _error = _displayDictionaryError(error.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '添加失败，请确认词典文件可读');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('添加 MDict 词典'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'MDX 文件路径',
                hintText: '请选择或填写 .mdx 文件路径',
                prefixIcon: const Icon(Icons.description_outlined),
                suffixIcon: IconButton(
                  tooltip: '选择词典文件夹',
                  onPressed: _busy ? null : _pickDirectory,
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '原地读取；同目录同名 .mdd 与 .css 会自动发现。',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AppTypography.helper,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '若提示无法访问，请先在设置中授予所有文件访问。',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AppTypography.helper,
                height: 1.5,
                color: AppColors.textTertiary,
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: AppTypography.helper,
                  height: 1.5,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('添加'),
        ),
      ],
    );
  }
}

String _formatCount(int value) {
  return value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}

String _displayDictionaryError(String raw) {
  var text = raw.trim();
  final lower = text.toLowerCase();
  final debugIndex = lower.indexOf('instance of');
  if (debugIndex >= 0) text = text.substring(0, debugIndex).trim();
  while (text.endsWith('：') || text.endsWith(':')) {
    text = text.substring(0, text.length - 1).trim();
  }
  if (text.isEmpty) return '词典操作失败';
  final lowerText = text.toLowerCase();
  if (lowerText.startsWith('exception') ||
      lowerText.startsWith('error') ||
      lowerText.startsWith('mdictexception')) {
    return '词典操作失败';
  }
  return text;
}
