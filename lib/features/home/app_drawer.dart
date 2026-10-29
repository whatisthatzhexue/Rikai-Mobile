import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/page_route.dart';
import '../../state/providers.dart';
import '../settings/copyright_page.dart';
import '../settings/font_dialog.dart';
import '../settings/help_page.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Drawer(
      shape: const RoundedRectangleBorder(),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.header,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              MediaQuery.paddingOf(context).top + AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.asset(
                    'assets/Rikai_Icon.jpg',
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    cacheWidth: 156,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rikai',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: AppColors.onHeader),
                      ),
                      Text(
                        '离线日语阅读',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onHeader,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            leading: const Icon(Icons.font_download_outlined),
            title: const Text('自定义字体'),
            subtitle: Text(AppFonts.label(settings.fontFamily)),
            onTap: () => showFontDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('帮助'),
            onTap: () => _push(context, const HelpPage()),
          ),
          ListTile(
            leading: const Icon(Icons.copyright_outlined),
            title: const Text('著作权信息'),
            onTap: () => _push(context, const CopyrightPage()),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(RikaiPageRoute<void>(builder: (_) => page));
  }
}
