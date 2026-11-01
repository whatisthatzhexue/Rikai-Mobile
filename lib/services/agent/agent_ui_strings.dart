import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_tool.dart';
import '../agent/agent_run.dart';

/// Language used for locally generated Agent UI/progress text.
enum AgentUiLanguage { chinese, english, japanese }

/// The local UI language is derived only from the explicit output-language
/// setting. Source text is never inspected; `follow` was removed on 2026-11-01
/// and legacy values migrate to Chinese in [AgentResponseLanguage.fromWire].
AgentUiLanguage resolveAgentUiLanguage(AgentResponseLanguage setting) {
  return switch (setting) {
    AgentResponseLanguage.chinese => AgentUiLanguage.chinese,
    AgentResponseLanguage.english => AgentUiLanguage.english,
    AgentResponseLanguage.japanese => AgentUiLanguage.japanese,
  };
}

/// Centralized Agent-area copy. Defaults to Chinese; English/Japanese variants
/// follow the explicit output language, never the input script.
class AgentUiStrings {
  const AgentUiStrings(this.language);

  factory AgentUiStrings.of(AgentUiLanguage language) =>
      AgentUiStrings(language);

  final AgentUiLanguage language;

  String _pick(String zh, String en, String ja) => switch (language) {
    AgentUiLanguage.chinese => zh,
    AgentUiLanguage.english => en,
    AgentUiLanguage.japanese => ja,
  };

  // App bar / navigation.
  String get appTitle => _pick('词典助手', 'Dictionary Assistant', '辞書アシスタント');
  String get newSession => _pick('新会话', 'New session', '新しい会話');
  String get history => _pick('历史记录', 'History', '履歴');
  String get historyPending => _pick(
    '历史记录将在 P6.7 提供',
    'History is planned for P6.7',
    '履歴は P6.7 で提供予定です',
  );
  String get profiles => _pick('词典档案', 'Dictionary profiles', '辞書プロファイル');
  String get settings => _pick('模型设置', 'Model settings', 'モデル設定');

  // Session bar / panel.
  String get sessionSettings => _pick('本会话设置', 'Session settings', 'この会話の設定');
  String get strictShort => _pick('严格', 'Strict', '厳格');
  String get looseShort => _pick('宽松', 'Loose', '緩和');
  String get unconfiguredModel =>
      _pick('未配置模型', 'No model configured', 'モデル未設定');
  String get model => _pick('模型', 'Model', 'モデル');
  String get strictMode => _pick('严格模式', 'Strict mode', '厳格モード');
  String get looseMode => _pick('宽松模式', 'Loose mode', '緩和モード');
  String get sessionDictionaries =>
      _pick('本次词典', 'Dictionaries in this session', 'この会話の辞書');
  String get noDictionaries => _pick(
    '尚未添加可用的 MDict 词典',
    'No usable MDict dictionary yet',
    '利用可能な MDict 辞書がありません',
  );
  String get noProviderTitle =>
      _pick('尚未配置模型', 'No model configured', 'モデルが未設定です');
  String get noProviderBody => _pick(
    '配置 API Key 后才能使用词典助手；图片仍只在本机 OCR，不会上传。',
    'Configure an API key to use the assistant. Images are still OCRed on-device and never uploaded.',
    'API キーを設定すると辞書アシスタントを使えます。画像は端末内で OCR され、アップロードされません。',
  );
  String get goConfigureModel => _pick('去配置模型', 'Configure model', 'モデルを設定');

  // Composer.
  String get imageLocalOnly => _pick(
    '图片仅在本机 OCR，不会上传',
    'Images are OCRed on-device and never uploaded',
    '画像は端末内で OCR され、アップロードされません',
  );
  String get removeImage => _pick('移除图片', 'Remove image', '画像を削除');
  String get pickImage => _pick('选择图片', 'Select images', '画像を選択');
  String get inputHint => _pick(
    '输入问题，或粘贴文本…',
    'Ask a question or paste text…',
    '質問を入力するか、テキストを貼り付け…',
  );
  String get takePhoto => _pick('拍照', 'Take a photo', '写真を撮る');
  String get chooseFromGallery =>
      _pick('从相册选择', 'Choose from gallery', 'ギャラリーから選択');
  String get addImages => _pick('添加图片', 'Add images', '画像を追加');
  String imageLimitReached(int limit) => _pick(
    '最多一次发送 $limit 张图片',
    'You can send at most $limit images at once',
    '一度に送信できる画像は最大 $limit 枚です',
  );
  String get pickImageFailed =>
      _pick('无法选择图片', 'Unable to select images', '画像を選択できません');
  String get inputRequired => _pick(
    '请输入文字或选择图片',
    'Enter text or select an image',
    'テキストを入力するか画像を選択してください',
  );
  String get dictionaryRequired =>
      _pick('请至少选择一本词典', 'Select at least one dictionary', '辞書を1冊以上選択してください');
  String get modelRequired =>
      _pick('请先在设置中配置模型', 'Configure a model first', '先にモデルを設定してください');

  // Messages.
  String sentImages(int count) =>
      _pick('已发送图片 $count 张', '$count sent image(s)', '送信した画像 $count 枚');
  String get imageOnly =>
      _pick('图片（仅本机 OCR）', 'Image (on-device OCR)', '画像（端末内 OCR）');
  String get assistantFallback => _pick(
    '已生成结果，请展开详细解析。',
    'Result generated. Expand for details.',
    '結果を生成しました。詳細を展開してください。',
  );
  String get retry => _pick('重试', 'Retry', '再試行');
  String get looseRetry => _pick('宽松重试', 'Retry in loose mode', '緩和モードで再試行');
  String get goSettings => _pick('去设置', 'Settings', '設定');
  String get viewDiagnostics => _pick('查看诊断', 'View diagnostics', '診断を表示');
  String get emptyTitle => _pick('词典助手', 'Dictionary Assistant', '辞書アシスタント');
  String get emptyBody => _pick(
    '输入日文或选择图片；图片只在本机 OCR，不会上传。结果会附带可点击的词典依据。',
    'Enter Japanese text or choose images. Images are OCRed on-device and never uploaded. Results include tappable dictionary citations.',
    '日本語を入力するか画像を選択してください。画像は端末内で OCR され、アップロードされません。結果には辞書根拠が付きます。',
  );
  String get awaitingProfiles => _pick(
    '等待确认词典档案',
    'Waiting for dictionary profile confirmation',
    '辞書プロファイルの確認待ち',
  );
  String errorMessageFor(AgentToolErrorCode? code, String fallback) {
    return switch (code) {
      AgentToolErrorCode.notConfigured => modelRequired,
      AgentToolErrorCode.modelMissing => _pick(
        '所需模型未安装',
        'A required model is not installed',
        '必要なモデルがインストールされていません',
      ),
      AgentToolErrorCode.modelInvalid => _pick(
        '模型文件无效',
        'The model file is invalid',
        'モデルファイルが無効です',
      ),
      AgentToolErrorCode.dictionaryNotReady => dictionaryRequired,
      AgentToolErrorCode.dictionaryLookupFailed => _pick(
        '词典查询失败',
        'Dictionary lookup failed',
        '辞書検索に失敗しました',
      ),
      AgentToolErrorCode.unidicNotReady => _pick(
        'UniDic 不可用',
        'UniDic is unavailable',
        'UniDic を利用できません',
      ),
      AgentToolErrorCode.toolTimeout => _pick(
        '请求超时，请重试',
        'The request timed out. Please retry.',
        'リクエストがタイムアウトしました。再試行してください。',
      ),
      AgentToolErrorCode.toolCancelled => _pick('已停止', 'Stopped', '停止しました'),
      AgentToolErrorCode.invalidArguments => fallback,
      AgentToolErrorCode.providerAuthFailed => _pick(
        'API Key 无效或没有权限',
        'The API key is invalid or unauthorized',
        'API キーが無効か権限がありません',
      ),
      AgentToolErrorCode.providerRateLimited => _pick(
        '请求过于频繁，请稍后再试',
        'Too many requests. Please try again later.',
        'リクエストが多すぎます。しばらくしてから再試行してください。',
      ),
      AgentToolErrorCode.providerUnavailable => _pick(
        '模型服务暂时不可用',
        'The model service is unavailable',
        'モデルサービスを利用できません',
      ),
      AgentToolErrorCode.validationFailed => _pick(
        '模型返回格式无效',
        'The model returned an invalid format',
        'モデルの出力形式が無効です',
      ),
      AgentToolErrorCode.internalError => _pick(
        'Agent 运行失败',
        'The assistant failed',
        'アシスタントの実行に失敗しました',
      ),
      null => fallback,
    };
  }

  String pendingProfiles(int count) => _pick(
    '待处理档案 $count 个',
    '$count profile(s) pending',
    '未処理のプロファイル $count 件',
  );
  String get retainedResult => _pick(
    '正在重新生成，下面显示上次结果',
    'Regenerating; showing the previous result below',
    '再生成中。前回の結果を表示しています',
  );
  String get resultRetainedAfterFailure => _pick(
    '重新生成失败，已保留上次结果',
    'Regeneration failed; the previous result was kept',
    '再生成に失敗しました。前回の結果を保持しています',
  );
  String get copy => _pick('复制', 'Copy', 'コピー');
  String get edit => _pick('修改', 'Edit', '編集');
  String get copyDone => _pick('已复制', 'Copied', 'コピーしました');
  String get userMessageMenu => _pick('消息操作', 'Message actions', 'メッセージ操作');
  String get regenerateResult => _pick('重新生成结果', 'Regenerate result', '結果を再生成');
  String get copyResultMarkdown =>
      _pick('复制结果为 Markdown', 'Copy result as Markdown', '結果を Markdown でコピー');
  String get cancel => _pick('取消', 'Cancel', 'キャンセル');

  // Familiarization sheet / profile inbox.
  String profileTitle(String title) => _pick(
    '词典档案 · $title',
    'Dictionary profile · $title',
    '辞書プロファイル · $title',
  );
  String get profileSheetBody => _pick(
    '这是模型根据少量样本生成的词典使用说明。请确认后再用于后续回答；你可以直接编辑下面的文字。',
    'This dictionary guide was generated from a small sample. Review it before it is used in later answers; you can edit the text below.',
    'これは少量のサンプルから生成された辞書の利用説明です。今後の回答に使う前に確認してください。下の文章は編集できます。',
  );
  String get profileHint => _pick('词典档案', 'Dictionary profile', '辞書プロファイル');
  String get saveAndTrust => _pick('保存并信任', 'Save and trust', '保存して信頼');
  String get skipOnce => _pick('本次跳过', 'Skip this time', '今回のみスキップ');
  String get decline => _pick('不再询问', 'Do not ask again', '今後確認しない');
  String get profileUnavailable =>
      _pick('档案不可用', 'Profile unavailable', 'プロファイル利用不可');
  String profileGenerated(String title) => _pick(
    '「$title」词典档案已生成',
    'Dictionary profile generated: $title',
    '辞書プロファイルを生成しました：$title',
  );
  String profilesGenerated(List<String> titles) {
    final names = titles
        .where((title) => title.trim().isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) return '';
    if (names.length == 1) return profileGenerated(names.single);
    return _pick(
      '已生成词典档案：${names.join('、')}',
      'Dictionary profiles generated: ${names.join(', ')}',
      '辞書プロファイルを生成しました：${names.join('、')}',
    );
  }

  String regeneratingProfile(String titles) => _pick(
    '正在重新生成档案：$titles',
    'Regenerating profile: $titles',
    'プロファイルを再生成中：$titles',
  );
  String get profilesAwaitingConfirmation => _pick(
    '该词典档案正在等待确认',
    'This dictionary profile is waiting for confirmation',
    'この辞書プロファイルは確認待ちです',
  );
  String get retryingProfile =>
      _pick('正在重试词典档案', 'Retrying dictionary profile', '辞書プロファイルを再試行中');

  // Result view.
  String get resultTruncated => _pick(
    '部分内容超出预算，未全部分析',
    'Some content exceeded the budget and was not analyzed',
    '一部の内容が予算を超えたため、解析されていません',
  );
  String get structureUnavailable => _pick(
    '结构分析不可用（未配置 UniDic）；本次只提供译文和词典依据',
    'Structural analysis unavailable (UniDic is not configured). Only translation and dictionary evidence are provided.',
    '構造解析は利用できません（UniDic 未設定）。翻訳と辞書根拠のみ提供します。',
  );
  String dictionaryLookupFailed(String names) => _pick(
    '词典查询失败：$names，结果可能不完整',
    'Dictionary lookup failed: $names. The result may be incomplete.',
    '辞書検索に失敗しました：$names。結果が不完全な可能性があります。',
  );
  String get languageWarning => _pick(
    '部分内容未按设置语言输出',
    'Some content was not written in the selected language',
    '一部の内容が設定した言語で出力されていません',
  );
  String get coverageUnavailable => _pick(
    '覆盖审查不可用，已保留现有资料',
    'Coverage review was unavailable; the existing evidence was kept',
    'カバレッジ確認を利用できません。既存の資料を保持しました',
  );
  String get coverageUnverifiable => _pick(
    '覆盖审查返回了无法追溯的查询，已忽略',
    'The coverage review returned untraceable queries; they were ignored',
    'カバレッジ確認の追跡できない検索語は無視しました',
  );
  String get coverageAtLimit => _pick(
    '检索已达上限，无法再补充资料',
    'The evidence limit was reached; no further entries could be added',
    '検索上限に達したため、これ以上資料を追加できません',
  );
  String get coverageNoNew => _pick(
    '覆盖审查未找到新的词典资料',
    'The coverage review found no new dictionary evidence',
    'カバレッジ確認で新しい辞書資料は見つかりませんでした',
  );
  String get validationPartial => _pick(
    '部分内容未通过校验，已移除无依据/无效引用的部分',
    'Some content failed validation; unsupported or invalid citations were removed',
    '一部の内容が検証に通りませんでした。根拠のない引用や無効な引用は削除されました。',
  );
  String profileWarning(String warning) => _pick(
    '词典档案未使用：$warning',
    'Dictionary profile not used: $warning',
    '辞書プロファイル未使用：$warning',
  );
  String noProfile(String title, String reason) => _pick(
    '$title：无档案（$reason），已按通用规则检索',
    '$title: no profile ($reason); generic lookup rules were used',
    '$title：プロファイルなし（$reason）。汎用検索ルールを使用しました。',
  );
  String get retryThisDictionary =>
      _pick('重试此词典', 'Retry this dictionary', 'この辞書を再試行');
  String get dictionaryUnavailable =>
      _pick('该词典当前不可用', 'This dictionary is unavailable', 'この辞書は利用できません');
  String get entryNotFound => _pick('未找到该词条', 'Entry not found', '項目が見つかりません');
  String get openEntryFailed =>
      _pick('打开词条失败', 'Failed to open entry', '項目を開けませんでした');
  String get translationTitle => _pick('译文', 'Translation', '訳文');
  String get originalText => _pick('原文', 'Source text', '原文');
  String get segmentUnderstanding =>
      _pick('逐句理解', 'Sentence-by-sentence', '文ごとの理解');
  String get possibleUnderstandings =>
      _pick('可能的理解', 'Possible interpretations', '解釈の候補');
  String get unresolvedTitle => _pick('未解决', 'Unresolved', '未解決');
  String get unresolvedFallback => _pick('未解决', 'Unresolved', '未解決');
  String get modelSupplements => _pick('模型补充', 'Model supplements', 'モデル補足');
  String get dictionaryEvidence => _pick('词典依据', 'Dictionary evidence', '辞書根拠');
  String evidenceEntryCount(int count) =>
      _pick('$count 条', '$count entry(s)', '$count 件');
  String detailedAnalysis(int count) => _pick(
    '详细解析 · 依据 $count 条',
    'Detailed analysis · $count citation(s)',
    '詳細解析 · 根拠 $count 件',
  );
  String get epistemicDictionaryFact =>
      _pick('词典事实', 'Dictionary fact', '辞書事実');
  String get epistemicStructural =>
      _pick('结构分析', 'Structural analysis', '構造解析');
  String get epistemicInference => _pick('语境推断', 'Context inference', '文脈推論');
  String get epistemicTranslation =>
      _pick('模型译文', 'Model translation', 'モデル翻訳');
  String confidence(int percent) =>
      _pick('置信度 $percent%', 'Confidence $percent%', '信頼度 $percent%');
  String citationLabel(int number) =>
      _pick('依据$number', 'Citation $number', '根拠$number');
  String citationSemantics(int number, String headword) => _pick(
    '查看依据$number $headword',
    'View citation $number $headword',
    '根拠$number $headword を表示',
  );

  // Profile manager.
  String get profileManagerTitle =>
      _pick('词典档案', 'Dictionary profiles', '辞書プロファイル');
  String get profileManagerEmpty => _pick(
    '还没有词典档案。首次分析时会生成档案并等待你确认。',
    'No dictionary profiles yet. Profiles are generated on the first analysis and wait for your confirmation.',
    '辞書プロファイルはまだありません。初回の解析時に生成され、確認を待ちます。',
  );
  String get profileStatusConfirmed => _pick('已信任', 'Trusted', '信頼済み');
  String get profileStatusDeclined => _pick('已拒绝', 'Declined', '拒否済み');
  String get profileStatusPending => _pick('待确认', 'Pending', '確認待ち');
  String get profileStatusStale => _pick('已失效', 'Stale', '無効');
  String get profileUnavailableDictionary =>
      _pick('词典当前不可用', 'Dictionary currently unavailable', '辞書は現在利用できません');
  String get profileEdit => _pick('修改', 'Edit', '編集');
  String get profileRegenerate => _pick('重新生成', 'Regenerate', '再生成');
  String get profileDelete => _pick('删除', 'Delete', '削除');
  String get profileSelectAll => _pick('全选', 'Select all', 'すべて選択');
  String get profileDeleteSelected => _pick('删除选中', 'Delete selected', '選択を削除');
  String get profileRegenerateSelected =>
      _pick('重新生成选中', 'Regenerate selected', '選択を再生成');
  String get profileExitSelection => _pick('退出多选', 'Exit selection', '選択を終了');
  String get profileSelectMode => _pick('多选', 'Select', '選択');
  String get profileDeleteTitle =>
      _pick('删除词典档案？', 'Delete dictionary profile?', '辞書プロファイルを削除しますか？');
  String profileDeleteBody(int count) => _pick(
    '将删除 $count 个档案，下次分析时会重新生成并再次确认。不会修改你的词典文件。',
    'This deletes $count profile(s). They will be regenerated and confirmed on the next analysis. Your dictionary files are not modified.',
    '$count 件のプロファイルを削除します。次回の解析時に再生成し、再度確認します。辞書ファイルは変更しません。',
  );
  String get profileDeleted =>
      _pick('档案已删除', 'Profile deleted', 'プロファイルを削除しました');
  String get profileUpdated =>
      _pick('档案已更新', 'Profile updated', 'プロファイルを更新しました');
  String get profileUpdatedRestart => _pick(
    '档案已更新，请重新开始分析',
    'Profile updated. Start the analysis again.',
    'プロファイルを更新しました。解析をやり直してください。',
  );
  String get profileRegenerateNeedsProvider => _pick(
    '请先在设置中配置模型服务，再重新生成档案',
    'Configure a model service in settings before regenerating profiles',
    'プロファイルを再生成する前に設定でモデルサービスを構成してください',
  );
  String get profileActionsDisabledWhileRunning => _pick(
    '分析进行中，暂不能修改词典档案',
    'Profiles cannot be changed while an analysis is running',
    '解析中は辞書プロファイルを変更できません',
  );
  String get profileRegenerateStarted => _pick(
    '正在重新生成档案，请稍候',
    'Regenerating profiles, please wait',
    'プロファイルを再生成しています。お待ちください。',
  );
  String get profileRegenerateFailed =>
      _pick('档案重新生成失败', 'Profile regeneration failed', 'プロファイルの再生成に失敗しました');
  String get profileMarkdownMissing => _pick(
    '该档案没有可编辑的正文，请重新生成',
    'This profile has no editable body; regenerate it instead',
    'このプロファイルには編集可能な本文がありません。再生成してください。',
  );
  String get profileOpen => _pick('处理', 'Review', '処理');

  // Agent settings page.
  String get settingsTitle =>
      _pick('词典助手设置', 'Dictionary Assistant settings', '辞書アシスタント設定');
  String get profileLanguageTitle =>
      _pick('词典档案语言', 'Dictionary profile language', '辞書プロファイルの言語');
  String get profileLanguageBody => _pick(
    '模型生成的词典用途/结构说明使用哪种语言；日文词条与读音保持原文。默认中文。切换语言后会重新生成未匹配的档案。',
    'Language used for generated dictionary structure notes. Japanese headwords and readings stay as-is. Defaults to Chinese. Existing profiles are regenerated when this changes.',
    '生成される辞書の用途・構造説明の言語です。日本語の見出しと読みはそのまま残ります。既定は中国語です。変更すると既存プロファイルは再生成されます。',
  );
  String get profileLanguageLabel =>
      _pick('档案主体语言', 'Profile language', 'プロファイル言語');
  String get answerLanguageLabel => _pick('回答语言', 'Answer language', '回答言語');
  String get autoAcceptProfiles => _pick(
    '生成词典档案时不再询问',
    'Do not ask when generating dictionary profiles',
    '辞書プロファイル生成時に確認しない',
  );
  String get autoAcceptProfilesBody => _pick(
    '开启后，新生成的词典档案会自动保存并信任；仍可在“词典档案”中修改或重新生成。',
    'When enabled, newly generated dictionary profiles are saved and trusted automatically. You can still edit or regenerate them under “Dictionary profiles”.',
    '有効にすると、生成された辞書プロファイルは自動的に保存・信頼されます。「辞書プロファイル」から編集・再生成できます。',
  );
  String get modelServicesTitle => _pick('模型服务', 'Model services', 'モデルサービス');
  String get secretBody => _pick(
    'API Key 只保存在 Android 安全存储中，不会写入 SharedPreferences、日志或导出文件。图片仍只在本机 OCR，不会上传。',
    'API keys are stored only in Android secure storage; they are never written to SharedPreferences, logs or exports. Images are OCRed on-device and never uploaded.',
    'API キーは Android のセキュアストレージにのみ保存され、SharedPreferences・ログ・エクスポートには書き込まれません。画像は端末内で OCR され、アップロードされません。',
  );
  String get providerLoadFailed =>
      _pick('读取模型配置失败', 'Failed to load model settings', 'モデル設定の読み込みに失敗しました');
  String get noProviders => _pick(
    '还没有配置模型。添加一个 DeepSeek、Claude 或其他 OpenAI 兼容服务后即可使用词典助手。',
    'No model configured yet. Add DeepSeek, Claude or another OpenAI-compatible service to use the assistant.',
    'モデルが未設定です。DeepSeek、Claude、その他の OpenAI 互換サービスを追加してください。',
  );
  String get addProvider => _pick('添加模型服务', 'Add model service', 'モデルサービスを追加');
  String get editProvider =>
      _pick('编辑模型服务', 'Edit model service', 'モデルサービスを編集');
  String get deleteProviderTitle =>
      _pick('删除模型服务', 'Delete model service', 'モデルサービスを削除');
  String deleteProviderBody(String name) => _pick(
    '确定删除「$name」及其 API Key 吗？',
    'Delete “$name” and its API key?',
    '「$name」と API キーを削除しますか？',
  );
  String get providerSaved =>
      _pick('模型配置已保存', 'Model settings saved', 'モデル設定を保存しました');
  String get providerDeleted =>
      _pick('已删除模型服务', 'Model service deleted', 'モデルサービスを削除しました');
  String get providerName => _pick('名称', 'Name', '名前');
  String get unnamedProvider =>
      _pick('未命名模型服务', 'Unnamed model service', '名前のないモデルサービス');
  String get providerPreset => _pick('服务商', 'Provider', 'プロバイダー');
  String get otherCompatibleProvider => _pick(
    '其他 OpenAI 兼容服务',
    'Other OpenAI-compatible service',
    'その他の OpenAI 互換サービス',
  );
  String get providerBaseUrl => _pick('接口地址', 'API address', 'API アドレス');
  String get providerSmallModel => _pick('快速模型', 'Fast model', '高速モデル');
  String get providerComplexModel =>
      _pick('高精度模型', 'High-accuracy model', '高精度モデル');
  String get providerSmallModelSummary => _pick('简单模型', 'Fast model', '高速モデル');
  String get providerComplexModelSummary =>
      _pick('复杂模型', 'Complex model', '複雑モデル');
  String get providerApiKey => _pick('接口密钥（API Key）', 'API key', 'API キー');
  String get providerApiKeyKeep =>
      _pick('留空则不修改', 'Leave blank to keep', '空欄なら変更しません');
  String get providerSmallModelHelp => _pick(
    '快速模型用于词典档案和资料检查。',
    'The fast model is used for dictionary profiles and evidence checks.',
    '高速モデルは辞書プロファイルと資料確認に使います。',
  );
  String get providerComplexModelHelp => _pick(
    '高精度模型用于最终解析。',
    'The high-accuracy model is used for the final analysis.',
    '高精度モデルは最終解析に使います。',
  );
  String get save => _pick('保存', 'Save', '保存');
  String get delete => _pick('删除', 'Delete', '削除');

  // Stage/progress copy.
  String stageMessage(AgentStage stage) => switch (stage) {
    AgentStage.prepare => _pick('准备输入', 'Preparing', '入力を準備中'),
    AgentStage.ocr => _pick('本机 OCR', 'On-device OCR', '端末内 OCR'),
    AgentStage.familiarizing => _pick(
      '熟悉词典',
      'Reading dictionary profiles',
      '辞書情報を確認中',
    ),
    AgentStage.awaitingProfile => awaitingProfiles,
    AgentStage.tokenizing => _pick(
      '分词与检索依据',
      'Tokenizing and retrieving evidence',
      '形態素解析と根拠検索',
    ),
    AgentStage.evidence => _pick(
      '整理词典依据',
      'Organizing dictionary evidence',
      '辞書根拠を整理中',
    ),
    AgentStage.coverage => _pick('补充资料中', 'Checking coverage', '資料を補完中'),
    AgentStage.reasoning => _pick('生成结果', 'Generating', '生成中'),
    AgentStage.validating => _pick('校验依据', 'Validating citations', '根拠を検証中'),
    AgentStage.done => _pick('完成', 'Done', '完了'),
    AgentStage.cancelled => _pick('已停止', 'Stopped', '停止しました'),
    AgentStage.error => _pick('Agent 运行失败', 'Agent failed', '実行に失敗しました'),
  };

  String get repairing =>
      _pick('修复格式与引用', 'Repairing format and citations', '形式と引用を修正中');
  String get thinkingFallback => _pick('模型思考中…', 'Thinking…', '思考中…');
  List<String> get progressStepLabels => switch (language) {
    AgentUiLanguage.chinese => const <String>['OCR', '查词', '生成', '校验'],
    AgentUiLanguage.english => const <String>[
      'OCR',
      'Lookup',
      'Generate',
      'Validate',
    ],
    AgentUiLanguage.japanese => const <String>['OCR', '検索', '生成', '検証'],
  };
  String evidenceProgressLabel(
    int evidenceCount,
    int citationCount,
    int maxEvidenceEntries,
  ) {
    if (citationCount > 0) {
      return _pick(
        '已检索 $evidenceCount / $maxEvidenceEntries 条词典条目，采用 $citationCount 条依据',
        '$evidenceCount / $maxEvidenceEntries dictionary entries retrieved, '
            '$citationCount citations used',
        '辞書項目 $evidenceCount / $maxEvidenceEntries 件を検索、'
            '根拠 $citationCount 件を採用',
      );
    }
    return _pick(
      '已检索 $evidenceCount / $maxEvidenceEntries 条词典条目',
      '$evidenceCount / $maxEvidenceEntries dictionary entries retrieved',
      '辞書項目 $evidenceCount / $maxEvidenceEntries 件を検索',
    );
  }

  String elapsedLabel(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final minutes = safe ~/ 60;
    final rest = (safe % 60).toString().padLeft(2, '0');
    return switch (language) {
      AgentUiLanguage.chinese =>
        safe < 60 ? '已思考 $safe 秒' : '已思考 $minutes 分 $rest 秒',
      AgentUiLanguage.english =>
        safe < 60
            ? 'Thinking for ${safe}s'
            : 'Thinking for ${minutes}m ${rest}s',
      AgentUiLanguage.japanese =>
        safe < 60 ? '思考中 $safe 秒' : '思考中 $minutes 分 $rest 秒',
    };
  }
}
