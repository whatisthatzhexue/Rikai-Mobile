import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rikai_ocr/rikai_ocr.dart' show OcrMode;

import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_limits.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/dict_info.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/agent/agent_run.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../state/agent_dictionary_preferences.dart';
import '../../state/agent_ocr_variants.dart';
import '../../state/agent_providers.dart';
import '../../state/agent_run_controller.dart';
import '../../state/providers.dart';
import 'agent_composer.dart';
import 'agent_message_list.dart';
import 'agent_profile_inbox_host.dart';
import 'agent_session_panel.dart';

class AgentPage extends ConsumerStatefulWidget {
  const AgentPage({super.key});

  @override
  ConsumerState<AgentPage> createState() => _AgentPageState();
}

class _PickedImage {
  const _PickedImage({required this.id, required this.path});

  final String id;
  final String path;
}

class _AgentPageState extends ConsumerState<AgentPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _messagesScroll = ScrollController();
  late final AgentRunController _runController;
  AgentMode _mode = AgentMode.strict;
  List<_PickedImage> _images = <_PickedImage>[];
  bool _settingsExpanded = false;
  int _imageSerial = 0;
  String? _dismissedBeautifyRunId;

  @override
  void initState() {
    super.initState();
    _runController = ref.read(agentRunControllerProvider.notifier);
    // Strict/loose is a session-level snapshot: re-entering the page keeps the
    // mode selected for this session (including an unused selection), while a
    // new session resets it to strict.
    _mode = _runController.sessionMode;
  }

  @override
  void dispose() {
    // Leaving the page only unsubscribes; the run and profile inbox keep going
    // at application scope.
    _input.dispose();
    _inputFocus.dispose();
    _messagesScroll.dispose();
    super.dispose();
  }

  AgentUiStrings _stringsFor(
    AgentRunSnapshot run,
    AgentResponseLanguage setting,
  ) {
    final language = run.hasConversation ? run.responseLanguage : setting;
    return AgentUiStrings.of(resolveAgentUiLanguage(language));
  }

  List<DictionaryInfo> _selectedDictionaries(
    List<DictionaryInfo> enabled,
    AgentDictionaryPreferences preferences,
  ) => preferences.selectedDictionaries(enabled);

  AgentProviderConfig? _provider(
    List<AgentProviderConfig> providers,
    String? selectedId,
  ) {
    if (providers.isEmpty) return null;
    for (final provider in providers) {
      if (provider.id == selectedId) return provider;
    }
    return providers.first;
  }

  Future<void> _showImageSourceMenu(AgentUiStrings strings) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                size: AppSizes.icon,
              ),
              title: Text(strings.takePhoto),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                size: AppSizes.icon,
              ),
              title: Text(strings.chooseFromGallery),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    await _pickImages(fromCamera: source == 'camera', strings: strings);
  }

  Future<void> _pickImages({
    required bool fromCamera,
    required AgentUiStrings strings,
  }) async {
    final limit = AgentLimits.standard.maxImagesPerRun;
    final remaining = limit - _images.length;
    if (remaining <= 0) {
      RikaiToast.show(context, strings.imageLimitReached(limit));
      return;
    }
    try {
      final picker = ref.read(agentImagePickerProvider);
      final picked = fromCamera
          ? await picker.pickFromCamera()
          : await picker.pickFromGallery();
      if (!mounted || picked.isEmpty) return;
      final accepted = picked.take(remaining).toList(growable: false);
      setState(() {
        for (final path in accepted) {
          _imageSerial++;
          _images.add(_PickedImage(id: 'local-$_imageSerial', path: path));
        }
      });
      if (picked.length > remaining) {
        RikaiToast.show(context, strings.imageLimitReached(limit));
      }
    } catch (_) {
      if (mounted) RikaiToast.show(context, strings.pickImageFailed);
    }
  }

  void _removeImage(String path) {
    setState(() {
      final next = <_PickedImage>[..._images];
      final index = next.indexWhere((image) => image.path == path);
      if (index >= 0) next.removeAt(index);
      _images = next;
    });
  }

  Future<void> _send() async {
    final run = ref.read(agentRunControllerProvider);
    if (run.isRunning) return;
    final settings = ref.read(appSettingsProvider);
    final strings = _stringsFor(
      run,
      AgentResponseLanguage.fromWire(settings.agentResponseLanguage),
    );
    if (ref.read(agentOcrVariantsProvider).loading) {
      RikaiToast.show(context, strings.ocrVariantsLoading);
      return;
    }
    FocusScope.of(context).unfocus();
    final text = _input.text.trim();
    final imagePaths = _images.map((image) => image.path).toList();
    if (text.isEmpty && imagePaths.isEmpty) {
      RikaiToast.show(context, strings.inputRequired);
      return;
    }
    final enabled = ref.read(enabledDictionariesProvider);
    final preferences = ref.read(agentDictionaryPreferencesProvider);
    final dictionaries = _selectedDictionaries(enabled, preferences);
    if (dictionaries.isEmpty) {
      RikaiToast.show(context, strings.dictionaryRequired);
      return;
    }
    final providers =
        ref.read(agentProvidersProvider).asData?.value ??
        const <AgentProviderConfig>[];
    final provider = _provider(
      providers,
      ref.read(selectedAgentProviderProvider),
    );
    if (provider == null) {
      RikaiToast.show(context, strings.modelRequired);
      return;
    }
    final started = _runController.start(
      userText: text,
      images: <AgentImageInput>[
        for (var index = 0; index < imagePaths.length; index++)
          AgentImageInput(
            id: 'local-${index + 1}',
            localPath: imagePaths[index],
          ),
      ],
      dictionaries: dictionaries,
      provider: provider,
      mode: _mode,
      unidicPath: settings.unidicPath,
      responseLanguage: AgentResponseLanguage.fromWire(
        settings.agentResponseLanguage,
      ),
      profileLanguage: AgentProfileLanguage.fromWire(
        settings.agentProfileLanguage,
      ),
    );
    // A request only leaves the composer after the controller accepted it.
    if (ref.read(agentRunControllerProvider).isRunning) {
      ref.read(agentOcrVariantsProvider.notifier).clear();
      setState(() {
        _input.clear();
        _images = <_PickedImage>[];
        _settingsExpanded = false;
      });
    }
    unawaited(started);
  }

  void _retry() {
    unawaited(_runController.retry());
  }

  void _retryLoose() {
    _runController.setSessionMode(AgentMode.loose);
    setState(() => _mode = AgentMode.loose);
    unawaited(_runController.retry(mode: AgentMode.loose));
  }

  void _regenerate() {
    unawaited(_runController.regenerate());
  }

  /// Local input images for the current result, or for the failed run when no
  /// result exists. Order matches `sentImagePaths` so thumbnails stay aligned.
  List<AgentImageInput> _baseImages(
    AgentRunResult? result,
    AgentRunSnapshot run,
  ) {
    final lastImages = _runController.lastImages;
    if (result == null) return lastImages;
    final images = <AgentImageInput>[];
    var index = 0;
    for (final source in result.input.sources) {
      if (!source.isImage) continue;
      final lastImage = index < lastImages.length ? lastImages[index] : null;
      final localPath = index < run.sentImagePaths.length
          ? run.sentImagePaths[index]
          : lastImage?.localPath ?? '';
      images.add(
        AgentImageInput(
          id: source.imageId ?? lastImage?.id ?? 'img-${index + 1}',
          localPath: localPath,
          mode: source.selectedVariant?.mode ?? lastImage?.mode ?? OcrMode.auto,
          variants: source.variants,
          selectedVariantId:
              source.selectedVariantId ?? lastImage?.selectedVariantId,
        ),
      );
      index++;
    }
    return images;
  }

  Future<void> _generateOcrVariants(String imageId) async {
    final run = ref.read(agentRunControllerProvider);
    if (run.isRunning) return;
    final result = run.result ?? run.provisionalResult ?? run.retainedResult;
    final images = _baseImages(result, run);
    AgentImageInput? target;
    for (final image in images) {
      if (image.id == imageId) {
        target = image;
        break;
      }
    }
    if (target == null || target.localPath.isEmpty) return;
    try {
      if (!File(target.localPath).existsSync()) return;
    } catch (_) {
      return;
    }
    final baselineVariants = target.variants.isEmpty
        ? const <String, List<AgentOcrVariant>>{}
        : <String, List<AgentOcrVariant>>{imageId: target.variants};
    final List<DictionaryInfo> dictionaries;
    if (result != null) {
      final enabled = ref.read(enabledDictionariesProvider);
      final preferences = ref.read(agentDictionaryPreferencesProvider);
      final runDictionaryIds = result.input.dictionaries
          .map((dictionary) => dictionary.id)
          .toSet();
      dictionaries = _selectedDictionaries(enabled, preferences)
          .where((dictionary) => runDictionaryIds.contains(dictionary.id))
          .toList(growable: false);
    } else {
      dictionaries = _runController.lastDictionaries;
    }
    await ref
        .read(agentOcrVariantsProvider.notifier)
        .generate(
          images: <AgentImageInput>[target],
          baselineVariants: baselineVariants,
          dictionaries: dictionaries,
        );
  }

  void _reanalyzeOcrVariant(String imageId, AgentOcrVariant selected) {
    final run = ref.read(agentRunControllerProvider);
    if (run.isRunning) return;
    final result = run.result ?? run.provisionalResult ?? run.retainedResult;
    final images = _baseImages(result, run);
    if (images.isEmpty) return;
    final variantsState = ref.read(agentOcrVariantsProvider);
    final extras = variantsState.extraVariants;
    final baselines = variantsState.baselineVariants;
    final next = <AgentImageInput>[];
    for (final image in images) {
      final all = <String, AgentOcrVariant>{
        for (final variant in image.variants) variant.id: variant,
        for (final variant in extras[image.id] ?? const <AgentOcrVariant>[])
          variant.id: variant,
        if (baselines[image.id] != null)
          baselines[image.id]!.id: baselines[image.id]!,
      };
      final selectedId = image.id == imageId
          ? selected.id
          : image.selectedVariantId ?? baselines[image.id]?.id;
      if (image.id == imageId) all[selected.id] = selected;
      // Keep the selected variant plus the highest-priority alternatives and
      // stay within the four-variant provider contract.
      final ordered = <AgentOcrVariant>[
        if (selectedId != null && all[selectedId] != null) all[selectedId]!,
        for (final variant in all.values)
          if (variant.id != selectedId) variant,
      ].take(AgentOcrVariant.maxPerSource).toList(growable: false);
      next.add(
        AgentImageInput(
          id: image.id,
          localPath: image.localPath,
          mode: image.mode,
          variants: ordered,
          selectedVariantId: selectedId,
        ),
      );
    }
    unawaited(_runController.reanalyzeWithImages(next));
  }

  void _cancel() {
    _runController.cancel();
  }

  void _newSession() {
    if (ref.read(agentRunControllerProvider).isRunning) return;
    _runController.newSession();
    ref.read(agentOcrVariantsProvider.notifier).clear();
    setState(() {
      _input.clear();
      _images = <_PickedImage>[];
      _mode = AgentMode.strict;
      _settingsExpanded = false;
    });
  }

  void _editCurrentMessage() {
    final run = ref.read(agentRunControllerProvider);
    if (run.sentText.isEmpty) return;
    _input
      ..text = run.sentText
      ..selection = TextSelection.collapsed(offset: run.sentText.length);
    setState(() {
      _images = <_PickedImage>[
        for (var index = 0; index < run.sentImagePaths.length; index++)
          _PickedImage(id: 'edit-$index', path: run.sentImagePaths[index]),
      ];
      _settingsExpanded = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(enabledDictionariesProvider);
    final providersAsync = ref.watch(agentProvidersProvider);
    final providers =
        providersAsync.asData?.value ?? const <AgentProviderConfig>[];
    final provider = _provider(
      providers,
      ref.watch(selectedAgentProviderProvider),
    );
    final preferences = ref.watch(agentDictionaryPreferencesProvider);
    final selectedIds = _selectedDictionaries(
      enabled,
      preferences,
    ).map((dictionary) => dictionary.id).toSet();
    final run = ref.watch(agentRunControllerProvider);
    final settings = ref.watch(appSettingsProvider);
    final strings = _stringsFor(
      run,
      AgentResponseLanguage.fromWire(settings.agentResponseLanguage),
    );
    final running = run.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
        actions: [
          IconButton(
            tooltip: strings.newSession,
            onPressed: running ? null : _newSession,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: strings.profiles,
            onPressed: () => context.push('/agent-profiles'),
            icon: const Icon(Icons.library_books_outlined),
          ),
          IconButton(
            tooltip: strings.history,
            onPressed: () => context.push('/agent-history'),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: strings.settings,
            onPressed: () => context.push('/agent-settings'),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: AgentProfileInboxHost(
        strings: strings,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              buildAgentSessionBar(
                context,
                mode: _mode,
                providerName:
                    provider?.displayName ?? strings.unconfiguredModel,
                expanded: _settingsExpanded,
                strings: strings,
                onToggle: () =>
                    setState(() => _settingsExpanded = !_settingsExpanded),
              ),
              if (_settingsExpanded)
                buildAgentSessionPanel(
                  context,
                  providers: providers,
                  provider: provider,
                  mode: _mode,
                  enabled: enabled,
                  selectedIds: selectedIds,
                  selectionMode: preferences.mode,
                  running: running,
                  strings: strings,
                  onProviderChanged: (value) => ref
                      .read(selectedAgentProviderProvider.notifier)
                      .select(value),
                  onModeChanged: (value) {
                    _runController.setSessionMode(value);
                    setState(() => _mode = value);
                  },
                  onSelectionModeChanged: (value) => ref
                      .read(agentDictionaryPreferencesProvider.notifier)
                      .setMode(value),
                  onToggleDictionary: (id) => ref
                      .read(agentDictionaryPreferencesProvider.notifier)
                      .toggle(id, enabled),
                  onSelectAll: () => ref
                      .read(agentDictionaryPreferencesProvider.notifier)
                      .selectAll(),
                  onOpenSettings: () => context.push('/agent-settings'),
                ),
              if (run.richTextFormatting &&
                  run.runId != null &&
                  _dismissedBeautifyRunId != run.runId)
                _BeautifyBanner(
                  strings: strings,
                  onClose: () =>
                      setState(() => _dismissedBeautifyRunId = run.runId),
                ),
              Expanded(
                child: AgentMessageList(
                  scrollController: _messagesScroll,
                  providers: providers,
                  provider: provider,
                  run: run,
                  onRetry: _retry,
                  onLooseRetry: _retryLoose,
                  onRegenerate: _regenerate,
                  onEditMessage: _editCurrentMessage,
                  onGenerateOcrVariants: _generateOcrVariants,
                  onReanalyzeOcrVariant: _reanalyzeOcrVariant,
                ),
              ),
              buildAgentComposer(
                context,
                controller: _input,
                focusNode: _inputFocus,
                imagePaths: _images.map((image) => image.path).toList(),
                running: running,
                canSend: providers.isNotEmpty,
                strings: strings,
                onPickImage: () => _showImageSourceMenu(strings),
                onRemoveImage: _removeImage,
                onSend: _send,
                onStop: _cancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dismissible progress banner for the post-result rich-text beautification
/// agent. The core result is already usable; the banner only explains why the
/// displayed formatting may still change. It is removed automatically when the
/// controller reports that the formatting pass has finished.
class _BeautifyBanner extends StatelessWidget {
  const _BeautifyBanner({required this.strings, required this.onClose});

  final AgentUiStrings strings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          0,
        ),
        padding: const EdgeInsets.only(
          left: AppSpacing.md,
          top: AppSpacing.xxs,
          bottom: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: AgentTokens.beautifyBannerSurface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome,
              size: AppSizes.iconSmall,
              color: AgentTokens.beautifyBannerText,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                strings.beautifyingInProgress,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.helper,
                  fontWeight: FontWeight.w500,
                  color: AgentTokens.beautifyBannerText,
                ),
              ),
            ),
            IconButton(
              tooltip: strings.close,
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
              color: AgentTokens.beautifyBannerText,
              icon: const Icon(Icons.close, size: AgentTokens.actionIcon),
            ),
          ],
        ),
      ),
    );
  }
}
