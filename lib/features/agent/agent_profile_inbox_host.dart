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
    // Saved-profile toasts are emitted by the inbox so manual saves and
    // auto-accept saves share one path; the mounted host listens for them.
    await inbox.resolve(target.id, decision);
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
    this.autoPresent = true,
  });

  final AgentUiStrings strings;
  final Widget child;

  /// When false, pending proposals are counted but no confirmation sheet is
  /// opened automatically. The profile manager still presents them when the
  /// user explicitly opens it.
  final bool autoPresent;

  @override
  ConsumerState<AgentProfileInboxHost> createState() =>
      _AgentProfileInboxHostState();
}

class _AgentProfileInboxHostState extends ConsumerState<AgentProfileInboxHost> {
  String? _dismissedId;
  bool _scheduled = false;
  int _lastSavedNoticeId = 0;

  @override
  void initState() {
    super.initState();
    // Do not replay a save that happened before this surface was mounted.
    _lastSavedNoticeId =
        ref.read(agentProfileInboxProvider).savedNotice?.id ?? 0;
    _schedule();
  }

  void _maybeShowSavedNotice(AgentProfileSavedNotice? notice) {
    if (notice == null || notice.id <= _lastSavedNoticeId) return;
    _lastSavedNoticeId = notice.id;
    if (!mounted) return;
    // Several Agent surfaces can be mounted at once; only the first host
    // handles this notice so the user sees a single toast.
    if (!ref
        .read(agentProfileInboxProvider.notifier)
        .claimSavedNotice(notice.id)) {
      return;
    }
    RikaiToast.show(context, widget.strings.profilesGenerated(notice.titles));
  }

  void _schedule() {
    if (!widget.autoPresent || _scheduled) return;
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
      _maybeShowSavedNotice(next.savedNotice);
      if (next.pending.isEmpty) {
        _dismissedId = null;
        return;
      }
      if (next.pending.first.id != _dismissedId) _schedule();
    });
    return widget.child;
  }
}
