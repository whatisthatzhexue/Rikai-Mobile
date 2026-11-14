// Local verification gate for Rikai-Mobile.
//
// Usage:
//   dart tool/verify.dart            # docs + analyze + test
//   dart tool/verify.dart --build    # also build a debug APK
//
// Pure dart:io. Runs check_docs.dart directly (not `dart run`) so the
// mecab_for_dart native build hook is not triggered by the docs script.

import 'dart:io';

void main(List<String> args) {
  final build = args.contains('--build');
  final failures = <String>[];

  if (!File('assets/fonts/HarmonyOS_Sans_SC_Regular.ttf').existsSync()) {
    stderr.writeln(
      'Missing assets/fonts/HarmonyOS_Sans_SC_Regular.ttf; see assets/fonts/README.md.',
    );
    exit(1);
  }
  if (!File('android/local.properties').existsSync()) {
    stderr.writeln('Missing android/local.properties; run `flutter pub get` first.');
    exit(1);
  }

  _run('docs', Platform.resolvedExecutable, <String>['tool/check_docs.dart'], failures);
  _run('analyze', 'flutter', <String>['analyze'], failures);
  _run('test', 'flutter', <String>['test'], failures);
  if (build) {
    _run(
      'build',
      'flutter',
      <String>['build', 'apk', '--debug'],
      failures,
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
  List<String> failures,
) {
  stdout.writeln('==> $label: $executable ${args.join(' ')}');
  final result = Process.runSync(
    executable,
    args,
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
