import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/dictionary_scan.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/format_bytes.dart';
import '../../services/mdict/dictionary_scanner.dart';
import '../../services/mdict/mdict_worker.dart';
import '../../state/providers.dart';

/// Result handed back to the dictionary management page. The import page
/// closes immediately so the refreshed dictionary list is the result screen.
class DictionaryImportSummary {
  const DictionaryImportSummary({
    required this.imported,
    required this.failed,
    required this.cancelled,
  });

  final int imported;
  final int failed;
  final bool cancelled;
}

class DictionaryImportPage extends ConsumerStatefulWidget {
  const DictionaryImportPage({super.key});

  @override
  ConsumerState<DictionaryImportPage> createState() =>
      _DictionaryImportPageState();
}

class _DictionaryImportPageState extends ConsumerState<DictionaryImportPage> {
  final TextEditingController _pathController = TextEditingController();
  final DictionaryScanner _scanner = const DictionaryScanner();
  List<DictionaryScanEntry> _entries = const [];
  final Set<String> _selected = {};
  bool _scanning = false;
  bool _probing = false;
  bool _importing = false;
  bool _importCancelRequested = false;
  String? _error;
  String _status = '';
  int _progressCurrent = 0;
  int _progressTotal = 0;
  int _token = 0;

  @override
  void dispose() {
    _token++;
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    try {
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: '选择词典总目录',
      );
      if (!mounted || selected == null) return;
      _pathController.text = selected;
      await _scan(selected);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = '无法打开文件管理器：${error.message ?? error.code}');
    }
  }

  Future<void> _scan(String root) async {
    final path = root.trim();
    if (path.isEmpty) {
      setState(() => _error = '请选择词典所在文件夹');
      return;
    }
    final token = ++_token;
    setState(() {
      _scanning = true;
      _probing = false;
      _importing = false;
      _entries = const [];
      _selected.clear();
      _error = null;
      _status = '正在扫描目录…';
      _progressCurrent = 0;
      _progressTotal = 0;
    });
    try {
      final existing = ref
          .read(dictionaryRepositoryProvider)
          .map((dictionary) => dictionary.mdxPath)
          .toSet();
      final entries = await _scanner.scan(path, existingPaths: existing);
      if (!mounted || token != _token) return;
      setState(() {
        _entries = entries;
        _scanning = false;
        _probing = entries.isNotEmpty;
        _status = entries.isEmpty ? '没有找到 .mdx 词典' : '正在读取词典信息…';
      });
      if (entries.isNotEmpty) {
        await _probeEntries(token);
      }
    } catch (error) {
      if (!mounted || token != _token) return;
      setState(() {
        _scanning = false;
        _probing = false;
        _error = '扫描失败：$error';
        _status = '';
      });
    }
  }

  Future<void> _probeEntries(int token) async {
    final service = await ref.read(mdictServiceProvider.future);
    if (!mounted || token != _token) return;
    final entries = _entries.toList();
    for (var index = 0; index < entries.length; index++) {
      if (!mounted || token != _token) return;
      final entry = entries[index];
      if (entry.status == DictionaryScanStatus.existing) continue;
      setState(
        () => _status = '正在读取 ${index + 1}/${entries.length}：$entry.fileName',
      );
      DictionaryScanEntry next;
      try {
        final metadata = await service.probe(entry.path);
        next = entry.copyWith(
          title: metadata.title.isEmpty ? entry.title : metadata.title,
          status: DictionaryScanStatus.importable,
          message: '',
        );
      } on MdictException catch (error) {
        next = entry.copyWith(
          status: DictionaryScanStatus.unsupported,
          message: error.message,
        );
      } catch (error) {
        next = entry.copyWith(
          status: DictionaryScanStatus.unsupported,
          message: error.toString(),
        );
      }
      if (!mounted || token != _token) return;
      setState(() {
        _entries = [
          for (final current in _entries)
            current.path == next.path ? next : current,
        ];
        if (next.status == DictionaryScanStatus.importable) {
          _selected.add(next.path);
        }
      });
    }
    if (mounted && token == _token) {
      setState(() {
        _probing = false;
        _status = '扫描完成';
      });
    }
  }

  void _cancelScan() {
    _token++;
    setState(() {
      _scanning = false;
      _probing = false;
      _status = '已取消扫描';
    });
  }

  Future<void> _importSelected() async {
    if (_importing) return;
    final selected = _entries
        .where(
          (entry) =>
              _selected.contains(entry.path) &&
              entry.status == DictionaryScanStatus.importable,
        )
        .toList(growable: false);
    if (selected.isEmpty) return;
    setState(() {
      _importing = true;
      _importCancelRequested = false;
      _error = null;
      _progressCurrent = 0;
      _progressTotal = selected.length;
      _status = '正在导入…';
    });
    var success = 0;
    var failed = 0;
    for (final entry in selected) {
      if (_importCancelRequested) break;
      if (!mounted) return;
      setState(() {
        _progressCurrent++;
        _status = '正在导入 $_progressCurrent/$_progressTotal：$entry.fileName';
      });
      try {
        await ref
            .read(dictionaryRepositoryProvider.notifier)
            .addDictionary(entry.path);
        success++;
      } on MdictException {
        failed++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    context.pop(
      DictionaryImportSummary(
        imported: success,
        failed: failed,
        cancelled: _importCancelRequested,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('导入 MDict 词典')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _pathController,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: _scan,
                    decoration: const InputDecoration(
                      labelText: '词典文件夹',
                      hintText: '请选择词典所在文件夹',
                      prefixIcon: Icon(Icons.folder_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _scanning || _importing ? null : _browse,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('浏览'),
                      ),
                      TextButton.icon(
                        onPressed: _scanning || _importing
                            ? null
                            : () => _scan(_pathController.text),
                        icon: const Icon(Icons.search),
                        label: const Text('扫描'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '应用会递归扫描文件夹及所有子文件夹；每个 .mdx 单独导入，'
                    '同目录同名 .mdd 与目录内 .css 自动关联。词典原地读取，不复制文件。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AppTypography.helper,
                      height: 1.5,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(_status, style: theme.textTheme.bodyMedium),
                  ],
                  if (_scanning || _probing) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const LinearProgressIndicator(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _cancelScan,
                        child: const Text('取消扫描'),
                      ),
                    ),
                  ],
                  if (_importing) ...[
                    const SizedBox(height: AppSpacing.xs),
                    LinearProgressIndicator(
                      value: _progressTotal == 0
                          ? null
                          : _progressCurrent / _progressTotal,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _importCancelRequested = true),
                        child: const Text('取消导入'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          _scanning ? '正在扫描…' : '选择文件夹后，这里会列出扫描到的词典。',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      itemCount: _entries.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        return _ScanEntryTile(
                          entry: entry,
                          selected: _selected.contains(entry.path),
                          onChanged:
                              entry.status == DictionaryScanStatus.importable
                              ? (value) {
                                  setState(() {
                                    if (value ?? false) {
                                      _selected.add(entry.path);
                                    } else {
                                      _selected.remove(entry.path);
                                    }
                                  });
                                }
                              : null,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _scanning || _probing || _importing || _selected.isEmpty
                      ? null
                      : _importSelected,
                  child: Text('导入所选（${_selected.length}）'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanEntryTile extends StatelessWidget {
  const _ScanEntryTile({
    required this.entry,
    required this.selected,
    required this.onChanged,
  });

  final DictionaryScanEntry entry;
  final bool selected;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = switch (entry.status) {
      DictionaryScanStatus.scanning => '正在读取…',
      DictionaryScanStatus.importable => '可导入',
      DictionaryScanStatus.existing =>
        entry.message.isEmpty ? '已存在' : entry.message,
      DictionaryScanStatus.unsupported => '不支持',
    };
    return CheckboxListTile(
      value: selected,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(entry.title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.folder}\n${formatBytes(entry.size)} · $status',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AppTypography.helper,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      isThreeLine: true,
    );
  }
}
