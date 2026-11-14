/// Display copy for OCR model sets.
///
/// The manifest keeps only machine identifiers (id/license/url/files). User
/// visible names and license notes live here, keyed by set id, so the data
/// file never hardcodes Chinese/English/Japanese copy. This mirrors the
/// existing `AgentUiStrings` table; full app localization is still M1 work.
enum OcrModelCopyLanguage { zh, en, ja }

class OcrModelSetCopy {
  const OcrModelSetCopy({required this.displayName, this.licenseNote = ''});

  final String displayName;
  final String licenseNote;
}

abstract final class OcrModelCopy {
  static const OcrModelCopyLanguage defaultLanguage = OcrModelCopyLanguage.zh;

  static const Map<String, Map<OcrModelCopyLanguage, OcrModelSetCopy>> _copy =
      <String, Map<OcrModelCopyLanguage, OcrModelSetCopy>>{
        'paddle_v5': <OcrModelCopyLanguage, OcrModelSetCopy>{
          OcrModelCopyLanguage.zh: OcrModelSetCopy(
            displayName: 'PaddleOCR PP-OCRv5 横向模型（检测 + 识别 + 字符表）',
          ),
          OcrModelCopyLanguage.en: OcrModelSetCopy(
            displayName:
                'PaddleOCR PP-OCRv5 horizontal model (detection + recognition + charset)',
          ),
          OcrModelCopyLanguage.ja: OcrModelSetCopy(
            displayName: 'PaddleOCR PP-OCRv5 横向きモデル（検出 + 認識 + 文字セット）',
          ),
        },
        'manga_ocr': <OcrModelCopyLanguage, OcrModelSetCopy>{
          OcrModelCopyLanguage.zh: OcrModelSetCopy(
            displayName: 'MangaOCR 2025 竖排模型（编码器 + 解码器 + 词表）',
            licenseNote:
                '上游模型卡未声明许可证，请在使用前确认上游条款；也可导入自行转换的 ONNX 模型。',
          ),
          OcrModelCopyLanguage.en: OcrModelSetCopy(
            displayName:
                'MangaOCR 2025 vertical model (encoder + decoder + vocabulary)',
            licenseNote:
                'The upstream model card does not declare a license; confirm upstream terms before use. You may import your own converted ONNX model.',
          ),
          OcrModelCopyLanguage.ja: OcrModelSetCopy(
            displayName: 'MangaOCR 2025 縦書きモデル（エンコーダー + デコーダー + 語彙）',
            licenseNote:
                '上流のモデルカードにライセンスが明記されていません。使用前に上流の条件を確認してください。自分で変換した ONNX モデルをインポートすることもできます。',
          ),
        },
        'orientation': <OcrModelCopyLanguage, OcrModelSetCopy>{
          OcrModelCopyLanguage.zh: OcrModelSetCopy(
            displayName: 'PP-LCNet 方向识别模型（文档 / 文本行）',
          ),
          OcrModelCopyLanguage.en: OcrModelSetCopy(
            displayName: 'PP-LCNet orientation model (document / text line)',
          ),
          OcrModelCopyLanguage.ja: OcrModelSetCopy(
            displayName: 'PP-LCNet 方向判定モデル（文書 / テキスト行）',
          ),
        },
      };

  static OcrModelSetCopy of(
    String setId, {
    OcrModelCopyLanguage language = defaultLanguage,
  }) {
    final byLanguage = _copy[setId];
    if (byLanguage == null) {
      return OcrModelSetCopy(displayName: setId);
    }
    return byLanguage[language] ??
        byLanguage[defaultLanguage] ??
        OcrModelSetCopy(displayName: setId);
  }

  static String displayName(
    String setId, {
    OcrModelCopyLanguage language = defaultLanguage,
  }) => of(setId, language: language).displayName;

  static String licenseNote(
    String setId, {
    OcrModelCopyLanguage language = defaultLanguage,
  }) => of(setId, language: language).licenseNote;

  static String licenseLabel(
    String license, {
    OcrModelCopyLanguage language = defaultLanguage,
  }) {
    if (license != 'UNKNOWN') return license;
    switch (language) {
      case OcrModelCopyLanguage.zh:
        return '许可未声明';
      case OcrModelCopyLanguage.en:
        return 'License not declared';
      case OcrModelCopyLanguage.ja:
        return 'ライセンス未明記';
    }
  }

  static Iterable<String> get knownSetIds => _copy.keys;
}
