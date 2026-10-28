import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

class CopyrightPage extends StatelessWidget {
  const CopyrightPage({super.key});

  static const List<(String, String)> _components = [
    (
      'MeCab / mecab_for_dart',
      'BSD-3-Clause，Copyright 2001-2006 Taku Kudo、NTT；'
          'mecab_for_dart Copyright 2024 CaptainDario。',
    ),
    ('dict_reader', 'MIT License。MDict MDX/MDD 解析库。'),
    ('ONNX Runtime', 'MIT License，Copyright Microsoft Corporation。用于后续 OCR。'),
    (
      'overlay-translator',
      'Apache License 2.0，Copyright 2026 ciddwd。OCR 流水线参考来源。',
    ),
    (
      'PaddleOCR4Android',
      'MIT License，Copyright 2026 jangviktor-web。'
          '本项目评估后未编译其 Paddle-Lite 模块。',
    ),
    (
      'HarmonyOS Sans SC',
      'HarmonyOS Sans Fonts License Agreement，Copyright Huawei Device Co., Ltd.。'
          '字体由用户自行下载，不随本项目分发。',
    ),
    ('UniDic', '用户自备；GPL v2 / LGPL v2.1 / 修正 BSD 三选一，Copyright NINJAL。'),
    ('MDict 词典', '用户自备；词条内容的原始许可由词典提供方决定，本项目不再分发。'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headingStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: AppTypography.sectionHeading,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    );
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.7,
      color: AppColors.textPrimary,
    );
    final nameStyle = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('著作权信息')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Text('Rikai-Mobile', style: headingStyle),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '离线日语阅读与查词应用。原创代码；仅读取用户提供的 UniDic 与 '
            'MDict 词典。',
            style: bodyStyle,
          ),
          const Divider(height: AppSpacing.xxl),
          Text('第三方组件', style: headingStyle),
          const SizedBox(height: AppSpacing.sm),
          Text('以下为应用使用或参考的开源组件与用户自备数据。', style: bodyStyle),
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < _components.length; index++) ...[
            if (index > 0) const Divider(height: AppSpacing.xl),
            Text(_components[index].$1, style: nameStyle),
            const SizedBox(height: AppSpacing.xs),
            Text(_components[index].$2, style: bodyStyle),
          ],
          const Divider(height: AppSpacing.xxl),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Rikai-Mobile',
                applicationVersion: '1.0.0',
                applicationLegalese: 'Copyright 2026 Rikai-Mobile contributors',
              ),
              icon: const Icon(Icons.description_outlined, size: AppSizes.icon),
              label: const Text('查看开源许可证'),
            ),
          ),
        ],
      ),
    );
  }
}
