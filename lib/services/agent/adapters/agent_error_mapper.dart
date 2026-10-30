import 'dart:async';

import 'package:rikai_ocr/rikai_ocr.dart';

import '../../../core/models/agent/agent_tool.dart';
import '../../lookup/lookup_gateway.dart';
import '../../mdict/mdict_worker.dart';
import '../../mecab/mecab_service.dart';
import '../../ocr/model_manager.dart';
import '../ports/agent_capability_exception.dart';

/// Maps native/service errors to stable, path-free Agent codes.
AgentCapabilityException mapAgentError(
  Object error, {
  String fallbackMessage = '本机能力调用失败',
}) {
  if (error is AgentCapabilityException) return error;
  if (error is TimeoutException) {
    return AgentCapabilityException(
      AgentToolErrorCode.toolTimeout,
      '本机处理超时，请重试',
      cause: error,
    );
  }
  if (error is OcrModelException) {
    final missing = error.code == 'MODEL_MISSING';
    return AgentCapabilityException(
      missing
          ? AgentToolErrorCode.modelMissing
          : AgentToolErrorCode.modelInvalid,
      error.message,
      cause: error,
    );
  }
  if (error is OcrException) {
    final code = switch (error.code) {
      'MODEL_MISSING' => AgentToolErrorCode.modelMissing,
      'MODEL_INVALID' => AgentToolErrorCode.modelInvalid,
      'CANCELLED' => AgentToolErrorCode.toolCancelled,
      'BUSY' => AgentToolErrorCode.internalError,
      _ => AgentToolErrorCode.internalError,
    };
    return AgentCapabilityException(code, error.message, cause: error);
  }
  if (error is MecabException) {
    return AgentCapabilityException(
      AgentToolErrorCode.unidicNotReady,
      error.message,
      cause: error,
    );
  }
  if (error is MdictException) {
    final code = switch (error.code) {
      MdictErrorCode.fileNotFound ||
      MdictErrorCode.invalidDictionary ||
      MdictErrorCode.unsupportedFormat ||
      MdictErrorCode.encrypted => AgentToolErrorCode.dictionaryNotReady,
      MdictErrorCode.lookupFailed || MdictErrorCode.resourceFailed =>
        AgentToolErrorCode.dictionaryLookupFailed,
      MdictErrorCode.disposed => AgentToolErrorCode.internalError,
    };
    return AgentCapabilityException(code, error.message, cause: error);
  }
  if (error is LookupGatewayException) {
    return AgentCapabilityException(
      AgentToolErrorCode.dictionaryNotReady,
      error.message,
      cause: error,
    );
  }
  return AgentCapabilityException(
    AgentToolErrorCode.internalError,
    fallbackMessage,
    cause: error,
  );
}
