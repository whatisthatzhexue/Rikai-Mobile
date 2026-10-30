import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/ui/rikai_toast.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const List<_HelpSection> _sections = [
    _HelpSection(
      '使用前须知',
      '在设置中填写分词词典（UniDic）目录，并在词典管理中添加 .mdx 词典。'
          '词典均按原路径读取，不复制文件。Android 11 及以上需要在设置中授予'
          '“所有文件访问”权限，或把数据放到应用外部私有目录。',
    ),
    _HelpSection(
      'MDict 词典',
      'MDict 是一种常见的离线词典容器格式（.mdx/.mdd）。本应用只读取你自行'
          '提供的词典文件，不内置、不抓取也不分发词典内容。请只使用自己制作、'
          '获得授权或明确允许下载的词典，并遵守词典作者与出版方的许可。',
      links: [_HelpLinkData('MDict 官方站点/社区入口', 'https://www.mdict.cn/')],
    ),
    _HelpSection(
      'UniDic 分词词典',
      'UniDic 是日本国立国语研究所发布的日语形态素词典，用于把日文切分为'
          '词语并给出发音、词性等信息。UniDic 有多个版本和不同许可，请从官方'
          '页面下载并阅读对应版本的使用条款。应用不会复制或修改你的 UniDic。',
      links: [
        _HelpLinkData(
          'UniDic 官方下载（版本列表）',
          'https://clrd.ninjal.ac.jp/unidic/back_number.html',
        ),
      ],
    ),
    _HelpSection(
      '文本阅读',
      '输入或粘贴日文，点击“分词”。内容词会高亮，汉字上方显示注音。'
          '点击任意词即可查询 MDict 词典；查询结果可按词典切换、查看全部词条。'
          '分词后可点击“隐藏输入框”，把工具栏收起，将空间留给结果。',
    ),
    _HelpSection(
      '查词',
      '在“查词”页输入汉字、假名或全半角文本。支持 NFKC、平假名/片假名'
          '与去标点匹配。标题栏的书本图标可切换增量搜索、完全匹配、前方匹配和'
          '后方匹配；无结果时会给出词典前缀建议。',
    ),
    _HelpSection(
      '词典管理',
      '添加 .mdx 后，同目录同名 .mdd 与目录内 .css 会自动发现。可启用/停用、'
          '排序、重新校验；删除只会移除记录，不会删除文件。',
    ),
    _HelpSection(
      '显示与字体',
      '阅读界面可切换注音与字号；每本词典的词条上限在“阅读显示”中设置。'
          '左侧菜单“自定义字体”可切换 HarmonyOS Sans 或系统字体。',
    ),
    _HelpSection(
      '拍照识别',
      '先在“设置 → OCR 模型”中下载或导入 PaddleOCR 模型（约 20.5 MB，'
          '模型不随应用分发）。拍照或从相册选择图片后，可选择自动/横向/竖向识别；'
          '识别结果会进入文本阅读，可继续分词和点击查词。图片只在设备本地处理，'
          '不会上传。',
    ),
    _HelpSection(
      '语料',
      '在照片集右下角保存照片和 OCR 原文后，可在主页“历史记录”中查看、重新打开'
          '分词结果或删除。语料详情支持在保存的语料之间翻页。',
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
            Text(_sections[index].title, style: headingStyle),
            const SizedBox(height: AppSpacing.sm),
            Text(_sections[index].body, style: bodyStyle),
            for (final link in _sections[index].links)
              _HelpLinkTile(link: link, style: bodyStyle),
          ],
        ],
      ),
    );
  }
}

class _HelpSection {
  const _HelpSection(this.title, this.body, {this.links = const []});

  final String title;
  final String body;
  final List<_HelpLinkData> links;
}

class _HelpLinkData {
  const _HelpLinkData(this.label, this.url);

  final String label;
  final String url;
}

class _HelpLinkTile extends StatelessWidget {
  const _HelpLinkTile({required this.link, required this.style});

  final _HelpLinkData link;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _open(context),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, AppSizes.control),
          textStyle: style?.copyWith(
            color: AppColors.primary,
            fontSize: AppTypography.helper,
          ),
        ),
        icon: const Icon(Icons.open_in_new, size: AppSizes.iconSmall),
        label: Text(link.label),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(link.url);
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        RikaiToast.show(context, '无法打开浏览器，请手动访问：${link.url}');
      }
    } catch (_) {
      if (context.mounted) {
        RikaiToast.show(context, '无法打开浏览器，请手动访问：${link.url}');
      }
    }
  }
}
