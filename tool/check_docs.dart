// Documentation guard for LexiCandy.
//
// Usage (from the repository root):
//   dart tool/check_docs.dart              # full check
//   dart tool/check_docs.dart --links-only # links + old-path bans only
//
// Pure dart:io: no package dependencies, so it can run before `flutter pub get`
// and from a repository root that has no pubspec.yaml of its own.

import 'dart:io';

const _rootDocs = 'docs';

const _currentDirs = <String>[
  'docs/01-规范',
  'docs/02-设计',
  'docs/03-进度',
  'docs/05-参考',
  'docs/07-维护',
  'docs/performance',
];

const _chineseCurrentDirs = <String>[
  'docs/01-规范',
  'docs/02-设计/助手',
  'docs/02-设计/接口模式',
  'docs/03-进度',
  'docs/07-维护',
  'docs/performance',
];

const _historyDir = 'docs/04-历史';
const _sampleDir = 'docs/06-样本';

/// Old paths that must not appear in current docs. History is exempt because
/// historical snapshots intentionally preserve the paths of their time.
const _bannedSubstrings = <String>[
  'docs/project-data.md',
  'docs/project-rules.md',
  'docs/project_tips.md',
  'docs/design-tokens.md',
  'docs/project-history.md',
  'docs/phase',
  'docs/schemas/agent',
  'docs/agent_output',
  'docs/agent_docs',
  'docs/开发历史',
  'docs/重要参考',
  'docs/手写文档',
  'docs/模式',
  'docs/留档',
  'docs/archive',
  'Agent-Refactor-Idea.txt',
  '项目初始文档.txt',
  'phase6-agent-design.md',
  'phase6-agent-contracts.md',
  'phase6-status.md',
  'dev-setup.md',
  'models.md',
  'licenses.md',
];

const _fullWidthPunctuation = <String>[
  '（',
  '）',
  '【',
  '】',
  '「',
  '」',
  '『',
  '』',
  '，',
  '。',
  '、',
  '：',
  '；',
  '？',
  '！',
  '“',
  '”',
  '‘',
  '’',
];

final _markdownLink = RegExp(r'\]\(([^)]+)\)');

void main(List<String> args) {
  final linksOnly = args.contains('--links-only');
  final issues = <String>[];

  final files = _collectDocsFiles();
  if (files.isEmpty) {
    stderr.writeln('No documentation files found.');
    exit(2);
  }

  for (final file in files) {
    _checkLinks(file, issues);
    if (!linksOnly && _isCurrentDoc(file.path)) {
      _checkBannedPaths(file, issues);
    }
  }

  if (!linksOnly) {
    _checkRegistration(files, issues);
    _checkNaming(files, issues);
    _checkBanners(files, issues);
    _checkVersionLabels(files, issues);
  }

  if (issues.isEmpty) {
    stdout.writeln('docs check passed (${files.length} files).');
    return;
  }

  stderr.writeln('docs check failed: ${issues.length} issue(s)');
  for (final issue in issues) {
    stderr.writeln('  $issue');
  }
  exit(1);
}

List<File> _collectDocsFiles() {
  final files = <File>[];
  for (final name in <String>['README.md', 'CLAUDE.md']) {
    final file = File(name);
    if (file.existsSync()) files.add(file);
  }
  final docs = Directory(_rootDocs);
  if (!docs.existsSync()) return files;
  for (final entity in docs.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = _posix(entity.path);
    if (path.endsWith('.md') || path.endsWith('.txt')) files.add(entity);
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

bool _isCurrentDoc(String rawPath) {
  final path = _posix(rawPath);
  if (path == 'README.md' || path == 'CLAUDE.md') return true;
  if (path == 'docs/07-维护/版本命名.md') return false;
  // External reference samples are not current docs.
  if (path.endsWith('_sample.md')) return false;
  for (final dir in _currentDirs) {
    if (path.startsWith('$dir/')) return true;
  }
  return false;
}

bool _isBannerExempt(String rawPath) {
  final path = _posix(rawPath);
  if (path == 'README.md' || path == 'CLAUDE.md') return true;
  if (path.startsWith('$_historyDir/')) return true;
  if (path.startsWith('$_sampleDir/')) return true;
  if (path.endsWith('_sample.md')) return true;
  if (path.endsWith('.txt')) return true;
  return false;
}

void _checkLinks(File file, List<String> issues) {
  final content = _read(file);
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final match in _markdownLink.allMatches(lines[i])) {
      var target = match.group(1)!.trim();
      if (target.startsWith('<') && target.contains('>')) {
        target = target.substring(1, target.indexOf('>'));
      } else {
        target = target.split(RegExp(r'\s+')).first;
      }
      if (target.isEmpty ||
          target.startsWith('#') ||
          target.startsWith('http://') ||
          target.startsWith('https://') ||
          target.startsWith('mailto:') ||
          target.startsWith('tel:') ||
          target.startsWith('data:')) {
        continue;
      }
      final withoutAnchor = target.split('#').first.split('?').first;
      if (withoutAnchor.isEmpty) continue;
      String decoded;
      try {
        decoded = Uri.decodeComponent(withoutAnchor);
      } on ArgumentError {
        decoded = withoutAnchor;
      }
      final resolved = decoded.startsWith('/')
          ? _normalize(decoded.substring(1))
          : _normalize('${_dirname(file.path)}/$decoded');
      if (!File(resolved).existsSync() && !Directory(resolved).existsSync()) {
        issues.add('${file.path}:${i + 1} broken link -> $target');
      }
    }
  }
}

void _checkBannedPaths(File file, List<String> issues) {
  final content = _read(file);
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final banned in _bannedSubstrings) {
      if (lines[i].contains(banned)) {
        issues.add('${file.path}:${i + 1} banned old path "$banned"');
      }
    }
  }
}

void _checkRegistration(List<File> files, List<String> issues) {
  final readmeFile = File('$_rootDocs/README.md');
  if (!readmeFile.existsSync()) {
    issues.add('docs/README.md is missing (the single documentation index)');
    return;
  }
  final readme = _read(readmeFile);
  for (final file in files) {
    final path = _posix(file.path);
    if (!_isCurrentDoc(path)) continue;
    if (path == '$_rootDocs/README.md' ||
        path == 'README.md' ||
        path == 'CLAUDE.md' ||
        !path.endsWith('.md')) {
      continue;
    }
    final relative = _relative(path, _rootDocs);
    if (!readme.contains(relative)) {
      issues.add('${file.path}: not registered in docs/README.md');
    }
  }
}

void _checkNaming(List<File> files, List<String> issues) {
  for (final file in files) {
    final path = _posix(file.path);
    if (!path.startsWith('$_rootDocs/')) continue;
    if (path.startsWith('$_historyDir/原始需求/') ||
        path.startsWith('$_sampleDir/')) {
      continue;
    }
    final name = _basename(path);
    if (name == 'README.md' || name == 'CLAUDE.md') continue;
    for (final token in _fullWidthPunctuation) {
      if (name.contains(token)) {
        issues.add('${file.path}: full-width punctuation in filename');
        break;
      }
    }
    if (name.contains(' ')) {
      issues.add('${file.path}: space in filename');
    }
  }
}

void _checkBanners(List<File> files, List<String> issues) {
  for (final file in files) {
    final path = _posix(file.path);
    if (_isBannerExempt(path)) continue;
    final firstLines = _read(file).split('\n').take(16).join('\n');
    if (!firstLines.contains('> 状态：')) {
      issues.add('${file.path}: missing status banner ("> 状态：")');
    }
  }
}

void _checkVersionLabels(List<File> files, List<String> issues) {
  final phase = RegExp(r'\bPhase\s+\d');
  final refactor = RegExp(r'\bPhase\s+1[a-d]\b');
  final priority = RegExp(r'\bP[0-2]\b');
  final wave = RegExp(r'\bWave\s+\d');
  final bareP68 = RegExp(r'P6\.8(?!-lite|（完整）)');
  final bareP7 = RegExp(r'P7(?![.\-（）])');

  for (final file in files) {
    final path = _posix(file.path);
    if (path == 'docs/07-维护/版本命名.md' ||
        path.endsWith('Review目标.txt') ||
        path.endsWith('_sample.md')) {
      continue;
    }
    final isChineseCurrent = path == 'CLAUDE.md' ||
        _chineseCurrentDirs.any((dir) => path.startsWith('$dir/'));
    if (!isChineseCurrent) continue;
    final isFeedbackDoc = path.endsWith('/设备反馈-2026-10-31.md');
    final lines = _read(file).split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (phase.hasMatch(line)) {
        issues.add('${file.path}:${i + 1} use 阶段 N instead of Phase N');
      }
      if (refactor.hasMatch(line)) {
        issues.add('${file.path}:${i + 1} use R1a–R4 instead of Phase 1a–d');
      }
      if (priority.hasMatch(line)) {
        issues.add('${file.path}:${i + 1} use 优先级/批次 instead of P0/P1/P2');
      }
      if (!isFeedbackDoc && wave.hasMatch(line)) {
        issues.add('${file.path}:${i + 1} use 反馈波次 N outside the feedback doc');
      }
      if (bareP68.hasMatch(line)) {
        issues.add('${file.path}:${i + 1} qualify P6.8 as P6.8-lite or P6.8（完整）');
      }
      if (bareP7.hasMatch(line)) {
        issues.add('${file.path}:${i + 1} qualify P7 as P7-lite, P7.x or P7（完整）');
      }
    }
  }
}

String _read(File file) => file.readAsStringSync();

String _posix(String path) => path.replaceAll('\\', '/');

String _normalize(String path) {
  final posix = _posix(path);
  final absolute = posix.startsWith('/');
  final parts = posix.split('/');
  final out = <String>[];
  for (final part in parts) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else if (!absolute) {
        out.add('..');
      }
    } else {
      out.add(part);
    }
  }
  final joined = out.join('/');
  if (absolute) return '/$joined';
  return joined.isEmpty ? '.' : joined;
}

String _dirname(String path) {
  final posix = _posix(path);
  final index = posix.lastIndexOf('/');
  if (index < 0) return '.';
  if (index == 0) return '/';
  return posix.substring(0, index);
}

String _basename(String path) {
  final posix = _posix(path);
  final index = posix.lastIndexOf('/');
  return index < 0 ? posix : posix.substring(index + 1);
}

String _relative(String path, String from) {
  final target = _normalize(path).split('/');
  final base = _normalize(from).split('/');
  var common = 0;
  while (common < target.length &&
      common < base.length &&
      target[common] == base[common]) {
    common++;
  }
  final up = List<String>.filled(base.length - common, '..');
  final rest = target.sublist(common);
  final result = <String>[...up, ...rest].join('/');
  return result.isEmpty ? '.' : result;
}
