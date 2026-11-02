import 'dart:async';

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
  String? _selectedProviderId;
  List<_PickedImage> _images = <_PickedImage>[];
  bool _settingsExpanded = false;
  int _imageSerial = 0;

  @override
  void initState() {
    super.initState();
    _runController = ref.read(agentRunControllerProvider.notifier);
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

  AgentProviderConfig? _provider(List<AgentProviderConfig> providers) {
    if (providers.isEmpty) return null;
    for (final provider in providers) {
      if (provider.id == _selectedProviderId) return provider;
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
    final provider = _provider(providers);
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
    unawaited(_runController.retry(mode: AgentMode.loose));
  }

  void _regenerate() {
    unawaited(_runController.regenerate());
  }

  Future<void> _generateOcrVariants(
    AgentRunResult result,
    String imageId,
  ) async {
    final run = ref.read(agentRunControllerProvider);
    if (run.isRunning || run.sentImagePaths.isEmpty) return;
    AgentSourceInput? target;
    var imageIndex = -1;
    var imageCount = 0;
    for (final source in result.input.sources) {
      if (!source.isImage) continue;
      imageCount++;
      final id = source.imageId ?? source.id;
      if (id == imageId) {
        target = source;
        imageIndex = imageCount - 1;
        break;
      }
    }
    if (target == null) return;
    final localPath = imageIndex < run.sentImagePaths.length
        ? run.sentImagePaths[imageIndex]
        : '';
    final images = <AgentImageInput>[
      AgentImageInput(
        id: imageId,
        localPath: localPath,
        mode: target.selectedVariant?.mode ?? OcrMode.auto,
        selectedVariantId: target.selectedVariantId,
      ),
    ];
    final baselineVariants = <String, List<AgentOcrVariant>>{
      imageId: target.variants,
    };
    final enabled = ref.read(enabledDictionariesProvider);
    final preferences = ref.read(agentDictionaryPreferencesProvider);
    final runDictionaryIds = result.input.dictionaries
        .map((dictionary) => dictionary.id)
        .toSet();
    final dictionaries = _selectedDictionaries(enabled, preferences)
        .where((dictionary) => runDictionaryIds.contains(dictionary.id))
        .toList(growable: false);
    await ref
        .read(agentOcrVariantsProvider.notifier)
        .generate(
          images: images,
          baselineVariants: baselineVariants,
          dictionaries: dictionaries,
        );
  }

  void _reanalyzeOcrVariant(
    AgentRunResult result,
    String imageId,
    AgentOcrVariant selected,
  ) {
    final run = ref.read(agentRunControllerProvider);
    if (run.isRunning) return;
    final extras = ref.read(agentOcrVariantsProvider).extraVariants;
    final images = <AgentImageInput>[];
    var imageIndex = 0;
    for (final source in result.input.sources) {
      if (!source.isImage) continue;
      final id = source.imageId ?? 'img-${imageIndex + 1}';
      final all = <String, AgentOcrVariant>{
        for (final variant in source.variants) variant.id: variant,
        for (final variant in extras[id] ?? const <AgentOcrVariant>[])
          variant.id: variant,
      };
      if (id == imageId) all[selected.id] = selected;
      final localPath = imageIndex < run.sentImagePaths.length
          ? run.sentImagePaths[imageIndex]
          : '';
      images.add(
        AgentImageInput(
          id: id,
          localPath: localPath,
          variants: all.values.toList(growable: false),
          selectedVariantId: id == imageId
              ? selected.id
              : source.selectedVariantId,
        ),
      );
      imageIndex++;
    }
    unawaited(_runController.reanalyzeWithImages(images));
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
    final provider = _provider(providers);
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
            onPressed: () => RikaiToast.show(context, strings.historyPending),
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
                  onProviderChanged: (value) =>
                      setState(() => _selectedProviderId = value),
                  onModeChanged: (value) => setState(() => _mode = value),
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
