import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const List<(String, String)> _sections = [
    (
      '使用前须知',
      '在设置中填写分词词典（UniDic）目录，并在词典管理中添加 .mdx 词典。'
          '词典均按原路径读取，不复制文件。Android 11 及以上需要在设置中授予'
          '“所有文件访问”权限，或把数据放到应用外部私有目录。',
    ),
    (
      '文本阅读',
      '输入或粘贴日文，点击“分词”。内容词会高亮，汉字上方显示注音。'
          '点击任意词即可查询 MDict 词典；查询结果可按词典切换、查看全部词条。',
    ),
    (
      '查词',
      '在“查词”页输入汉字、假名或全半角文本。支持 NFKC、平假名/片假名'
          '与去标点匹配；无结果时会给出词典前缀建议。',
    ),
    (
      '词典管理',
      '添加 .mdx 后，同目录同名 .mdd 与目录内 .css 会自动发现。可启用/停用、'
          '排序、重新校验；删除只会移除记录，不会删除文件。',
    ),
    (
      '显示与字体',
      '阅读界面可切换注音与字号；每本词典的词条上限在“阅读显示”中设置。'
          '左侧菜单“自定义字体”可切换 HarmonyOS Sans 或系统字体。',
    ),
    (
      '拍照识别与语料',
      'OCR 与语料保存正在后续阶段接入；当前版本支持文本输入、分词、'
          '浏览器式 MDict 查词与词典管理。',
    ),
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

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('帮助')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          for (var index = 0; index < _sections.length; index++) ...[
            if (index > 0) const Divider(height: AppSpacing.xxl),
            Text(_sections[index].$1, style: headingStyle),
            const SizedBox(height: AppSpacing.sm),
            Text(_sections[index].$2, style: bodyStyle),
          ],
        ],
      ),
    );
  }
}
