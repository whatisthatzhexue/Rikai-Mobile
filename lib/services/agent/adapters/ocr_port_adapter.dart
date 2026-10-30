import 'package:rikai_ocr/rikai_ocr.dart';

import '../../../core/models/agent/agent_tool.dart';
import '../../../core/models/ocr_model.dart';
import '../../ocr/ocr_service.dart';
import '../../ocr/ocr_text_composer.dart';
import '../ports/agent_capability_exception.dart';
import '../ports/ocr_port.dart';
import 'agent_error_mapper.dart';

/// Adapts the app-lifetime [OcrService] to the Agent-facing [OcrPort].
class OcrPortAdapter implements OcrPort {
  OcrPortAdapter({
    required OcrService service,
    required Future<OcrModelManifest> Function() manifest,
  }) : _service = service,
       _manifest = manifest;

  final OcrService _service;
  final Future<OcrModelManifest> Function() _manifest;

  @override
  bool get horizontalAvailable => _service.paddleReady;

  @override
  bool get verticalAvailable => _service.mangaAvailable;

  @override
  Future<void> ensureReady() async {
    try {
      await _service.ensureReady(await _manifest());
    } catch (error) {
      throw mapAgentError(error, fallbackMessage: 'OCR 模型初始化失败');
    }
  }

  @override
  Future<OcrRun> recognize({
    required OcrHandle image,
    required OcrMode mode,
  }) async {
    if (image is! LocalOcrHandle) {
      throw const AgentCapabilityException(
        AgentToolErrorCode.invalidArguments,
        '图片句柄无效',
      );
    }
    try {
      await ensureReady();
      final result = await _service.recognize(
        imagePath: image.localPath,
        mode: mode,
      );
      final blocks = result.blocks;
      final average = blocks.isEmpty
          ? 0.0
          : blocks.fold<double>(0, (sum, block) => sum + block.confidence) /
                blocks.length;
      return OcrRun(
        engine: result.engine,
        mode: mode,
        text: composeOcrText(blocks),
        elapsedMs: result.elapsedMs,
        confidence: average,
        blocks: blocks,
      );
    } catch (error) {
      throw mapAgentError(error, fallbackMessage: 'OCR 识别失败');
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _service.cancel();
    } catch (error) {
      throw mapAgentError(error, fallbackMessage: '取消 OCR 失败');
    }
  }
}
