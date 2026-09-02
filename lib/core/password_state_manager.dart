import 'dart:convert';
import 'dart:math';
import 'package:Rocen/core/debug_log.dart' as debug_log;
import 'package:hive_flutter/hive_flutter.dart';
import 'github_backup_service.dart';
import 'debug_log.dart';

enum PasswordStateComparison {
  synchronized,
  behindRemote,
  conflict,
  remoteStateBehind,
  noRemoteStateYet,
  remoteStateMissing,
  checkFailed,
}

enum PendingReason {
  publishUnconfirmed,
  deviceKeyNotReady,
}

enum ReconciliationOutcome {
  nothingPending,
  confirmedSucceeded,
  confirmedLostToNewerDevice,
  confirmedConflict,
  retriedPublishSucceeded,
  retriedPublishFailed,
  checkFailed,
  blockedOnDeviceKey,
}

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

class PasswordStateResult {
  final PasswordStateComparison comparison;
  final int? remoteGeneration;
  final String? remoteChangeId;
  final DateTime? remoteChangedAt;
  final String? remoteChangedByDeviceId;
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

  static String generateChangeId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static int getKnownGeneration() {
    final box = Hive.box(_boxName);
    return box.get(_keyKnownGeneration, defaultValue: 0);
  }

  static String? getKnownChangeId() {
    final box = Hive.box(_boxName);
    return box.get(_keyKnownChangeId);
  }

  static Future<void> recordKnownState({
    required int generation,
    required String changeId,
  }) async {
    final box = Hive.box(_boxName);
    await box.put(_keyKnownGeneration, generation);
    await box.put(_keyKnownChangeId, changeId);
  }

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

  static Future<void> recordBackupSyncNow() async {
    final box = Hive.box(_boxName);
    await box.put(
      _keyLastBackupSyncAt,
      DateTime.now().toIso8601String(),
    );
  }

  static bool isPublishPending() {
    final box = Hive.box(_boxName);
    return box.get(_keyPublishPending, defaultValue: false);
  }

  static PendingReason? getPendingReason() {
    final box = Hive.box(_boxName);
    final String? raw = box.get(_keyPendingReason);
    if (raw == null) return null;
    return PendingReason.values.firstWhere(
      (r) => r.name == raw,
      orElse: () => PendingReason.publishUnconfirmed,
    );
  }

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
      comparison = PasswordStateComparison.remoteStateBehind;
    } else {
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

  static Future<void> initializeInitialState({
    required GithubBackupService service,
  }) async {
    final int initialGeneration = 1;
    final String initialChangeId = generateChangeId();
    final String deviceId = getOrCreateDeviceId();
    final ({
      Map<String, dynamic>? content,
      String? refSha,
    }) observed = await service.fetchNoteFileWithRefSha(fileName);

    if (observed.content != null) {
      throw GithubSyncException(
        'INITIAL PASSWORD STATE ALREADY EXISTS. '
        'REFUSING TO OVERWRITE EXISTING SHARED STATE.',
      );
    }
    if (observed.refSha == null) {
      throw GithubSyncException(
        'INITIAL PASSWORD STATE FAILED: '
        'repository branch is not initialized.',
      );
    }

    final Map<String, dynamic> initialState = {
      'passwordGeneration': initialGeneration,
      'passwordChangeId': initialChangeId,
      'passwordChangedAt': DateTime.now().toUtc().toIso8601String(),
      'changedByDeviceId': deviceId,
    };

    final String json = jsonEncode(initialState);
    await service.updateFileWithFastForwardCheck(
      path: fileName,
      content: json,
      message: 'initial password state',
      expectedParentSha: observed.refSha,
    );
    await recordKnownState(
      generation: initialGeneration,
      changeId: initialChangeId,
    );

    debug_log.secureDebugLog(
      '[password_state] initial shared state published successfully '
      '(generation=$initialGeneration, device=$deviceId)',
    );
  }

  static Future<ReconciliationOutcome> reconcilePendingPublish(
      GithubBackupService service) async {
    if (!isPublishPending()) return ReconciliationOutcome.nothingPending;

    final PendingReason? reason = getPendingReason();
    if (reason == PendingReason.deviceKeyNotReady) {
      return ReconciliationOutcome.blockedOnDeviceKey;
    }

    final int? pendingGeneration = getPendingGeneration();
    final String? pendingChangeId = getPendingChangeId();
    if (pendingGeneration == null || pendingChangeId == null) {
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
    if (remoteGeneration == pendingGeneration &&
        remoteChangeId == pendingChangeId) {
      await recordKnownState(
          generation: pendingGeneration, changeId: pendingChangeId);
      await clearPublishPending();
      return ReconciliationOutcome.confirmedSucceeded;
    }
    if (remoteGeneration > oldLocalGeneration) {
      await LocalRotationOrphanStatus.setOrphaned(true);
      await clearPublishPending();
      return ReconciliationOutcome.confirmedLostToNewerDevice;
    }

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
        return ReconciliationOutcome.retriedPublishFailed;
      }
    }
    await LocalRotationOrphanStatus.setOrphaned(true);
    await clearPublishPending();
    return ReconciliationOutcome.confirmedConflict;
  }

  static Future<bool> isPushAllowed(GithubBackupService service) async {
    if (isPublishPending()) return false;
    if (LocalRotationOrphanStatus.isOrphaned()) return false;

    final PasswordStateResult result = await checkState(service);
    return result.comparison == PasswordStateComparison.synchronized ||
        result.comparison == PasswordStateComparison.noRemoteStateYet;
  }
}
