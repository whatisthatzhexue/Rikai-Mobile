// Local verification gate for LexiCandy.
//
// Usage (from the repository root):
//   dart tool/verify.dart            # docs + app analyze + app test
//   dart tool/verify.dart --build    # also build a debug APK
//
// Pure dart:io. Flutter commands run with `workingDirectory: app`; this file
// only orchestrates and does not contain app/business logic.

import 'dart:io';

void main(List<String> args) {
  final build = args.contains('--build');
  final failures = <String>[];

  const fontFiles = <String>[
    'app/assets/fonts/KiyosunaSans/KiyosunaSans-L-1.0.1.otf',
    'app/assets/fonts/KiyosunaSans/KiyosunaSans-B-1.0.1.otf',
  ];
  for (final font in fontFiles) {
    if (!File(font).existsSync()) {
      stderr.writeln('Missing $font; see app/assets/fonts/KiyosunaSans/README.md.');
      exit(1);
    }
  }
  if (!File('app/android/local.properties').existsSync()) {
    stderr.writeln(
      'Missing app/android/local.properties; run `flutter pub get` in app/ first.',
    );
    exit(1);
  }

  _run(
    'docs',
    Platform.resolvedExecutable,
    <String>['tool/check_docs.dart'],
    failures,
  );
  _run(
    'analyze',
    'flutter',
    <String>['analyze'],
    failures,
    workingDirectory: 'app',
  );
  _run(
    'test',
    'flutter',
    <String>['test'],
    failures,
    workingDirectory: 'app',
  );
  if (build) {
    _run(
      'build',
      'flutter',
      <String>['build', 'apk', '--debug'],
      failures,
      workingDirectory: 'app',
    );
  }

  if (failures.isEmpty) {
    stdout.writeln('verify passed${build ? ' (with build)' : ''}.');
    return;
  }
  stderr.writeln('verify failed: ${failures.join(', ')}');
  exit(1);
}

void _run(
  String label,
  String executable,
  List<String> args,
  List<String> failures, {
  String? workingDirectory,
}) {
  stdout.writeln('==> $label: $executable ${args.join(' ')}');
  final result = Process.runSync(
    executable,
    args,
    workingDirectory: workingDirectory,
    runInShell: true,
    stdoutEncoding: systemEncoding,
    stderrEncoding: systemEncoding,
  );
  final out = (result.stdout as String).trim();
  final err = (result.stderr as String).trim();
  if (out.isNotEmpty) stdout.writeln(out);
  if (err.isNotEmpty) stderr.writeln(err);
  if (result.exitCode != 0) failures.add('$label (exit ${result.exitCode})');
}
