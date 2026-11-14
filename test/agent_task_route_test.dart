import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_provider.dart';
import 'package:lexicandy/services/agent/agent_task_route.dart';

const _provider = AgentProviderConfig(
  id: 'p1',
  kind: AgentProviderKind.openAiCompatible,
  displayName: 'Test',
  baseUrl: 'https://example.com/v1',
  smallModel: 'small',
  complexModel: 'complex',
);

void main() {
  test('routes analysis and language repair to complex', () {
    expect(
      AgentTaskRoute.resolve(AgentTaskKind.analysis, _provider).model,
      'complex',
    );
    expect(
      AgentTaskRoute.resolve(AgentTaskKind.languageRepair, _provider).model,
      'complex',
    );
  });

  test('routes coverage, repair, formatting and provider test to small', () {
    for (final kind in <AgentTaskKind>[
      AgentTaskKind.coverage,
      AgentTaskKind.repair,
      AgentTaskKind.richText,
      AgentTaskKind.providerTest,
    ]) {
      expect(AgentTaskRoute.resolve(kind, _provider).model, 'small');
    }
  });

  test('empty model fields fall back to the configured model', () {
    final complexOnly = _provider.copyWith(smallModel: '');
    final smallOnly = _provider.copyWith(complexModel: '');

    expect(
      AgentTaskRoute.resolve(AgentTaskKind.coverage, complexOnly).model,
      'complex',
    );
    expect(
      AgentTaskRoute.resolve(AgentTaskKind.analysis, complexOnly).model,
      'complex',
    );
    expect(
      AgentTaskRoute.resolve(AgentTaskKind.analysis, smallOnly).model,
      'small',
    );
    expect(
      AgentTaskRoute.resolve(AgentTaskKind.richText, smallOnly).model,
      'small',
    );
  });
}
