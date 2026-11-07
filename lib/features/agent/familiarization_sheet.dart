import 'package:flutter/material.dart';

import '../../core/models/agent/agent_profile.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../services/agent/familiarization/dictionary_familiarization_service.dart';
import '../../services/agent/familiarization/dictionary_profile_markdown.dart';

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
  late final List<DictionaryLanguagePair> _pairs;
  late String _newSource;
  late String _newTarget;

  static const List<String> _commonLanguages = <String>['ja', 'zh', 'en', 'ko'];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMarkdown);
    _pairs = List<DictionaryLanguagePair>.of(widget.profile.languagePairs);
    _newSource = _pairs.isEmpty ? 'ja' : _pairs.first.source;
    _newTarget = _pairs.isEmpty ? 'zh' : _pairs.first.target;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _languageOptions {
    final values = <String>{
      ..._commonLanguages,
      ..._pairs.expand((pair) => <String>[pair.source, pair.target]),
      _newSource,
      _newTarget,
    };
    final extra =
        values.where((code) => !_commonLanguages.contains(code)).toList()
          ..sort();
    return <String>[..._commonLanguages, ...extra];
  }

  bool get _pairsChanged {
    if (_pairs.length != widget.profile.languagePairs.length) return true;
    for (var index = 0; index < _pairs.length; index++) {
      final before = widget.profile.languagePairs[index];
      final after = _pairs[index];
      if (before.source != after.source || before.target != after.target) {
        return true;
      }
    }
    return false;
  }

  void _addPair() {
    if (_pairs.any(
      (pair) => pair.source == _newSource && pair.target == _newTarget,
    )) {
      return;
    }
    setState(() {
      _pairs.add(
        DictionaryLanguagePair(
          source: _newSource,
          target: _newTarget,
          confidence: 1,
        ),
      );
    });
  }

  void _finish(ProfileConfirmationAction action) {
    final updatedProfile = widget.profile.copyWith(
      languagePairs: List<DictionaryLanguagePair>.unmodifiable(_pairs),
    );
    final markdown = _pairsChanged
        ? updateLanguagePairsMarkdown(
            _controller.text.trim(),
            updatedProfile,
            AgentProfileLanguage.fromWire(updatedProfile.language),
          )
        : _controller.text.trim();
    Navigator.of(context).pop(
      ProfileConfirmation(
        action: action,
        markdown: markdown,
        profile: updatedProfile,
      ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.strings.profileLanguagePairsTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: AgentTokens.evidenceTitle,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  widget.strings.profileLanguagePairsHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AgentTokens.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (_pairs.isEmpty)
                  Text(
                    widget.strings.profileLanguagePairsEmpty,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AgentTokens.helper,
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final pair in _pairs)
                        InputChip(
                          label: Text(
                            '${widget.strings.languageLabel(pair.source)} → '
                            '${widget.strings.languageLabel(pair.target)}',
                          ),
                          deleteButtonTooltipMessage: widget.strings.delete,
                          onDeleted: () => setState(() => _pairs.remove(pair)),
                        ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _languageOptions.contains(_newSource)
                            ? _newSource
                            : null,
                        decoration: InputDecoration(
                          labelText: widget.strings.profileLanguagePairSource,
                          isDense: true,
                        ),
                        items: <DropdownMenuItem<String>>[
                          for (final code in _languageOptions)
                            DropdownMenuItem<String>(
                              value: code,
                              child: Text(widget.strings.languageLabel(code)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _newSource = value);
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _languageOptions.contains(_newTarget)
                            ? _newTarget
                            : null,
                        decoration: InputDecoration(
                          labelText: widget.strings.profileLanguagePairTarget,
                          isDense: true,
                        ),
                        items: <DropdownMenuItem<String>>[
                          for (final code in _languageOptions)
                            DropdownMenuItem<String>(
                              value: code,
                              child: Text(widget.strings.languageLabel(code)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _newTarget = value);
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(
                      tooltip: widget.strings.profileLanguagePairAdd,
                      onPressed: _addPair,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
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
                            onPressed: () => _finish(
                              ProfileConfirmationAction.saveAndNeverAsk,
                            ),
                            child: Text(
                              widget.strings.decline,
                              textAlign: TextAlign.center,
                            ),
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
