import 'package:flutter/material.dart';

import '../../core/models/agent/agent_profile.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../services/agent/familiarization/dictionary_familiarization_service.dart';

/// Shows the generated dictionary profile and requires explicit confirmation.
Future<ProfileConfirmation?> showFamiliarizationSheet(
  BuildContext context, {
  required DictionaryProfile profile,
  required String markdown,
  required AgentUiStrings strings,
  bool editOnly = false,
}) {
  return showModalBottomSheet<ProfileConfirmation>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    builder: (context) => _FamiliarizationSheet(
      profile: profile,
      initialMarkdown: markdown,
      strings: strings,
      editOnly: editOnly,
    ),
  );
}

class _FamiliarizationSheet extends StatefulWidget {
  const _FamiliarizationSheet({
    required this.profile,
    required this.initialMarkdown,
    required this.strings,
    required this.editOnly,
  });

  final DictionaryProfile profile;
  final String initialMarkdown;
  final AgentUiStrings strings;
  final bool editOnly;

  @override
  State<_FamiliarizationSheet> createState() => _FamiliarizationSheetState();
}

class _FamiliarizationSheetState extends State<_FamiliarizationSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMarkdown);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(ProfileConfirmationAction action) {
    Navigator.of(context).pop(
      ProfileConfirmation(action: action, markdown: _controller.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.strings.profileTitle(widget.profile.title),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: AppTypography.sectionHeading,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.strings.profileSheetBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: AppTypography.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: TextField(
                controller: _controller,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: AgentTokens.body,
                ),
                decoration: InputDecoration(
                  filled: false,
                  hintText: widget.strings.profileHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.editOnly) ...[
                    SizedBox(
                      height: AppSizes.control,
                      child: FilledButton(
                        onPressed: () =>
                            _finish(ProfileConfirmationAction.save),
                        child: Text(widget.strings.save),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(widget.strings.cancel),
                    ),
                  ] else ...[
                    SizedBox(
                      height: AppSizes.control,
                      child: FilledButton(
                        onPressed: () =>
                            _finish(ProfileConfirmationAction.save),
                        child: Text(widget.strings.saveAndTrust),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                _finish(ProfileConfirmationAction.skipOnce),
                            child: Text(widget.strings.skipOnce),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextButton(
                            onPressed: () =>
                                _finish(ProfileConfirmationAction.decline),
                            child: Text(widget.strings.decline),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
