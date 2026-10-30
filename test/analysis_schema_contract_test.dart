import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/services/agent/analysis_prompts.dart';

void main() {
  test('runtime analysis schema matches the checked-in contract', () {
    final runtime = analysisResponseSchema();
    final docs =
        jsonDecode(
              File(
                'docs/schemas/agent/analysis.v1.schema.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final runtimeRequired = (runtime['required'] as List).cast<String>().toSet();
    final docsRequired = (docs['required'] as List).cast<String>().toSet();
    expect(runtimeRequired, docsRequired);

    final runtimeProperties = (runtime['properties'] as Map).keys
        .cast<String>()
        .toSet();
    final docsProperties = (docs['properties'] as Map).keys
        .cast<String>()
        .toSet();
    expect(runtimeProperties, docsProperties);
    expect(runtimeRequired.contains('schema'), isTrue);
  });
}
