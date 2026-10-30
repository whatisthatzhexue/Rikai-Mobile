import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/dict_info.dart';
import '../../core/models/lookup_models.dart';
import '../../core/theme/page_route.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/agent/adapters/dictionary_sample_port_adapter.dart';
import '../../services/agent/familiarization/dictionary_familiarization_service.dart';
import '../../services/agent/providers/provider_factory.dart';
import '../../state/agent_providers.dart';
import '../../state/providers.dart';
import '../lookup/entry_page.dart';
import 'familiarization_sheet.dart';

Future<ProfileConfirmation> confirmAgentProfile(
  BuildContext context,
  DictionaryProfile profile,
  String markdown,
) async {
  if (!context.mounted) {
    return ProfileConfirmation(
      action: ProfileConfirmationAction.skipOnce,
      markdown: markdown,
    );
  }
  final decision = await showFamiliarizationSheet(
    context,
    profile: profile,
    markdown: markdown,
  );
  return decision ??
      ProfileConfirmation(
        action: ProfileConfirmationAction.skipOnce,
        markdown: markdown,
      );
}

Future<void> openAgentCitation(
  BuildContext context,
  WidgetRef ref,
  AgentCitation citation,
) async {
  final enabled = ref.read(enabledDictionariesProvider);
  DictionaryInfo? dictionary;
  for (final item in enabled) {
    if (item.id == citation.dictionaryId) {
      dictionary = item;
      break;
    }
  }
  if (dictionary == null) {
    RikaiToast.show(context, '该词典当前不可用');
    return;
  }
  final selectedDictionary = dictionary;
  try {
    final service = await ref.read(mdictServiceProvider.future);
    final result = await service.lookup(
      query: citation.entryKey,
      rawCandidates: <String>[
        citation.entryKey,
        if (citation.matchedKey.isNotEmpty) citation.matchedKey,
      ],
      dictionaries: <DictionaryInfo>[selectedDictionary],
      maxEntriesPerDictionary: 1,
    );
    final group = result.hitGroups.isEmpty ? null : result.hitGroups.first;
    if (!context.mounted) return;
    if (group == null || group.entries.isEmpty) {
      RikaiToast.show(context, '未找到该词条');
      return;
    }
    Navigator.of(context).push(
      RikaiPageRoute<void>(
        builder: (context) => EntryPage(
          word: citation.entryKey,
          groups: <DictionaryLookupGroup>[
            DictionaryLookupGroup(
              dictionary: group.dictionary,
              entries: <LookupEntry>[group.entries.first],
            ),
          ],
          initialDictionaryId: selectedDictionary.id,
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) RikaiToast.show(context, '打开词条失败');
  }
}

/// Regenerates a failed/unavailable dictionary profile without starting a new
/// analysis run. The user still confirms the generated profile.
Future<void> retryAgentDictionaryProfile(
  BuildContext context,
  WidgetRef ref,
  DictionaryProfileIssue issue,
  AgentProviderConfig provider,
) async {
  final enabled = ref.read(enabledDictionariesProvider);
  DictionaryInfo? dictionary;
  for (final item in enabled) {
    if (item.id == issue.dictionaryId) {
      dictionary = item;
      break;
    }
  }
  if (dictionary == null) {
    RikaiToast.show(context, '该词典当前不可用');
    return;
  }
  final selectedDictionary = dictionary;
  final settings = ref.read(appSettingsProvider);
  try {
    final mdict = await ref.read(mdictServiceProvider.future);
    final secretStore = ref.read(secretStoreProvider);
    final smallModel = provider.smallModel.trim().isEmpty
        ? provider.complexModel
        : provider.smallModel;
    final familiarizer = DictionaryFamiliarizationService(
      samplePort: DictionarySamplePortAdapter(mdict),
      repository: ref.read(agentStoreProvider),
      llm: createLlmProvider(config: provider, secrets: secretStore),
      smallModel: smallModel,
      profileLanguage: AgentProfileLanguage.fromWire(
        settings.agentProfileLanguage,
      ),
    );
    final batch = await familiarizer.ensureMany(
      <DictionaryInfo>[selectedDictionary],
      force: true,
      confirm: (profile, markdown) async {
        if (!context.mounted) {
          return ProfileConfirmation(
            action: ProfileConfirmationAction.skipOnce,
            markdown: markdown,
          );
        }
        final decision = await showFamiliarizationSheet(
          context,
          profile: profile,
          markdown: markdown,
        );
        return decision ??
            ProfileConfirmation(
              action: ProfileConfirmationAction.skipOnce,
              markdown: markdown,
            );
      },
    );
    if (!context.mounted) return;
    if (batch.issues.isNotEmpty) {
      RikaiToast.show(context, batch.issues.first.reason);
    } else {
      RikaiToast.show(context, '档案已更新，请重新开始分析');
    }
  } catch (_) {
    if (context.mounted) RikaiToast.show(context, '档案重试失败');
  }
}
