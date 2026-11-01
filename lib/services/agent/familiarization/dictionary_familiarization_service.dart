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
import 'dictionary_profile_tag_parser.dart';
import 'familiarization_prompts.dart';
import 'profile_fingerprint.dart';
import 'profile_repository.dart';

enum ProfileConfirmationAction { save, skipOnce, saveAndNeverAsk, decline }

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

/// A generated profile waiting for an explicit user decision.
///
/// The app-level inbox holds these proposals so navigating away cannot turn a
/// missing decision into an automatic skip. Nothing is written to the profile
/// store until [DictionaryFamiliarizationService.persistDecision] is called.
class AgentProfileProposal {
  AgentProfileProposal({
    required this.id,
    required this.dictionary,
    required this.fingerprint,
    required this.profile,
    required this.markdown,
    this.runId = '',
    this.modelId = '',
    this.promptVersion = 1,
    this.schemaVersion = 1,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final DictionaryInfo dictionary;
  final String fingerprint;
  final DictionaryProfile profile;
  final String markdown;
  final String runId;
  final String modelId;
  final int promptVersion;
  final int schemaVersion;
  final DateTime createdAt;

  String get dictionaryId => dictionary.id;
  String get title => dictionary.title;
}

class FamiliarizationGeneration {
  const FamiliarizationGeneration({
    required this.results,
    required this.proposals,
    this.warnings = const <String>[],
    this.issues = const <DictionaryProfileIssue>[],
  });

  /// Reused, declined and unavailable results. Pending drafts are proposals.
  final List<FamiliarizationResult> results;
  final List<AgentProfileProposal> proposals;
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
  ///
  /// `confirm` is retained for callers that resolve the decision inline. The
  /// Agent run splits generation and decision into [generateMany] +
  /// [persistDecision] so a page detach can never skip a profile.
  Future<FamiliarizationBatchResult> ensureMany(
    List<DictionaryInfo> dictionaries, {
    ProfileConfirmationCallback? confirm,
    bool force = false,
    String runId = '',
  }) async {
    final generation = await generateMany(
      dictionaries,
      force: force,
      runId: runId,
    );
    final results = <FamiliarizationResult>[...generation.results];
    for (final proposal in generation.proposals) {
      if (confirm == null) {
        results.add(
          FamiliarizationResult(
            action: FamiliarizationAction.pending,
            draft: proposal.profile,
            markdown: proposal.markdown,
          ),
        );
        continue;
      }
      final decision = await confirm(proposal.profile, proposal.markdown);
      results.add(
        await persistDecision(proposal, decision.action, decision.markdown),
      );
    }
    return FamiliarizationBatchResult(
      results: results,
      warnings: generation.warnings,
      issues: generation.issues,
    );
  }

  /// Samples and generates profiles without asking for consent or writing a
  /// profile. All generated items are returned so the app-level inbox can show
  /// the complete pending queue.
  Future<FamiliarizationGeneration> generateMany(
    List<DictionaryInfo> dictionaries, {
    bool force = false,
    String runId = '',
  }) async {
    final results = <FamiliarizationResult>[];
    final proposals = <AgentProfileProposal>[];
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
      return FamiliarizationGeneration(
        results: results,
        proposals: proposals,
        issues: issues,
      );
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
      return FamiliarizationGeneration(
        results: results,
        proposals: proposals,
        warnings: warnings,
        issues: issues,
      );
    }

    var proposalSerial = 0;
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

      final parsed = _parseProfiles(raw);
      var profiles = parsed.profiles;
      final missing = batch
          .where((dictionary) => !profiles.containsKey(dictionary.id))
          .toList(growable: false);
      if (missing.isNotEmpty || parsed.integrityErrors.isNotEmpty) {
        // One bounded format-correction call per batch. It may only add tags;
        // readable text must stay unchanged.
        try {
          final repairedRaw = await collectLlmText(
            _llm,
            buildDictionaryProfileBatchRepairRequest(
              model: _smallModel,
              samples: batchSamples,
              language: profileLanguage,
              rawOutput: raw,
              errors: <String>[
                ...parsed.integrityErrors,
                if (missing.isNotEmpty)
                  'missing profiles for: '
                      '${missing.map((dictionary) => dictionary.id).join(', ')}',
              ],
              maxTokens: maxTokens,
            ),
          );
          final repaired = _parseProfiles(repairedRaw);
          profiles = <String, DictionaryProfile>{
            ...repaired.profiles,
            ...profiles,
          };
          if (repaired.integrityErrors.isNotEmpty) {
            warnings.add('词典档案标签不完整，已使用可解析内容');
          }
        } catch (error) {
          _agentDebug(
            '[AgentFamiliarization] format repair failed '
            '(dictionaries=${batch.length}): ${error.runtimeType}',
          );
        }
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
        proposalSerial++;
        proposals.add(
          AgentProfileProposal(
            id:
                'profile-${DateTime.now().microsecondsSinceEpoch}-'
                '$proposalSerial-${dictionary.id}',
            dictionary: dictionary,
            fingerprint: fingerprints[dictionary.id]!,
            profile: draft,
            markdown: markdown,
            runId: runId,
            modelId: _smallModel,
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
          ),
        );
      }
    }
    return FamiliarizationGeneration(
      results: results,
      proposals: proposals,
      warnings: warnings,
      issues: issues,
    );
  }

  /// Writes the user's explicit decision. `skipOnce` deliberately writes
  /// nothing and can be retried on the next run.
  Future<FamiliarizationResult> persistDecision(
    AgentProfileProposal proposal,
    ProfileConfirmationAction action,
    String markdown,
  ) {
    return persistAgentProfileDecision(
      repository: _repository,
      proposal: proposal,
      action: action,
      markdown: markdown,
    );
  }

  ({Map<String, DictionaryProfile> profiles, List<String> integrityErrors})
  _parseProfiles(String raw) {
    final tagged = parseTaggedProfiles(raw, language: profileLanguage);
    return (
      profiles: <String, DictionaryProfile>{
        for (final profile in tagged)
          if (profile.dictionaryId.isNotEmpty) profile.dictionaryId: profile,
      },
      integrityErrors: dictionaryProfileTagIntegrityErrors(raw),
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
}

/// Applies an explicit user decision to a generated proposal without depending
/// on a live LLM/sample port. Used by both the Agent run and the profile
/// manager.
Future<FamiliarizationResult> persistAgentProfileDecision({
  required DictionaryProfileRepository repository,
  required AgentProfileProposal proposal,
  required ProfileConfirmationAction action,
  required String markdown,
}) async {
  final dictionary = proposal.dictionary;
  switch (action) {
    case ProfileConfirmationAction.save ||
        ProfileConfirmationAction.saveAndNeverAsk:
      final stored = StoredDictionaryProfile(
        dictionaryId: dictionary.id,
        title: dictionary.title,
        fingerprint: proposal.fingerprint,
        markdown: markdown.trim().isEmpty ? proposal.markdown : markdown.trim(),
        status: DictionaryProfileStatus.confirmed,
        profile: proposal.profile,
        confirmedAt: DateTime.now(),
        modelId: proposal.modelId,
        promptVersion: proposal.promptVersion,
        schemaVersion: proposal.schemaVersion,
      );
      await repository.save(stored);
      return FamiliarizationResult(
        action: FamiliarizationAction.created,
        stored: stored,
        draft: proposal.profile,
        markdown: stored.markdown,
      );
    case ProfileConfirmationAction.decline:
      final stored = StoredDictionaryProfile(
        dictionaryId: dictionary.id,
        title: dictionary.title,
        fingerprint: proposal.fingerprint,
        markdown: '',
        status: DictionaryProfileStatus.declined,
        confirmedAt: DateTime.now(),
        modelId: proposal.modelId,
        promptVersion: proposal.promptVersion,
        schemaVersion: proposal.schemaVersion,
      );
      await repository.save(stored);
      return FamiliarizationResult(
        action: FamiliarizationAction.declined,
        stored: stored,
      );
    case ProfileConfirmationAction.skipOnce:
      return FamiliarizationResult(
        action: FamiliarizationAction.skipped,
        draft: proposal.profile,
        markdown: proposal.markdown,
      );
  }
}

void _agentDebug(String message) {
  if (kDebugMode) debugPrint(message);
}
