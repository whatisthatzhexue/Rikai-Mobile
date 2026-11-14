import '../../core/models/agent/agent_provider.dart';

/// One logical model task in the fixed Agent pipeline.
enum AgentTaskKind {
  analysis,
  coverage,
  repair,
  languageRepair,
  richText,
  providerTest,
}

/// Resolved model for one task. The orchestrator, not the model, owns routing.
class AgentTaskRoute {
  const AgentTaskRoute({required this.kind, required this.model});

  final AgentTaskKind kind;
  final String model;

  /// Resolves the existing small/complex split without adding any model calls.
  ///
  /// Analysis and language repair use the complex model when configured;
  /// coverage, format repair and display formatting use the small model.
  /// Empty model fields fall back to the other configured model.
  factory AgentTaskRoute.resolve(
    AgentTaskKind kind,
    AgentProviderConfig provider,
  ) {
    final complex = provider.complexModel.trim();
    final small = provider.smallModel.trim();
    final analysisModel = complex.isNotEmpty ? complex : small;
    final smallModel = small.isNotEmpty ? small : complex;
    final model = switch (kind) {
      AgentTaskKind.analysis || AgentTaskKind.languageRepair => analysisModel,
      AgentTaskKind.coverage ||
      AgentTaskKind.repair ||
      AgentTaskKind.richText ||
      AgentTaskKind.providerTest => smallModel,
    };
    return AgentTaskRoute(kind: kind, model: model);
  }
}
