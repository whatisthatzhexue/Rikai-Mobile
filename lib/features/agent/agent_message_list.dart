import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/agent/agent_tool.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/no_scrollbar_behavior.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/agent/agent_messages.dart';
import '../../services/agent/agent_run.dart';
import 'agent_actions.dart';
import 'agent_evidence_panel.dart';
import 'agent_message_widgets.dart';

void scrollAgentToBottom(ScrollController controller, bool mounted) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !controller.hasClients) return;
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  });
}

class AgentMessageList extends ConsumerWidget {
  const AgentMessageList({
    super.key,
    required this.scrollController,
    required this.providers,
    required this.provider,
    required this.run,
    required this.onRetry,
    required this.onLooseRetry,
  });

  final ScrollController scrollController;
  final List<AgentProviderConfig> providers;
  final AgentProviderConfig? provider;
  final AgentRunSnapshot run;
  final VoidCallback onRetry;
  final VoidCallback onLooseRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final result = run.result;
    final uiLanguage = resolveAgentUiLanguage(
      run.responseLanguage,
      run.sentText,
    );
    return ScrollConfiguration(
      behavior: const NoScrollbarBehavior(),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          if (!run.hasConversation)
            AgentEmptyState(
              hasProvider: providers.isNotEmpty,
              onSettings: () => context.push('/agent-settings'),
            ),
          if (run.sentText.isNotEmpty || run.sentImage)
            AgentUserBubble(
              text: run.sentText,
              hasImage: run.sentImage,
              imagePaths: run.sentImagePaths,
            ),
          if (run.isRunning ||
              result != null ||
              run.errorMessage != null ||
              run.status == AgentRunStatus.cancelled)
            AgentAssistantBubble(
              theme: theme,
              providerLabel: run.providerLabel,
              mode: run.mode,
              running: run.isRunning,
              cancelled: run.status == AgentRunStatus.cancelled,
              error: run.errorMessage,
              errorDetail: run.errorDetail,
              stageMessage: run.stageMessage,
              startedAt: run.startedAt,
              finishedAt: run.finishedAt,
              progressStep: run.progressStep,
              evidenceCount: run.evidenceCount,
              citationCount: run.citationCount,
              uiLanguage: uiLanguage,
              result: result,
              onRetry: providers.isEmpty ? null : onRetry,
              onLooseRetry:
                  providers.isNotEmpty &&
                      run.mode == AgentMode.strict &&
                      run.errorCode == AgentToolErrorCode.validationFailed
                  ? onLooseRetry
                  : null,
              onSettings: () => context.push('/agent-settings'),
            ),
          if (result != null)
            AgentEvidencePanel(
              result: result,
              onCitationTap: (citation) =>
                  unawaited(openAgentCitation(context, ref, citation)),
              onRetryProfile: (issue) {
                final selectedProvider = provider;
                if (selectedProvider == null) {
                  RikaiToast.show(context, '请先配置模型');
                  return;
                }
                unawaited(
                  retryAgentDictionaryProfile(
                    context,
                    ref,
                    issue,
                    selectedProvider,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
