import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import 'github_backup_service.dart';

/// The result of comparing this device's known password-generation state
/// against whatever is currently in `password_state.json` on GitHub.
///
/// This is a SYNCHRONIZATION signal, not a security boundary. It answers
/// "does this device's local idea of the current password generation
/// match the shared account state" — nothing here proves, verifies, or
/// distributes any actual password, hash, or key material. See
/// [PasswordStateManager]'s class doc for what this file deliberately
/// does and does not protect against.
enum PasswordStateComparison {
  /// Local and remote generation and changeId match. Normal operation —
  /// pushes and pulls may proceed.
  synchronized,

  /// Remote generation is higher than local. Another device has rotated
  /// the password since this device last knew about it. This device
  /// must not push note content (it would be encrypted under a stale
  /// generation) and should tell the user their password is out of
  /// date rather than attempt to decrypt remote notes and quietly fail.
  behindRemote,

  /// Same generation number, but a different changeId. This means two
  /// devices independently rotated from the same base generation while
  /// each was unaware of the other's change — an offline-rotation fork.
  /// With the online-precondition rule enforced at rotation time, this
  /// should be unreachable in normal operation; it remains a distinct,
  /// explicit state rather than being silently treated as "behind" or
  /// "synchronized", because neither of those descriptions is accurate
  /// for a fork.
  conflict,

  /// Remote generation is LOWER than this device's own established
  /// local generation. This should never happen in normal operation —
  /// it means the shared state moved backwards (a reverted file, a
  /// restored old backup overwriting the current one, or some other
  /// external interference). This is NOT "synchronized" and must never
  /// be treated as such: a caller seeing this must fail closed (block
  /// push, block rotation) and must NOT attempt to repair it — not by
  /// overwriting the remote with the local generation, and not by
  /// lowering the local generation to match. Detection only; any actual
  /// repair/recovery behavior is a separate, deliberate decision.
  remoteStateBehind,

  /// No `password_state.json` exists on the remote, AND this device has
  /// no established local generation either (`localGeneration == 0`).
  /// This is the genuine first-ever-setup case — not a failure. The
  /// caller may treat this as "this device may establish the initial
  /// shared state." See [remoteStateMissing] for the DIFFERENT case
  /// where a device that previously had state sees the file vanish —
  /// that is deliberately NOT this value.
  noRemoteStateYet,

  /// No `password_state.json` exists on the remote, but this device HAS
  /// an established local generation (`localGeneration > 0`). Unlike
  /// [noRemoteStateYet], this is not a benign "first setup" situation —
  /// an established device is seeing the shared state disappear, which
  /// could mean the file was deleted, the repository was reset, or
  /// something is wrong with the backup. Must fail closed (block push,
  /// block rotation) and must NOT be treated as license to silently
  /// recreate/reset the shared state — detection only.
  remoteStateMissing,

  /// The remote state could not be read at all (offline, GitHub
  /// unreachable, auth failure, malformed file). Distinct from
  /// [behindRemote]/[conflict] because those require the file to have
  /// been successfully read and understood. A caller enforcing the
  /// online-rotation precondition (constraint: rotation requires a
  /// successful check) must treat this the same as "check failed" and
  /// refuse to proceed with rotation.
  checkFailed,
}

/// Outcome of [PasswordStateManager.reconcilePendingPublish].
/// Why a password-state publish is currently pending. These are
/// genuinely different situations, not just different log messages:
/// one is safe for automatic background reconciliation to resolve on
/// its own, the other must NOT be auto-resolved because doing so would
/// publish a generation bump before the cross-device recovery artifact
/// (device_key.json) it depends on actually exists.
enum PendingReason {
  /// The publish attempt itself was unconfirmed (network failure,
  /// ambiguous timeout, or a rejected conditional write that turned out
  /// — per reconciliation — to still need a retry). device_key.json
  /// WAS already successfully updated for the new password before this
  /// publish was attempted. Safe for
  /// [PasswordStateManager.reconcilePendingPublish] to automatically
  /// retry.
  publishUnconfirmed,

  /// device_key.json is NOT yet updated for the new password — either
  /// the user declined the recovery-phrase re-entry step, or the upload
  /// itself failed. Automatic reconciliation must NOT attempt to
  /// publish this generation, because doing so would let other devices
  /// observe a password change they cannot actually recover from yet.
  /// Requires the user to complete the device-key step (re-run the
  /// recovery-phrase confirmation, or retry the upload) before this can
  /// ever be published — never resolved by background retry alone.
  deviceKeyNotReady,
}

enum ReconciliationOutcome {
  /// No pending publish existed — nothing to do.
  nothingPending,

  /// The pending publish is confirmed to have actually succeeded
  /// (remote already shows exactly the pending generation/changeId).
  /// Local known state has been advanced and pending cleared.
  confirmedSucceeded,

  /// The pending publish is confirmed lost — another device's write
  /// won. Local state has been marked orphaned; pending is cleared
  /// (it is no longer "pending," it is now a resolved conflict
  /// requiring explicit user action).
  confirmedLostToNewerDevice,

  /// Same generation, different changeId on remote than what this
  /// device pended — a genuine simultaneous-write conflict, not a
  /// simple "someone was ahead" case. Same field handling as
  /// [confirmedLostToNewerDevice] — orphaned, pending cleared.
  confirmedConflict,

  /// Remote still showed the OLD (pre-rotation) state — this device's
  /// write genuinely never landed. Retried the conditional publish
  /// using a freshly-read parent SHA, and that retry SUCCEEDED. Local
  /// known state has been advanced and pending cleared.
  retriedPublishSucceeded,

  /// Same as [retriedPublishSucceeded]'s precondition, but the retry
  /// itself also failed. Remains pending for a future attempt — NOT
  /// orphaned, since we still have no evidence anyone else has won;
  /// we've only failed twice in a row to confirm our own write.
  retriedPublishFailed,

  /// The remote state could not be read at all during reconciliation
  /// (offline, etc). Pending remains exactly as it was — no field
  /// changes, no orphaning, no local state advancement. Safe to
  /// retry again on the next opportunity.
  checkFailed,

  /// Reconciliation was not attempted at all because the pending
  /// reason is [PendingReason.deviceKeyNotReady] — publishing is
  /// blocked until the user completes the device-key step. This is
  /// distinct from every other outcome: it means "nothing was even
  /// tried," not "something was tried and didn't resolve."
  blockedOnDeviceKey,
}

/// Whether this device's local rotation was left in a state that
/// requires explicit user resolution before any further account writes.
/// Distinct from the ordinary [PasswordStateComparison] states because
/// it can be true even when a fresh [PasswordStateManager.checkState]
/// call would otherwise report `behindRemote` or even `synchronized` —
/// this flag specifically means "this device already committed a local
/// password change/note re-encryption that did not end up reflected in
/// the account's shared state," which is a strictly worse situation
/// than ordinary staleness (see the reconciliation design).
class LocalRotationOrphanStatus {
  static const String _boxName = 'rocen_settings_box';
  static const String _keyOrphaned = 'local_rotation_orphaned';

  static bool isOrphaned() {
    final box = Hive.box(_boxName);
    return box.get(_keyOrphaned, defaultValue: false);
  }

  static Future<void> setOrphaned(bool value) async {
    final box = Hive.box(_boxName);
    await box.put(_keyOrphaned, value);
  }
}

/// Outcome of a comparison, bundled with the shared-state fields a
/// caller needs to act on it (e.g. to show "changed on <device> at
/// <time>", or to compute the next generation/changeId when rotating).
class PasswordStateResult {
  final PasswordStateComparison comparison;
  final int? remoteGeneration;
  final String? remoteChangeId;
  final DateTime? remoteChangedAt;
  final String? remoteChangedByDeviceId;

  /// The branch ref SHA observed at the moment this state was read.
  /// Callers that go on to WRITE a new `password_state.json` (i.e. a
  /// device performing a rotation) must pass this exact value as
  /// `expectedParentSha` to
  /// [GithubBackupService.updateFileWithFastForwardCheck], so the write
  /// is conditioned on nothing having changed since this read.
  final String? observedRefSha;

  const PasswordStateResult({
    required this.comparison,
    this.remoteGeneration,
    this.remoteChangeId,
    this.remoteChangedAt,
    this.remoteChangedByDeviceId,
    this.observedRefSha,
  });
}

/// Manages the shared, cross-device password-generation state and this
/// device's own local record of it.
///
/// WHAT THIS FILE IS: a way for a device to detect, BEFORE attempting to
/// decrypt anything or push any note content, whether its locally-known
/// password generation matches what the account's other device(s) most
/// recently established — so a stale device gets a clear "your password
/// is out of date" state instead of silently failing decryption or
/// silently uploading ciphertext encrypted under an obsolete generation.
///
/// WHAT THIS FILE DELIBERATELY IS NOT:
/// - It does not store, transmit, or derive the password, a password
///   hash, the recovery phrase, or any encryption key. The synced file
///   contains only a generation counter, a random change-identifier, an
///   informational timestamp, and which device made the change.
/// - It is not a security/authentication boundary. `password_state.json`
///   is a plain, unsigned file on GitHub. Anyone with write access to
///   the repository could edit it to claim a false generation number.
///   The consequence of such tampering is a false "your password is out
///   of date" prompt (an availability/annoyance problem) — it cannot be
///   used to extract, weaken, or bypass the actual password or note
///   encryption, since none of that lives in this file. Anyone with
///   write access to the repository already has the ability to delete
///   or corrupt the real encrypted notes directly, which is a strictly
///   larger problem this file was never meant to solve.
/// - It does not, by itself, let a stale device recover another
///   device's new password. See [PasswordStateComparison.behindRemote]
///   doc and the recovery-flow integration in settings.dart: a stale
///   device still needs the user to know the current password and use
///   the recovery phrase to reconstruct the authentication salt. This
///   manager only detects staleness; it never distributes secrets.
class PasswordStateManager {
  static const String fileName = 'password_state.json';
  static const String _boxName = 'rocen_settings_box';

  static const String _keyDeviceId = 'device_id';
  static const String _keyKnownGeneration = 'known_password_generation';
  static const String _keyKnownChangeId = 'known_password_change_id';
  static const String _keyLastBackupSyncAt = 'last_backup_sync_at';
  static const String _keyRegisteredAt = 'device_registered_at';
  static const String _keyPublishPending = 'password_state_publish_pending';
  static const String _keyPendingGeneration =
      'password_state_pending_generation';
  static const String _keyPendingChangeId = 'password_state_pending_change_id';
  static const String _keyPendingReason = 'password_state_pending_reason';

  /// This device's stable identifier. Generated once, on first use, and
  /// persisted locally — never regenerated for the lifetime of the
  /// install. Not a secret; purely a label used in `changedByDeviceId`
  /// and the device registry for user-facing diagnostics (e.g. "changed
  /// on <this string>").
  static String getOrCreateDeviceId() {
    final box = Hive.box(_boxName);
    final String? existing = box.get(_keyDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;

    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final String deviceId = 'device-$hex';
    box.put(_keyDeviceId, deviceId);
    if (box.get(_keyRegisteredAt) == null) {
      box.put(_keyRegisteredAt, DateTime.now().toIso8601String());
    }
    return deviceId;
  }

  /// Generates a fresh, random change identifier for a new rotation.
  /// Deliberately independent randomness (not derived from the
  /// generation number or any other value) so that two devices
  /// rotating from the same base generation while offline produce
  /// different changeIds with overwhelming probability — this is what
  /// makes a same-generation-different-changeId FORK detectable at all,
  /// per the offline-conflict analysis this design is built around.
  static String generateChangeId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// This device's locally-known generation, or 0 if never set (a device
  /// that has never observed any shared state — e.g. brand new install
  /// with no prior rotation on this account).
  static int getKnownGeneration() {
    final box = Hive.box(_boxName);
    return box.get(_keyKnownGeneration, defaultValue: 0);
  }

  static String? getKnownChangeId() {
    final box = Hive.box(_boxName);
    return box.get(_keyKnownChangeId);
  }

  /// Records that this device now knows about a given generation/changeId
  /// as current — called after a successful rotation (by the device that
  /// performed it) or after a successful recovery-phrase-based
  /// reconciliation (by a device that was behind and has now caught up).
  static Future<void> recordKnownState({
    required int generation,
    required String changeId,
  }) async {
    final box = Hive.box(_boxName);
    await box.put(_keyKnownGeneration, generation);
    await box.put(_keyKnownChangeId, changeId);
  }

  static Future<void> recordBackupSyncNow() async {
    final box = Hive.box(_boxName);
    await box.put(_keyLastBackupSyncAt, DateTime.now().toIso8601String());
  }

  static bool isPublishPending() {
    final box = Hive.box(_boxName);
    return box.get(_keyPublishPending, defaultValue: false);
  }

  /// The reason the current pending publish (if any) is pending. Null
  /// if nothing is pending. Callers MUST check this before assuming a
  /// pending publish is safe for automatic retry — see [PendingReason].
  static PendingReason? getPendingReason() {
    final box = Hive.box(_boxName);
    final String? raw = box.get(_keyPendingReason);
    if (raw == null) return null;
    return PendingReason.values.firstWhere(
      (r) => r.name == raw,
      orElse: () => PendingReason.publishUnconfirmed,
    );
  }

  /// Records that a rotation's shared-state publish is pending, and WHY
  /// — this is not optional bookkeeping, it is what determines whether
  /// [reconcilePendingPublish] is allowed to automatically retry.
  /// Persisted — this must survive an app restart, since reconciliation
  /// on next launch/sync depends on knowing exactly which (generation,
  /// changeId, reason) triple was pending.
  static Future<void> setPublishPending({
    required int pendingGeneration,
    required String pendingChangeId,
    required PendingReason reason,
  }) async {
    final box = Hive.box(_boxName);
    await box.put(_keyPublishPending, true);
    await box.put(_keyPendingGeneration, pendingGeneration);
    await box.put(_keyPendingChangeId, pendingChangeId);
    await box.put(_keyPendingReason, reason.name);
  }

  static Future<void> clearPublishPending() async {
    final box = Hive.box(_boxName);
    await box.put(_keyPublishPending, false);
    await box.delete(_keyPendingGeneration);
    await box.delete(_keyPendingChangeId);
    await box.delete(_keyPendingReason);
  }

  static int? getPendingGeneration() {
    final box = Hive.box(_boxName);
    return box.get(_keyPendingGeneration);
  }

  static String? getPendingChangeId() {
    final box = Hive.box(_boxName);
    return box.get(_keyPendingChangeId);
  }

  /// Fetches the current shared state from GitHub and compares it
  /// against this device's locally-known generation/changeId. Does not
  /// write anything, locally or remotely — pure read + compare.
  ///
  /// This is the function both the push-time and pull-time checks call
  /// before doing anything else with note content, and the function the
  /// rotation flow calls as its mandatory online precondition.
  static Future<PasswordStateResult> checkState(
      GithubBackupService service) async {
    final int localGeneration = getKnownGeneration();
    final String? localChangeId = getKnownChangeId();

    final ({Map<String, dynamic>? content, String? refSha}) fetched;
    try {
      fetched = await service.fetchNoteFileWithRefSha(fileName);
    } catch (_) {
      return const PasswordStateResult(
          comparison: PasswordStateComparison.checkFailed);
    }

    if (fetched.content == null) {
      // Distinguish "this device has never had a generation" (genuine
      // first-ever setup — benign) from "this device previously had an
      // established generation and the shared state has now vanished"
      // (not benign — could be a deleted file, a reset repository, or
      // something wrong with the backup). Deliberately does NOT attempt
      // to repair either case; this is detection only.
      return PasswordStateResult(
        comparison: localGeneration == 0
            ? PasswordStateComparison.noRemoteStateYet
            : PasswordStateComparison.remoteStateMissing,
        observedRefSha: fetched.refSha,
      );
    }

    final Map<String, dynamic> remote = fetched.content!;
    final int? remoteGeneration = remote['passwordGeneration'] as int?;
    final String? remoteChangeId = remote['passwordChangeId'] as String?;
    final String? remoteChangedAtRaw = remote['passwordChangedAt'] as String?;
    final String? remoteChangedByDeviceId =
        remote['changedByDeviceId'] as String?;

    if (remoteGeneration == null || remoteChangeId == null) {
      // Malformed file — treat the same as unreadable, since we cannot
      // safely compare against fields that aren't present in the shape
      // we expect. This is deliberately conservative: a device should
      // never proceed with rotation or a push on the strength of a file
      // it couldn't fully parse.
      return const PasswordStateResult(
          comparison: PasswordStateComparison.checkFailed);
    }

    final DateTime? remoteChangedAt = remoteChangedAtRaw != null
        ? DateTime.tryParse(remoteChangedAtRaw)
        : null;

    final PasswordStateComparison comparison;
    if (remoteGeneration > localGeneration) {
      comparison = PasswordStateComparison.behindRemote;
    } else if (remoteGeneration == localGeneration &&
        localChangeId != null &&
        remoteChangeId != localChangeId) {
      comparison = PasswordStateComparison.conflict;
    } else if (remoteGeneration < localGeneration) {
      // Remote is BEHIND this device's own established generation.
      // Should never happen in normal operation — the shared state has
      // moved backwards relative to what this device already knows.
      // Deliberately fail-closed: do not treat this as synchronized,
      // do not overwrite the remote with the local (higher) generation,
      // and do not lower the local generation to match. Detection only.
      comparison = PasswordStateComparison.remoteStateBehind;
    } else {
      // remoteGeneration == localGeneration and changeId matches (or
      // this device has no local changeId recorded yet, e.g. first-ever
      // check on a device that already knows the right generation via
      // some other path) — treated as synchronized. Note: generation is
      // authoritative per the approved design; a missing local changeId
      // does not by itself trigger a conflict.
      comparison = PasswordStateComparison.synchronized;
    }

    return PasswordStateResult(
      comparison: comparison,
      remoteGeneration: remoteGeneration,
      remoteChangeId: remoteChangeId,
      remoteChangedAt: remoteChangedAt,
      remoteChangedByDeviceId: remoteChangedByDeviceId,
      observedRefSha: fetched.refSha,
    );
  }

  /// Writes a new shared state reflecting a rotation this device just
  /// performed, using the real fast-forward conditional write — NOT the
  /// force-push path used for notes. `expectedParentSha` must be the
  /// `observedRefSha` from the [PasswordStateResult] this rotation's
  /// precondition check already obtained; if the branch moved since
  /// then, this throws [GithubConditionalWriteConflict] and the caller
  /// must treat the rotation as unable to safely publish its result
  /// (the local password change should not be presented to the user as
  /// complete/synced in that case — see settings.dart integration).
  static Future<void> publishNewState({
    required GithubBackupService service,
    required int newGeneration,
    required String newChangeId,
    required String deviceId,
    required String? expectedParentSha,
  }) async {
    final String nowIso = DateTime.now().toUtc().toIso8601String();
    final String json = '{'
        '"passwordGeneration":$newGeneration,'
        '"passwordChangeId":"$newChangeId",'
        '"passwordChangedAt":"$nowIso",'
        '"changedByDeviceId":"$deviceId"'
        '}';

    await service.updateFileWithFastForwardCheck(
      path: fileName,
      content: json,
      message: 'password rotation - generation $newGeneration',
      expectedParentSha: expectedParentSha,
    );
  }

  /// Must be called before any note push, and is also the correct thing
  /// to call once at app launch if [isPublishPending] is true. This is
  /// idempotent by design: calling it when the previous publish attempt
  /// actually succeeded (but this device never received/processed that
  /// confirmation) safely detects the success and finalizes locally,
  /// rather than incorrectly treating a successful-but-unconfirmed write
  /// as a failure and retrying it (which could otherwise manufacture a
  /// spurious conflict against its OWN earlier, successful write).
  static Future<ReconciliationOutcome> reconcilePendingPublish(
      GithubBackupService service) async {
    if (!isPublishPending()) return ReconciliationOutcome.nothingPending;

    // CRITICAL: if this device is pending specifically because
    // device_key.json isn't ready for the new password, automatic
    // reconciliation must not attempt to publish — doing so would let
    // other devices observe a generation bump before the artifact they
    // need to recover exists, which is exactly the consistency problem
    // this whole mechanism was built to prevent. This state can ONLY be
    // cleared by the user completing the device-key step (see
    // settings.dart's recovery-setup-incomplete flow) — never by
    // background retry.
    final PendingReason? reason = getPendingReason();
    if (reason == PendingReason.deviceKeyNotReady) {
      return ReconciliationOutcome.blockedOnDeviceKey;
    }

    final int? pendingGeneration = getPendingGeneration();
    final String? pendingChangeId = getPendingChangeId();
    if (pendingGeneration == null || pendingChangeId == null) {
      // Inconsistent local state (pending flag set but no pending
      // values recorded) — clear the flag defensively rather than get
      // stuck. This should not happen if setPublishPending/
      // clearPublishPending are always used together, but a corrupted
      // Hive write is not impossible.
      await clearPublishPending();
      return ReconciliationOutcome.nothingPending;
    }

    final int oldLocalGeneration = getKnownGeneration();
    final String? oldLocalChangeId = getKnownChangeId();

    final ({Map<String, dynamic>? content, String? refSha}) fetched;
    try {
      fetched = await service.fetchNoteFileWithRefSha(fileName);
    } catch (_) {
      return ReconciliationOutcome.checkFailed;
    }

    final Map<String, dynamic>? remote = fetched.content;
    final int? remoteGeneration = remote?['passwordGeneration'] as int?;
    final String? remoteChangeId = remote?['passwordChangeId'] as String?;

    if (remoteGeneration == null || remoteChangeId == null) {
      return ReconciliationOutcome.checkFailed;
    }

    // Case: remote already reflects exactly what we tried to publish —
    // our write actually succeeded; only the confirmation was lost.
    if (remoteGeneration == pendingGeneration &&
        remoteChangeId == pendingChangeId) {
      await recordKnownState(
          generation: pendingGeneration, changeId: pendingChangeId);
      await clearPublishPending();
      return ReconciliationOutcome.confirmedSucceeded;
    }

    // Case: someone else's generation is now ahead of our OLD local
    // generation (not the pending one) — they won, we lost.
    if (remoteGeneration > oldLocalGeneration) {
      await LocalRotationOrphanStatus.setOrphaned(true);
      await clearPublishPending();
      return ReconciliationOutcome.confirmedLostToNewerDevice;
    }

    // Case: remote still shows EXACTLY the old state this device
    // started from before its own pending rotation. This is the
    // completely normal "our write hasn't landed yet" case — NOT a
    // conflict. It's easy to misclassify this: remoteChangeId here is
    // guaranteed to differ from pendingChangeId (pendingChangeId is a
    // freshly-generated value nobody has published yet), so a check
    // that only compares against pendingChangeId would wrongly treat
    // this ordinary, expected state as a conflict — which is exactly
    // the bug this comparison is written to avoid. Falls through to
    // the retry logic below using a FRESH parent SHA (never reuse the
    // original observedRefSha; time has passed and it may be stale).
    if (remoteGeneration == oldLocalGeneration &&
        remoteChangeId == oldLocalChangeId) {
      try {
        final String deviceId = getOrCreateDeviceId();
        await publishNewState(
          service: service,
          newGeneration: pendingGeneration,
          newChangeId: pendingChangeId,
          deviceId: deviceId,
          expectedParentSha: fetched.refSha,
        );
        await recordKnownState(
            generation: pendingGeneration, changeId: pendingChangeId);
        await clearPublishPending();
        return ReconciliationOutcome.retriedPublishSucceeded;
      } catch (_) {
        // Retry failed again (could be another race, could be another
        // network failure). Remains pending for the next opportunity —
        // deliberately NOT marked orphaned here, since we still don't
        // have confirmation anyone else has actually won; we've only
        // failed to confirm our own write, which is the same ambiguous
        // state as before this reconciliation attempt.
        return ReconciliationOutcome.retriedPublishFailed;
      }
    }

    // Case: same generation as our old local value, but the remote
    // changeId is neither our OLD changeId (handled above, that's the
    // normal retry case) nor our PENDING changeId (handled at the top,
    // that's our own success) — a genuine third-party conflict:
    // another device rotated from the same base generation we did.
    await LocalRotationOrphanStatus.setOrphaned(true);
    await clearPublishPending();
    return ReconciliationOutcome.confirmedConflict;
  }

  /// The three-condition push gate: a note push may proceed ONLY if
  /// none of these hold: a publish is still pending confirmation, this
  /// device's local rotation has been orphaned, or a fresh state check
  /// shows this device's generation/changeId no longer matches remote.
  /// All three must be checked — clearing `passwordStatePublishPending`
  /// does not by itself mean push is safe again if the device was
  /// marked orphaned in the process (see reconcilePendingPublish above).
  /// The three-condition push gate: a note push may proceed ONLY if
  /// none of these hold: a publish is still pending confirmation, this
  /// device's local rotation has been orphaned, or a fresh state check
  /// shows this device's generation/changeId no longer matches remote.
  /// All three must be checked — clearing `passwordStatePublishPending`
  /// does not by itself mean push is safe again if the device was
  /// marked orphaned in the process (see reconcilePendingPublish above).
  ///
  /// The allow-list below is intentionally an ALLOW-list, not a
  /// block-list: only [PasswordStateComparison.synchronized] and
  /// [PasswordStateComparison.noRemoteStateYet] permit a push.
  /// [PasswordStateComparison.remoteStateBehind] and
  /// [PasswordStateComparison.remoteStateMissing] are therefore
  /// EXCLUDED BY DESIGN, not by accidental omission — a push must never
  /// proceed while either of those fail-closed states is active, and
  /// using an allow-list here (rather than enumerating everything to
  /// block) means a future comparison state added to the enum is
  /// blocked by default unless someone deliberately adds it here.
  static Future<bool> isPushAllowed(GithubBackupService service) async {
    if (isPublishPending()) return false;
    if (LocalRotationOrphanStatus.isOrphaned()) return false;

    final PasswordStateResult result = await checkState(service);
    return result.comparison == PasswordStateComparison.synchronized ||
        result.comparison == PasswordStateComparison.noRemoteStateYet;
  }
}