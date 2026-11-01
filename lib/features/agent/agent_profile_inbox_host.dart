import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/rikai_toast.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../services/agent/familiarization/dictionary_familiarization_service.dart';
import '../../state/agent_profile_inbox.dart';
import '../../state/providers.dart';
import 'familiarization_sheet.dart';

enum AgentProfilePresentationResult { resolved, dismissed, busy, empty }

/// The single confirmation flow shared by the Agent page, the profile manager
/// and any other Agent subpage. It reuses the app-level inbox; callers must not
/// duplicate the sheet/queue logic.
Future<AgentProfilePresentationResult> presentAgentProfileConfirmation(
  BuildContext context,
  WidgetRef ref,
  AgentUiStrings strings, {
  AgentProfileProposal? proposal,
}) async {
  final state = ref.read(agentProfileInboxProvider);
  final target = proposal ?? state.first;
  if (target == null || !state.pending.any((item) => item.id == target.id)) {
    return AgentProfilePresentationResult.empty;
  }
  final inbox = ref.read(agentProfileInboxProvider.notifier);
  if (!inbox.tryClaimPresentation()) {
    return AgentProfilePresentationResult.busy;
  }
  final settings = ref.read(appSettingsProvider.notifier);
  try {
    if (!context.mounted) {
      return AgentProfilePresentationResult.dismissed;
    }
    final decision = await showFamiliarizationSheet(
      context,
      profile: target.profile,
      markdown: target.markdown,
      strings: strings,
    );
    if (decision == null) {
      return AgentProfilePresentationResult.dismissed;
    }
    if (decision.action == ProfileConfirmationAction.saveAndNeverAsk) {
      settings.setAgentProfilesAutoAccept(true);
    }
    await inbox.resolve(target.id, decision);
    if (decision.action == ProfileConfirmationAction.saveAndNeverAsk &&
        context.mounted) {
      RikaiToast.show(context, strings.profileGenerated(target.title));
    }
    return AgentProfilePresentationResult.resolved;
  } finally {
    inbox.releasePresentation();
  }
}

/// Headless queue presenter. Place it on every Agent surface that may show a
/// profile confirmation. The inbox's claim guard ensures only one host presents
/// the same proposal, even when a subpage is pushed over the Agent page.
class AgentProfileInboxHost extends ConsumerStatefulWidget {
  const AgentProfileInboxHost({
    super.key,
    required this.strings,
    required this.child,
  });

  final AgentUiStrings strings;
  final Widget child;

  @override
  ConsumerState<AgentProfileInboxHost> createState() =>
      _AgentProfileInboxHostState();
}

class _AgentProfileInboxHostState extends ConsumerState<AgentProfileInboxHost> {
  String? _dismissedId;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_presentNext());
    });
  }

  Future<void> _presentNext() async {
    if (!mounted) return;
    final proposal = ref.read(agentProfileInboxProvider).first;
    if (proposal == null || proposal.id == _dismissedId) return;
    final result = await presentAgentProfileConfirmation(
      context,
      ref,
      widget.strings,
      proposal: proposal,
    );
    if (!mounted) return;
    if (result == AgentProfilePresentationResult.dismissed) {
      // A dismissed sheet stays pending, but must not immediately reopen in
      // a loop. It is shown again on the next page entry or queue change.
      _dismissedId = proposal.id;
      return;
    }
    if (result == AgentProfilePresentationResult.resolved) {
      _dismissedId = null;
      _schedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(agentProfileInboxProvider, (previous, next) {
      if (next.pending.isEmpty) {
        _dismissedId = null;
        return;
      }
      if (next.pending.first.id != _dismissedId) _schedule();
    });
    return widget.child;
  }
}
