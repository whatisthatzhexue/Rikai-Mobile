import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/models/agent/agent_profile.dart';
import '../../../core/models/agent/agent_tool.dart';
import '../../../core/models/dict_info.dart';
import '../../../core/models/dictionary_sample.dart';
import '../ports/agent_capability_exception.dart';
import '../ports/dictionary_sample_port.dart';
import '../ports/llm_port.dart';
import 'dictionary_profile_markdown.dart';
import 'familiarization_prompts.dart';
import 'profile_fingerprint.dart';
import 'profile_repository.dart';

enum ProfileConfirmationAction { save, skipOnce, decline }

class ProfileConfirmation {
  const ProfileConfirmation({required this.action, required this.markdown});

  final ProfileConfirmationAction action;
  final String markdown;
}

typedef ProfileConfirmationCallback =
    Future<ProfileConfirmation> Function(
      DictionaryProfile profile,
      String markdown,
    );

enum FamiliarizationAction {
  reuse,
  created,
  skipped,
  declined,
  pending,
  unavailable,
}

class DictionaryProfileIssue {
  const DictionaryProfileIssue({
    required this.dictionaryId,
    required this.title,
    required this.reason,
  });

  final String dictionaryId;
  final String title;
  final String reason;

  Map<String, Object?> toJson() => {
    'dictionary_id': dictionaryId,
    'title': title,
    'reason': reason,
  };
}

class FamiliarizationResult {
  const FamiliarizationResult({
    required this.action,
    this.stored,
    this.draft,
    this.markdown = '',
    this.reason = '',
  });

  final FamiliarizationAction action;
  final StoredDictionaryProfile? stored;
  final DictionaryProfile? draft;
  final String markdown;
  final String reason;
}

class FamiliarizationBatchResult {
  const FamiliarizationBatchResult({
    required this.results,
    this.warnings = const <String>[],
    this.issues = const <DictionaryProfileIssue>[],
  });

  final List<FamiliarizationResult> results;
  final List<String> warnings;
  final List<DictionaryProfileIssue> issues;
}

/// Generates and caches one dictionary profile after explicit user consent.
class DictionaryFamiliarizationService {
  const DictionaryFamiliarizationService({
    required DictionarySamplePort samplePort,
    required DictionaryProfileRepository repository,
    required LlmPort llm,
    required String smallModel,
    this.promptVersion = dictionaryProfilePromptVersion,
    this.schemaVersion = dictionaryProfileSchemaVersion,
    this.maxEntries = 12,
    this.maxBatchTokens = 4000,
    this.profileLanguage = AgentProfileLanguage.chinese,
  }) : _samplePort = samplePort,
       _repository = repository,
       _llm = llm,
       _smallModel = smallModel;

  final DictionarySamplePort _samplePort;
  final DictionaryProfileRepository _repository;
  final LlmPort _llm;
  final String _smallModel;
  final int promptVersion;
  final int schemaVersion;
  final int maxEntries;
  final int maxBatchTokens;
  final AgentProfileLanguage profileLanguage;

  Future<FamiliarizationResult> ensure(
    DictionaryInfo dictionary, {
    ProfileConfirmationCallback? confirm,
    bool force = false,
  }) async {
    final batch = await ensureMany(
      <DictionaryInfo>[dictionary],
      confirm: confirm,
      force: force,
    );
    if (batch.results.isEmpty || batch.issues.isNotEmpty) {
      throw AgentCapabilityException(
        AgentToolErrorCode.validationFailed,
        batch.issues.isEmpty ? '词典档案生成失败' : batch.issues.first.reason,
      );
    }
    return batch.results.first;
  }

  /// Generates all missing profiles in one provider request.
  ///
  /// Confirmed/declined profiles are reused locally. If the batch request or
  /// JSON parse fails, the run continues with warnings instead of spending
  /// one request per dictionary.
  Future<FamiliarizationBatchResult> ensureMany(
    List<DictionaryInfo> dictionaries, {
    ProfileConfirmationCallback? confirm,
    bool force = false,
  }) async {
    final results = <FamiliarizationResult>[];
    final warnings = <String>[];
    final issues = <DictionaryProfileIssue>[];
    final pending = <DictionaryInfo>[];
    final fingerprints = <String, String>{};

    for (final dictionary in dictionaries) {
      final fingerprint = await dictionaryProfileFingerprint(
        dictionary,
        promptVersion: promptVersion,
        schemaVersion: schemaVersion,
        language: profileLanguage,
      );
      fingerprints[dictionary.id] = fingerprint;
      final existing = await _repository.load(dictionary.id);
      if (!force && existing != null && existing.fingerprint == fingerprint) {
        if (existing.isConfirmed) {
          results.add(
            FamiliarizationResult(
              action: FamiliarizationAction.reuse,
              stored: existing,
              draft: existing.profile,
              markdown: existing.markdown,
            ),
          );
          continue;
        }
        if (existing.status == DictionaryProfileStatus.declined) {
          results.add(
            FamiliarizationResult(
              action: FamiliarizationAction.declined,
              stored: existing,
              markdown: existing.markdown,
            ),
          );
          continue;
        }
      }
      pending.add(dictionary);
    }

    if (pending.isEmpty) {
      return FamiliarizationBatchResult(results: results, issues: issues);
    }

    final samples = <String, DictionarySample>{};
    for (final dictionary in pending) {
      try {
        samples[dictionary.id] = await _samplePort.sample(
          dictionary,
          maxEntries: maxEntries,
        );
      } catch (error) {
        const reason = '词典采样失败';
        warnings.add('${dictionary.title}: $reason');
        issues.add(
          DictionaryProfileIssue(
            dictionaryId: dictionary.id,
            title: dictionary.title,
            reason: reason,
          ),
        );
        results.add(
          FamiliarizationResult(
            action: FamiliarizationAction.unavailable,
            reason: reason,
          ),
        );
      }
    }
    final sampled = pending
        .where((dictionary) => samples.containsKey(dictionary.id))
        .toList(growable: false);
    if (sampled.isEmpty) {
      return FamiliarizationBatchResult(
        results: results,
        warnings: warnings,
        issues: issues,
      );
    }

    for (final batch in _splitBatches(sampled, samples)) {
      final batchSamples = <DictionarySample>[
        for (final dictionary in batch) samples[dictionary.id]!,
      ];
      final maxTokens = (2000 + batch.length * 900).clamp(2000, 6000).toInt();
      final request = LlmRequest(
        model: _smallModel,
        messages: <LlmMessage>[
          LlmMessage(
            role: LlmRole.system,
            parts: <LlmTextPart>[
              LlmTextPart(dictionaryProfileBatchSystemPrompt(profileLanguage)),
            ],
          ),
          LlmMessage(
            role: LlmRole.user,
            parts: <LlmTextPart>[
              LlmTextPart(
                buildDictionaryProfileBatchUserPrompt(
                  batchSamples,
                  profileLanguage,
                ),
              ),
            ],
          ),
        ],
        responseFormat: LlmResponseFormat(
          name: 'dictionary_profiles',
          schema: dictionaryProfileBatchResponseSchema(),
        ),
        maxTokens: maxTokens,
        stream: false,
      );

      final String raw;
      try {
        raw = await collectLlmText(_llm, request);
      } catch (error) {
        _agentDebug(
          '[AgentFamiliarization] batch request failed '
          '(dictionaries=${batch.length}): ${error.runtimeType}',
        );
        for (final dictionary in batch) {
          const reason = '词典档案请求失败';
          warnings.add('${dictionary.title}: $reason');
          issues.add(
            DictionaryProfileIssue(
              dictionaryId: dictionary.id,
              title: dictionary.title,
              reason: reason,
            ),
          );
          results.add(
            FamiliarizationResult(
              action: FamiliarizationAction.unavailable,
              reason: reason,
            ),
          );
        }
        continue;
      }

      final profiles = <String, DictionaryProfile>{};
      try {
        final json = extractJsonObject(raw);
        final rawProfiles = json['profiles'];
        if (rawProfiles is List) {
          for (final item in rawProfiles.whereType<Map>()) {
            final profile = DictionaryProfile.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            );
            if (profile.dictionaryId.isNotEmpty) {
              profiles[profile.dictionaryId] = profile.copyWith(
                language: profileLanguage.wireName,
              );
            }
          }
        } else if (batch.length == 1) {
          // Older prompts/one-dictionary calls may return the profile directly
          // instead of wrapping it in {"profiles": [...]}. Keep that response
          // usable without spending a repair request.
          final profile = DictionaryProfile.fromJson(json);
          if (profile.dictionaryId.isNotEmpty) {
            profiles[profile.dictionaryId] = profile.copyWith(
              language: profileLanguage.wireName,
            );
          }
        }
      } catch (error) {
        _agentDebug(
          '[AgentFamiliarization] batch JSON parse failed '
          '(dictionaries=${batch.length}, chars=${raw.length}): '
          '${error.runtimeType}',
        );
      }

      for (final dictionary in batch) {
        final draft = profiles[dictionary.id];
        if (draft == null) {
          const reason = '模型未返回该词典档案';
          warnings.add('${dictionary.title}: $reason');
          issues.add(
            DictionaryProfileIssue(
              dictionaryId: dictionary.id,
              title: dictionary.title,
              reason: reason,
            ),
          );
          results.add(
            FamiliarizationResult(
              action: FamiliarizationAction.unavailable,
              reason: reason,
            ),
          );
          continue;
        }
        final markdown = profileToMarkdown(draft, profileLanguage);
        if (confirm == null) {
          results.add(
            FamiliarizationResult(
              action: FamiliarizationAction.pending,
              draft: draft,
              markdown: markdown,
            ),
          );
          continue;
        }
        final decision = await confirm(draft, markdown);
        switch (decision.action) {
          case ProfileConfirmationAction.save:
            final stored = await _saveConfirmed(
              dictionary: dictionary,
              draft: draft,
              markdown: decision.markdown.trim().isEmpty
                  ? markdown
                  : decision.markdown.trim(),
              fingerprint: fingerprints[dictionary.id]!,
            );
            results.add(
              FamiliarizationResult(
                action: FamiliarizationAction.created,
                stored: stored,
                draft: draft,
                markdown: stored.markdown,
              ),
            );
          case ProfileConfirmationAction.decline:
            final stored = await _saveDeclined(
              dictionary: dictionary,
              fingerprint: fingerprints[dictionary.id]!,
            );
            results.add(
              FamiliarizationResult(
                action: FamiliarizationAction.declined,
                stored: stored,
              ),
            );
          case ProfileConfirmationAction.skipOnce:
            results.add(
              FamiliarizationResult(
                action: FamiliarizationAction.skipped,
                draft: draft,
                markdown: markdown,
              ),
            );
        }
      }
    }
    return FamiliarizationBatchResult(
      results: results,
      warnings: warnings,
      issues: issues,
    );
  }

  List<List<DictionaryInfo>> _splitBatches(
    List<DictionaryInfo> dictionaries,
    Map<String, DictionarySample> samples,
  ) {
    final batches = <List<DictionaryInfo>>[];
    var current = <DictionaryInfo>[];
    var currentTokens = 0;
    for (final dictionary in dictionaries) {
      final sample = samples[dictionary.id];
      if (sample == null) continue;
      final estimated = 1200 + (jsonEncode(sample.toJson()).length / 2).ceil();
      if (current.isNotEmpty && currentTokens + estimated > maxBatchTokens) {
        batches.add(current);
        current = <DictionaryInfo>[];
        currentTokens = 0;
      }
      current.add(dictionary);
      currentTokens += estimated;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  Future<StoredDictionaryProfile> _saveConfirmed({
    required DictionaryInfo dictionary,
    required DictionaryProfile draft,
    required String markdown,
    required String fingerprint,
  }) async {
    final stored = StoredDictionaryProfile(
      dictionaryId: dictionary.id,
      fingerprint: fingerprint,
      markdown: markdown,
      status: DictionaryProfileStatus.confirmed,
      profile: draft,
      confirmedAt: DateTime.now(),
      modelId: _smallModel,
      promptVersion: promptVersion,
      schemaVersion: schemaVersion,
    );
    await _repository.save(stored);
    return stored;
  }

  Future<StoredDictionaryProfile> _saveDeclined({
    required DictionaryInfo dictionary,
    required String fingerprint,
  }) async {
    final stored = StoredDictionaryProfile(
      dictionaryId: dictionary.id,
      fingerprint: fingerprint,
      markdown: '',
      status: DictionaryProfileStatus.declined,
      confirmedAt: DateTime.now(),
      modelId: _smallModel,
      promptVersion: promptVersion,
      schemaVersion: schemaVersion,
    );
    await _repository.save(stored);
    return stored;
  }

}

void _agentDebug(String message) {
  if (kDebugMode) debugPrint(message);
}
