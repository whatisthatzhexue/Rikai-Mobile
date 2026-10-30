import 'package:flutter/material.dart';

import '../../core/models/agent/agent_evidence.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_run.dart';
import '../../services/agent/familiarization/dictionary_familiarization_service.dart'
    show DictionaryProfileIssue;
import 'agent_result_view.dart';

class AgentEvidencePanel extends StatelessWidget {
  const AgentEvidencePanel({
    super.key,
    required this.result,
    required this.onCitationTap,
    required this.onRetryProfile,
  });

  final AgentRunResult result;
  final ValueChanged<AgentCitation> onCitationTap;
  final ValueChanged<DictionaryProfileIssue> onRetryProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AgentTokens.evidenceSurface,
        border: Border.all(color: AgentTokens.evidenceBorder),
        borderRadius: BorderRadius.circular(AgentTokens.evidenceRadius),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          title: Text(
            '详细解析 · 依据 ${result.citations.length} 条',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.primary,
            ),
          ),
          children: [
            AgentResultView(
              result: result,
              onCitationTap: onCitationTap,
              onRetryProfile: onRetryProfile,
            ),
          ],
        ),
      ),
    );
  }
}
