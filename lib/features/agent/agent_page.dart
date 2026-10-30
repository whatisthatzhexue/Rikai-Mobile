import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/dict_info.dart';
import '../../core/models/dictionary_selection.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/agent/agent_run.dart';
import '../../services/agent/familiarization/dictionary_familiarization_service.dart';
import '../../state/agent_providers.dart';
import '../../state/agent_run_controller.dart';
import '../../state/lookup_preferences.dart';
import '../../state/providers.dart';
import 'agent_actions.dart';
import 'agent_composer.dart';
import 'agent_message_list.dart';
import 'agent_session_panel.dart';

class AgentPage extends ConsumerStatefulWidget {
  const AgentPage({super.key});

  @override
  ConsumerState<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends ConsumerState<AgentPage> {
  final TextEditingController _input = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _messagesScroll = ScrollController();
  late final AgentRunController _runController;
  late final ProfileConfirmationCallback _profileHandler;
  Set<String>? _selectedIds;
  DictionarySelectionMode _selectionMode = DictionarySelectionMode.multi;
  AgentMode _mode = AgentMode.strict;
  String? _selectedProviderId;
  String? _imagePath;
  bool _settingsExpanded = false;

  @override
  void initState() {
    super.initState();
    _runController = ref.read(agentRunControllerProvider.notifier);
    _profileHandler = (profile, markdown) =>
        confirmAgentProfile(context, profile, markdown);
    _runController.attachProfileHandler(_profileHandler);
    final enabled = ref.read(enabledDictionariesProvider);
    final preferences = ref.read(lookupPreferencesProvider);
    _selectedIds = preferences
        .selectedDictionaries(enabled)
        .map((dictionary) => dictionary.id)
        .toSet();
    _selectionMode = preferences.mode;
  }

  @override
  void dispose() {
    // Leaving the page only unsubscribes; the run keeps going at app scope.
    _runController.detachProfileHandler(_profileHandler);
    _input.dispose();
    _messagesScroll.dispose();
    super.dispose();
  }

  List<DictionaryInfo> _selectedDictionaries(List<DictionaryInfo> enabled) {
    final ids = _selectedIds;
    if (ids == null) return enabled;
    return enabled
        .where((dictionary) => ids.contains(dictionary.id))
        .toList(growable: false);
  }

  AgentProviderConfig? _provider(List<AgentProviderConfig> providers) {
    if (providers.isEmpty) return null;
    for (final provider in providers) {
      if (provider.id == _selectedProviderId) return provider;
    }
    return providers.first;
  }

  void _toggleDictionary(String id, List<DictionaryInfo> enabled) {
    final current = _selectedIds ?? enabled.map((item) => item.id).toSet();
    final next = <String>{...current};
    if (_selectionMode == DictionarySelectionMode.single) {
      next
        ..clear()
        ..add(id);
    } else if (!next.add(id)) {
      next.remove(id);
    }
    setState(() => _selectedIds = next);
  }

  void _selectAll(List<DictionaryInfo> enabled) {
    setState(() {
      _selectedIds = enabled.map((dictionary) => dictionary.id).toSet();
    });
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      setState(() => _imagePath = file.path);
    } catch (_) {
      if (mounted) RikaiToast.show(context, '无法选择图片');
    }
  }

  Future<void> _send() async {
    if (ref.read(agentRunControllerProvider).isRunning) return;
    FocusScope.of(context).unfocus();
    final text = _input.text.trim();
    final imagePath = _imagePath;
    if (text.isEmpty && imagePath == null) {
      RikaiToast.show(context, '请输入文字或选择图片');
      return;
    }
    final enabled = ref.read(enabledDictionariesProvider);
    final dictionaries = _selectedDictionaries(enabled);
    if (dictionaries.isEmpty) {
      RikaiToast.show(context, '请至少选择一本词典');
      return;
    }
    final providers =
        ref.read(agentProvidersProvider).asData?.value ??
        const <AgentProviderConfig>[];
    final provider = _provider(providers);
    if (provider == null) {
      RikaiToast.show(context, '请先在设置中配置模型');
      return;
    }
    final settings = ref.read(appSettingsProvider);
    final run = _runController.start(
      userText: text,
      images: imagePath == null
          ? const <AgentImageInput>[]
          : <AgentImageInput>[
              AgentImageInput(id: 'img-1', localPath: imagePath),
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
    // Immediate validation errors (for example an empty model name) keep the
    // user's text/image so nothing typed is lost.
    if (ref.read(agentRunControllerProvider).isRunning) {
      setState(() {
        _input.clear();
        _imagePath = null;
        _settingsExpanded = false;
      });
    }
    unawaited(run);
  }

  void _retry() {
    unawaited(_runController.retry());
  }

  void _retryLoose() {
    unawaited(_runController.retry(mode: AgentMode.loose));
  }

  void _cancel() {
    _runController.cancel();
  }

  void _newSession() {
    if (ref.read(agentRunControllerProvider).isRunning) return;
    _runController.newSession();
    setState(() {
      _input.clear();
      _imagePath = null;
      final enabled = ref.read(enabledDictionariesProvider);
      _selectedIds = enabled.map((dictionary) => dictionary.id).toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(enabledDictionariesProvider);
    final providersAsync = ref.watch(agentProvidersProvider);
    final providers =
        providersAsync.asData?.value ?? const <AgentProviderConfig>[];
    final provider = _provider(providers);
    final selected = _selectedDictionaries(enabled);
    final selectedIds = selected.map((dictionary) => dictionary.id).toSet();
    final run = ref.watch(agentRunControllerProvider);
    ref.listen(agentRunControllerProvider, (previous, next) {
      if (previous?.status != next.status ||
          previous?.stageMessage != next.stageMessage ||
          previous?.receivedChars != next.receivedChars ||
          previous?.result != next.result ||
          previous?.errorMessage != next.errorMessage) {
        scrollAgentToBottom(_messagesScroll, mounted);
      }
    });
    final running = run.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('词典助手'),
        actions: [
          IconButton(
            tooltip: '新会话',
            onPressed: running ? null : _newSession,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: '历史记录',
            onPressed: () => RikaiToast.show(context, '历史记录将在 P6.7 提供'),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: '模型设置',
            onPressed: () => context.push('/agent-settings'),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            buildAgentSessionBar(
              context,
              mode: _mode,
              providerName: provider?.displayName ?? '未配置模型',
              expanded: _settingsExpanded,
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
                selectionMode: _selectionMode,
                running: running,
                onProviderChanged: (value) =>
                    setState(() => _selectedProviderId = value),
                onModeChanged: (value) => setState(() => _mode = value),
                onSelectionModeChanged: (value) =>
                    setState(() => _selectionMode = value),
                onToggleDictionary: (id) => _toggleDictionary(id, enabled),
                onSelectAll: () => _selectAll(enabled),
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
              ),
            ),
            buildAgentComposer(
              context,
              controller: _input,
              imagePath: _imagePath,
              running: running,
              canSend: providers.isNotEmpty,
              onPickImage: _pickImage,
              onRemoveImage: () => setState(() => _imagePath = null),
              onSend: _send,
              onStop: _cancel,
            ),
          ],
        ),
      ),
    );
  }
}
