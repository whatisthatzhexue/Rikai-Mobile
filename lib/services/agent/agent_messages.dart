import '../../core/models/agent/agent_profile.dart';
import 'agent_run.dart';

/// Language used for locally generated UI/progress text (not model output).
enum AgentUiLanguage { chinese, english, japanese }

AgentUiLanguage resolveAgentUiLanguage(
  AgentResponseLanguage setting,
  String sourceText,
) {
  switch (setting) {
    case AgentResponseLanguage.chinese:
      return AgentUiLanguage.chinese;
    case AgentResponseLanguage.english:
      return AgentUiLanguage.english;
    case AgentResponseLanguage.japanese:
      return AgentUiLanguage.japanese;
    case AgentResponseLanguage.follow:
      // "Follow the input": kana strongly indicates Japanese; otherwise a
      // Latin-only input is treated as English and everything else as Chinese.
      if (RegExp(r'[぀-ヿㇰ-ㇿ]').hasMatch(sourceText)) {
        return AgentUiLanguage.japanese;
      }
      final hasLatin = RegExp(r'[A-Za-z]').hasMatch(sourceText);
      final hasCjk = RegExp(r'[㐀-鿿]').hasMatch(sourceText);
      if (hasLatin && !hasCjk) return AgentUiLanguage.english;
      return AgentUiLanguage.chinese;
  }
}

String agentStageMessage(AgentStage stage, AgentUiLanguage language) {
  switch (stage) {
    case AgentStage.prepare:
      return _pick(language, '准备输入', 'Preparing', '入力を準備中');
    case AgentStage.ocr:
      return _pick(language, '本机 OCR', 'On-device OCR', '端末内 OCR');
    case AgentStage.familiarizing:
      return _pick(
        language,
        '熟悉词典',
        'Reading dictionary profiles',
        '辞書情報を確認中',
      );
    case AgentStage.tokenizing:
      return _pick(
        language,
        '分词与检索依据',
        'Tokenizing and retrieving evidence',
        '形態素解析と根拠検索',
      );
    case AgentStage.evidence:
      return _pick(
        language,
        '整理词典依据',
        'Organizing dictionary evidence',
        '辞書根拠を整理中',
      );
    case AgentStage.reasoning:
      return _pick(language, '生成结果', 'Generating', '生成中');
    case AgentStage.validating:
      return _pick(
        language,
        '校验依据',
        'Validating citations',
        '根拠を検証中',
      );
    case AgentStage.done:
      return _pick(language, '完成', 'Done', '完了');
    case AgentStage.cancelled:
      return _pick(language, '已停止', 'Stopped', '停止しました');
    case AgentStage.error:
      return _pick(
        language,
        'Agent 运行失败',
        'Agent failed',
        '実行に失敗しました',
      );
  }
}

String agentRepairingMessage(AgentUiLanguage language) => _pick(
  language,
  '修复格式与引用',
  'Repairing format and citations',
  '形式と引用を修正中',
);

String agentInputRequiredMessage(AgentUiLanguage language) => _pick(
  language,
  '请输入文字或选择图片',
  'Enter text or select an image',
  'テキストを入力するか画像を選択してください',
);

String agentDictionaryRequiredMessage(AgentUiLanguage language) => _pick(
  language,
  '请至少选择一本词典',
  'Select at least one dictionary',
  '辞書を1冊以上選択してください',
);

String agentModelRequiredMessage(AgentUiLanguage language) => _pick(
  language,
  '尚未配置模型',
  'No model is configured',
  'モデルが設定されていません',
);

List<String> agentProgressStepLabels(AgentUiLanguage language) => switch (
  language
) {
  AgentUiLanguage.chinese => const <String>['OCR', '查词', '生成', '校验'],
  AgentUiLanguage.english => const <String>['OCR', 'Lookup', 'Generate', 'Validate'],
  AgentUiLanguage.japanese => const <String>['OCR', '検索', '生成', '検証'],
};

String agentEvidenceProgressLabel(
  int evidenceCount,
  int citationCount,
  AgentUiLanguage language,
) {
  if (citationCount > 0) {
    return _pick(
      language,
      '已检索 $evidenceCount 条词典条目，采用 $citationCount 条依据',
      '$evidenceCount dictionary entries retrieved, $citationCount citations used',
      '辞書項目 $evidenceCount 件を検索、根拠 $citationCount 件を採用',
    );
  }
  return _pick(
    language,
    '已检索 $evidenceCount 条词典条目',
    '$evidenceCount dictionary entries retrieved',
    '辞書項目 $evidenceCount 件を検索',
  );
}

String agentThinkingFallback(AgentUiLanguage language) => _pick(
  language,
  '模型思考中…',
  'Thinking…',
  '思考中…',
);

String agentElapsedLabel(int seconds, AgentUiLanguage language) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = safe ~/ 60;
  final rest = (safe % 60).toString().padLeft(2, '0');
  return switch (language) {
    AgentUiLanguage.chinese => safe < 60
        ? '已思考 $safe 秒'
        : '已思考 $minutes 分 $rest 秒',
    AgentUiLanguage.english => safe < 60
        ? 'Thinking for ${safe}s'
        : 'Thinking for ${minutes}m ${rest}s',
    AgentUiLanguage.japanese => safe < 60
        ? '思考中 $safe 秒'
        : '思考中 $minutes 分 $rest 秒',
  };
}

String _pick(AgentUiLanguage language, String zh, String en, String ja) {
  return switch (language) {
    AgentUiLanguage.chinese => zh,
    AgentUiLanguage.english => en,
    AgentUiLanguage.japanese => ja,
  };
}
