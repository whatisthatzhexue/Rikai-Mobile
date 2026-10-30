import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/storage/permission_service.dart';
import '../../state/providers.dart';

/// First-run setup guide: storage permission, UniDic, optional dictionaries
/// and OCR models, and the local-only boundary/licence confirmation.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage>
    with WidgetsBindingObserver {
  StorageAccessStatus? _storageStatus;
  bool _accepted = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final status = await ref.read(permissionServiceProvider).getStatus();
    if (!mounted) return;
    setState(() => _storageStatus = status);
  }

  Future<void> _requestPermission() async {
    final status = _storageStatus;
    if (status == null) return;
    try {
      if (status.sdkInt >= 30) {
        await ref.read(permissionServiceProvider).requestAllFilesAccess();
      } else if (status.sdkInt > 0) {
        await ref.read(permissionServiceProvider).requestLegacyReadPermission();
      } else {
        await ref.read(permissionServiceProvider).openAppSettings();
      }
      await _refreshPermissions();
    } catch (error) {
      if (!mounted) return;
      RikaiToast.show(context, '无法打开权限设置：$error');
    }
  }

  void _finish() {
    if (_finishing) return;
    setState(() => _finishing = true);
    ref.read(appSettingsProvider.notifier).setOnboardingCompleted(true);
    context.go('/');
  }

  Future<void> _open(String route) async {
    await context.push(route);
    if (mounted) await _refreshPermissions();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final dictionaries = ref.watch(dictionaryRepositoryProvider);
    final theme = Theme.of(context);
    final status = _storageStatus;
    final granted = status?.granted ?? false;
    final canStart = _accepted && !_finishing;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('欢迎使用 Rikai'),
        actions: [
          TextButton(
            onPressed: _finishing ? null : _finish,
            child: const Text(
              '跳过',
              style: TextStyle(color: AppColors.onHeader),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Image.asset(
                    'assets/Rikai_Icon.jpg',
                    width: AppSizes.heroIcon,
                    height: AppSizes.heroIcon,
                    fit: BoxFit.cover,
                    cacheWidth: 144,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('离线日语阅读与查词', style: theme.textTheme.titleLarge),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '先完成下面几项准备，就可以拍照或输入日文，分词、注音并点击查词。',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const _BoundaryPanel(),
            const SizedBox(height: AppSpacing.xl),
            Text('准备清单', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            _SetupTile(
              icon: Icons.folder_shared_outlined,
              title: '存储权限',
              subtitle: status == null
                  ? '正在检查…'
                  : granted
                  ? '已授权，可以原地读取 /sdcard/... 下的词典文件。'
                  : status.sdkInt >= 30
                  ? '读取 /sdcard/... 下的 UniDic/MDict 需要「所有文件访问」。'
                  : '需要读取存储权限。',
              done: granted,
              actionLabel: granted || status == null
                  ? null
                  : status.sdkInt == 0
                  ? '打开设置'
                  : '去授权',
              onAction: granted || status == null ? null : _requestPermission,
            ),
            _SetupTile(
              icon: Icons.translate_outlined,
              title: 'UniDic 分词词典',
              subtitle: settings.unidicPath.trim().isEmpty
                  ? '必需。请选择包含 matrix.bin 的 UniDic 文件夹。'
                  : '已配置：${_shortPath(settings.unidicPath)}',
              done: settings.unidicPath.trim().isNotEmpty,
              actionLabel: '去设置',
              onAction: () => _open('/settings'),
            ),
            _SetupTile(
              icon: Icons.library_books_outlined,
              title: 'MDict 词典',
              subtitle: dictionaries.isEmpty
                  ? '可选。添加词典后才能点击单词查看释义。'
                  : '已添加 ${dictionaries.length} 本词典。',
              done: dictionaries.isNotEmpty,
              actionLabel: '去管理',
              onAction: () => _open('/dictionaries'),
            ),
            _SetupTile(
              icon: Icons.document_scanner_outlined,
              title: 'OCR 模型',
              subtitle: '可选。拍照识别前需要下载或导入 PaddleOCR 模型。',
              done: false,
              actionLabel: '去模型设置',
              onAction: () => _open('/models'),
            ),
            const SizedBox(height: AppSpacing.lg),
            CheckboxListTile(
              value: _accepted,
              onChanged: _finishing
                  ? null
                  : (value) => setState(() => _accepted = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('我已阅读并理解上述边界与许可说明'),
              subtitle: Text(
                '继续使用即表示你同意仅由自己提供并遵守 UniDic 与 MDict 词典的许可。',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: canStart ? _finish : null,
              child: _finishing
                  ? const SizedBox(
                      width: AppSizes.icon,
                      height: AppSizes.icon,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('开始使用'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '之后可以在设置中随时修改路径、模型和显示选项。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length <= 2) return path;
    return '…/${segments[segments.length - 2]}/${segments.last}';
  }
}

class _BoundaryPanel extends StatelessWidget {
  const _BoundaryPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.shield_outlined,
                size: AppSizes.icon,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('本地优先', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '照片只在本机 OCR；UniDic 分词和 MDict 查词也都在本机完成。'
            '应用不上传图片、词典或输入文本。OCR 可能会漏字或认错字，'
            '重要内容请点开词典确认。',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _SetupTile extends StatelessWidget {
  const _SetupTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle : icon,
            size: AppSizes.iconLarge,
            color: done ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
