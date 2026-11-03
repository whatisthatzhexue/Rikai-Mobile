import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/agent/agent_tool.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/no_scrollbar_behavior.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/agent/agent_result_markdown.dart';
import '../../services/agent/agent_run.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../state/agent_ocr_variants.dart';
import 'agent_actions.dart';
import 'agent_evidence_panel.dart';
import 'agent_message_widgets.dart';
import 'agent_ocr_variants_panel.dart';

class AgentMessageList extends ConsumerWidget {
  const AgentMessageList({
    super.key,
    required this.scrollController,
    required this.providers,
    required this.provider,
    required this.run,
    required this.onRetry,
    required this.onLooseRetry,
    required this.onRegenerate,
    required this.onEditMessage,
    this.onGenerateOcrVariants,
    this.onReanalyzeOcrVariant,
  });

  final ScrollController scrollController;
  final List<AgentProviderConfig> providers;
  final AgentProviderConfig? provider;
  final AgentRunSnapshot run;
  final VoidCallback onRetry;
  final VoidCallback onLooseRetry;
  final VoidCallback onRegenerate;
  final VoidCallback onEditMessage;
  final Future<void> Function(AgentRunResult result, String imageId)?
  onGenerateOcrVariants;
  final void Function(
    AgentRunResult result,
    String imageId,
    AgentOcrVariant variant,
  )?
  onReanalyzeOcrVariant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final result = run.result ?? run.provisionalResult ?? run.retainedResult;
    final provisional = run.result == null && run.provisionalResult != null;
    if (kDebugMode && run.result != null) {
      _logResultFrame(run, provisional: false);
    } else if (kDebugMode && run.provisionalResult != null) {
      _logResultFrame(run, provisional: true);
    }
    final uiLanguage = resolveAgentUiLanguage(run.responseLanguage);
    final strings = AgentUiStrings.of(uiLanguage);
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
              strings: strings,
            ),
          if (run.pendingProfileCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                strings.pendingProfiles(run.pendingProfileCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.warning,
                ),
              ),
            ),
          if (run.sentText.isNotEmpty || run.sentImage)
            AgentUserBubble(
              text: run.sentText,
              hasImage: run.sentImage,
              imagePaths: run.sentImagePaths,
              strings: strings,
              onLongPress: run.sentText.isEmpty
                  ? null
                  : () => _showUserMessageActions(
                      context,
                      run.sentText,
                      strings,
                      onEditMessage,
                    ),
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
              provisional: provisional,
              cancelled: run.status == AgentRunStatus.cancelled,
              error: run.errorMessage == null
                  ? null
                  : strings.errorMessageFor(run.errorCode, run.errorMessage!),
              errorDetail: run.errorDetail,
              stageMessage: run.stageMessage,
              startedAt: run.startedAt,
              finishedAt: run.finishedAt,
              progressStep: run.progressStep,
              evidenceCount: run.evidenceCount,
              citationCount: run.citationCount,
              maxEvidenceEntries: run.evidenceLimit,
              uiLanguage: uiLanguage,
              strings: strings,
              result: result,
              resultRetainedAfterFailure: run.resultRetainedAfterFailure,
              onRetry: providers.isEmpty ? null : onRetry,
              onLooseRetry:
                  providers.isNotEmpty &&
                      run.mode == AgentMode.strict &&
                      run.errorCode == AgentToolErrorCode.validationFailed
                  ? onLooseRetry
                  : null,
              onSettings: () => context.push('/agent-settings'),
              onRegenerate: run.result == null || providers.isEmpty
                  ? null
                  : onRegenerate,
              onCopy: run.result == null
                  ? null
                  : () => _copyResult(context, run.result!, strings),
            ),
          if (result != null)
            AgentEvidencePanel(
              result: result,
              strings: strings,
              onCitationTap: (citation) =>
                  unawaited(openAgentCitation(context, ref, citation)),
              onRetryProfile: (issue) async {
                final selectedProvider = provider;
                if (selectedProvider == null) {
                  RikaiToast.show(context, strings.modelRequired);
                  return;
                }
                await retryAgentDictionaryProfile(
                  context,
                  ref,
                  issue,
                  selectedProvider,
                );
              },
            ),
          if (result != null &&
              result.input.sources.any((source) => source.isImage))
            AgentOcrVariantsPanel(
              result: result,
              variantsState: ref.watch(agentOcrVariantsProvider),
              strings: strings,
              imagePaths: run.sentImagePaths,
              onGenerate: run.isRunning || onGenerateOcrVariants == null
                  ? null
                  : (imageId) =>
                        unawaited(onGenerateOcrVariants!(result, imageId)),
              onCancelGenerate: (imageId) => ref
                  .read(agentOcrVariantsProvider.notifier)
                  .cancelImage(imageId),
              onReanalyze: run.isRunning || onReanalyzeOcrVariant == null
                  ? null
                  : (imageId, variant) =>
                        onReanalyzeOcrVariant!(result, imageId, variant),
            ),
        ],
      ),
    );
  }

  Future<void> _showUserMessageActions(
    BuildContext context,
    String text,
    AgentUiStrings strings,
    VoidCallback onEdit,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                strings.userMessageMenu,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: AgentTokens.evidenceTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined, size: AppSizes.icon),
              title: Text(strings.copy),
              onTap: () => Navigator.of(context).pop('copy'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: AppSizes.icon),
              title: Text(strings.edit),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) RikaiToast.show(context, strings.copyDone);
    } else if (action == 'edit') {
      onEdit();
    }
  }

  Future<void> _copyResult(
    BuildContext context,
    AgentRunResult result,
    AgentUiStrings strings,
  ) async {
    final markdown = buildAgentResultMarkdown(result, strings);
    await Clipboard.setData(ClipboardData(text: markdown));
    if (context.mounted) RikaiToast.show(context, strings.copyDone);
  }
}

final Set<String> _loggedResultFrames = <String>{};

/// Logs the first frame that contains a result/provisional result. The
/// timestamp starts when the controller published that state, so the number
/// isolates state→frame latency from provider/validation time.
void _logResultFrame(AgentRunSnapshot run, {required bool provisional}) {
  final key = '${run.runId}:${provisional ? 'provisional' : 'final'}';
  if (!_loggedResultFrames.add(key)) return;
  final since = provisional ? run.updatedAt : run.finishedAt;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!kDebugMode || since == null) return;
    debugPrint(
      '[AgentTiming] ui_${provisional ? 'provisional' : 'result'}_frame '
      'latency=${DateTime.now().difference(since).inMilliseconds}ms',
    );
  });
}
