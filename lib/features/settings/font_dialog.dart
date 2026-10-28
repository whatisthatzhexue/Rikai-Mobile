import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_tokens.dart';
import '../../state/providers.dart';

/// Lets the user switch between the bundled HarmonyOS Sans and the system font.
Future<void> showFontDialog(BuildContext context, WidgetRef ref) async {
  final current = ref.read(appSettingsProvider).fontFamily;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('自定义字体'),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final family in AppFonts.values)
              ListTile(
                leading: Icon(
                  current == family
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: current == family
                      ? AppColors.primary
                      : AppColors.textTertiary,
                ),
                title: Text(AppFonts.label(family)),
                subtitle: Text(
                  family == AppFonts.system
                      ? '使用 Android 系统字体'
                      : '应用内置的 HarmonyOS Sans',
                ),
                onTap: () {
                  ref.read(appSettingsProvider.notifier).setFontFamily(family);
                  Navigator.of(dialogContext).pop();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
