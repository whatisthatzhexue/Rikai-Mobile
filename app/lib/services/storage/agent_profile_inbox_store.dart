import '../agent/familiarization/dictionary_familiarization_service.dart'
    show AgentProfileProposal;

/// Persistence seam for profile proposals awaiting confirmation.
///
/// Pending proposals are not dictionary profiles yet: nothing is written to
/// `dictionary_profiles` until the user chooses save/skip/decline. This store
/// only keeps the queue alive across process death.
abstract interface class AgentProfileInboxPersistence {
  Future<List<AgentProfileProposal>> loadPendingProfiles();

  Future<void> savePendingProfile(AgentProfileProposal proposal);

  Future<void> deletePendingProfile(String id);

  Future<void> deletePendingProfilesForRun(String runId);
}
