/// Stable error codes shared by the Agent pipeline and provider adapters.
///
/// The model has no tools in the current fixed pipeline, but these codes are
/// the single vocabulary for run failures shown in the UI and stored in
/// snapshots.
enum AgentToolErrorCode {
  notConfigured('NOT_CONFIGURED'),
  modelMissing('MODEL_MISSING'),
  modelInvalid('MODEL_INVALID'),
  dictionaryNotReady('DICTIONARY_NOT_READY'),
  dictionaryLookupFailed('DICTIONARY_LOOKUP_FAILED'),
  unidicNotReady('UNIDIC_NOT_READY'),
  toolTimeout('TOOL_TIMEOUT'),
  toolCancelled('TOOL_CANCELLED'),
  invalidArguments('INVALID_ARGUMENTS'),
  providerAuthFailed('PROVIDER_AUTH_FAILED'),
  providerRateLimited('PROVIDER_RATE_LIMITED'),
  providerUnavailable('PROVIDER_UNAVAILABLE'),
  validationFailed('VALIDATION_FAILED'),
  internalError('INTERNAL_ERROR');

  const AgentToolErrorCode(this.wireName);

  final String wireName;

  static AgentToolErrorCode fromWire(Object? value) {
    for (final code in AgentToolErrorCode.values) {
      if (code.wireName == value) return code;
    }
    return AgentToolErrorCode.internalError;
  }
}
