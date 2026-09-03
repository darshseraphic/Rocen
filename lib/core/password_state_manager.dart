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

/// A registered device entry inside password_state.json.
///
/// deviceNumber is the stable human-facing membership number (1, 2, 3...).
/// deviceId remains the random per-installation identifier and is the real
/// unique identity used by Rocen internally.
class PasswordStateDevice {
  final int deviceNumber;
  final String deviceId;
  final int passwordGeneration;

  const PasswordStateDevice({
    required this.deviceNumber,
    required this.deviceId,
    required this.passwordGeneration,
  });

  factory PasswordStateDevice.fromJson(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('device entry is not an object');
    }

    final int? deviceNumber = raw['deviceNumber'] is int
        ? raw['deviceNumber'] as int
        : int.tryParse('${raw['deviceNumber'] ?? ''}');
    final String deviceId = (raw['deviceId'] ?? '').toString().trim();
    final int? generation = raw['passwordGeneration'] is int
        ? raw['passwordGeneration'] as int
        : int.tryParse('${raw['passwordGeneration'] ?? ''}');

    if (deviceNumber == null || deviceNumber < 1) {
      throw const FormatException('deviceNumber is invalid');
    }
    if (deviceId.isEmpty) {
      throw const FormatException('deviceId is empty');
    }
    if (generation == null || generation < 1) {
      throw const FormatException('device passwordGeneration is invalid');
    }

    return PasswordStateDevice(
      deviceNumber: deviceNumber,
      deviceId: deviceId,
      passwordGeneration: generation,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceNumber': deviceNumber,
        'deviceId': deviceId,
        'passwordGeneration': passwordGeneration,
      };
}

class PasswordStateResult {
  final PasswordStateComparison comparison;
  final int? remoteGeneration;
  final String? remoteChangeId;
  final DateTime? remoteChangedAt;
  final String? remoteChangedByDeviceId;
  final String? observedRefSha;
  final List<PasswordStateDevice> devices;

  const PasswordStateResult({
    required this.comparison,
    this.remoteGeneration,
    this.remoteChangeId,
    this.remoteChangedAt,
    this.remoteChangedByDeviceId,
    this.observedRefSha,
    this.devices = const <PasswordStateDevice>[],
  });
}

class PasswordStateManager {
  static const String fileName = 'password_state.json';
  static const String _boxName = 'rocen_settings_box';

  static const String _keyDeviceId = 'device_id';
  static const String _keyDeviceNumber = 'device_number';
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

  static int? getDeviceNumber() {
    final box = Hive.box(_boxName);
    final dynamic raw = box.get(_keyDeviceNumber);
    if (raw is int && raw > 0) return raw;
    return int.tryParse('${raw ?? ''}');
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

  static Future<void> _recordKnownStateAndDeviceNumber({
    required int generation,
    required String changeId,
    required int deviceNumber,
  }) async {
    final box = Hive.box(_boxName);
    await box.put(_keyKnownGeneration, generation);
    await box.put(_keyKnownChangeId, changeId);
    await box.put(_keyDeviceNumber, deviceNumber);
  }

  static List<PasswordStateDevice> _decodeDevices(Map<String, dynamic> state) {
    final dynamic raw = state['devices'];
    if (raw == null) return <PasswordStateDevice>[];
    if (raw is! List) {
      throw const FormatException('devices is not an array');
    }

    final List<PasswordStateDevice> devices =
        raw.map(PasswordStateDevice.fromJson).toList(growable: false);

    final Set<int> numbers = <int>{};
    final Set<String> ids = <String>{};
    for (final PasswordStateDevice device in devices) {
      if (!numbers.add(device.deviceNumber)) {
        throw const FormatException('duplicate deviceNumber in password state');
      }
      if (!ids.add(device.deviceId)) {
        throw const FormatException('duplicate deviceId in password state');
      }
    }

    return devices;
  }

  static Map<String, dynamic> _buildStateJson({
    required int generation,
    required String changeId,
    required String changedAt,
    required String changedByDeviceId,
    required List<PasswordStateDevice> devices,
  }) {
    return <String, dynamic>{
      'passwordGeneration': generation,
      'passwordChangeId': changeId,
      'passwordChangedAt': changedAt,
      'changedByDeviceId': changedByDeviceId,
      'devices': devices.map((d) => d.toJson()).toList(),
    };
  }

  static int _nextDeviceNumber(List<PasswordStateDevice> devices) {
    int maxNumber = 0;
    for (final PasswordStateDevice device in devices) {
      if (device.deviceNumber > maxNumber) {
        maxNumber = device.deviceNumber;
      }
    }
    return maxNumber + 1;
  }

  static Future<List<PasswordStateDevice>> _legacyAwareDevices({
    required Map<String, dynamic> state,
    required String currentDeviceId,
  }) async {
    final List<PasswordStateDevice> devices = _decodeDevices(state);
    if (devices.isNotEmpty) return devices;

    // Older Rocen versions did not store a device list. Preserve the old
    // changedByDeviceId as Device 1 when it exists, then register the current
    // device after it. This is a migration aid only; new states always carry a
    // proper devices array from the beginning.
    final int remoteGeneration = (state['passwordGeneration'] as int?) ?? 0;
    if (remoteGeneration < 1) {
      throw const FormatException('passwordGeneration is invalid');
    }

    final String legacyOwner =
        (state['changedByDeviceId'] ?? '').toString().trim();
    if (legacyOwner.isEmpty || legacyOwner == currentDeviceId) {
      return <PasswordStateDevice>[
        PasswordStateDevice(
          deviceNumber: 1,
          deviceId: currentDeviceId,
          passwordGeneration: remoteGeneration,
        ),
      ];
    }

    return <PasswordStateDevice>[
      PasswordStateDevice(
        deviceNumber: 1,
        deviceId: legacyOwner,
        passwordGeneration: remoteGeneration,
      ),
    ];
  }

  /// Establishes the initial shared password state on a brand-new backup or
  /// joins an existing backup as a newly registered device.
  ///
  /// A new repository receives generation 1 and Device 1. A second/following
  /// device adopts the existing global generation/change ID and is appended to
  /// the device registry without altering the password-state event itself.
  /// Device registration uses the same fast-forward parent-SHA protection as
  /// password-state changes, so simultaneous joins retry against the new state
  /// rather than allocating the same device number twice.
  static Future<void> initializeOrJoinState({
    required GithubBackupService service,
    required bool allowCreateInitialState,
    int maxAttempts = 4,
  }) async {
    final String currentDeviceId = getOrCreateDeviceId();

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final ({Map<String, dynamic>? content, String? refSha}) observed =
          await service.fetchNoteFileWithRefSha(fileName);

      if (observed.content == null) {
        if (!allowCreateInitialState) {
          throw GithubSyncException(
            'PASSWORD STATE IS MISSING FROM THIS EXISTING BACKUP. '
            'Rocen will not silently create a new shared password state because '
            'that could overwrite the meaning of an existing backup.',
          );
        }

        const int initialGeneration = 1;
        final String initialChangeId = generateChangeId();
        final String changedAt = DateTime.now().toUtc().toIso8601String();
        final List<PasswordStateDevice> initialDevices = <PasswordStateDevice>[
          PasswordStateDevice(
            deviceNumber: 1,
            deviceId: currentDeviceId,
            passwordGeneration: initialGeneration,
          ),
        ];

        if (observed.refSha == null) {
          throw GithubSyncException(
            'INITIAL PASSWORD STATE FAILED: repository branch is not initialized.',
          );
        }

        final String json = jsonEncode(_buildStateJson(
          generation: initialGeneration,
          changeId: initialChangeId,
          changedAt: changedAt,
          changedByDeviceId: currentDeviceId,
          devices: initialDevices,
        ));

        try {
          await service.updateFileWithFastForwardCheck(
            path: fileName,
            content: json,
            message: 'initial password state',
            expectedParentSha: observed.refSha,
          );
        } on GithubConditionalWriteConflict {
          if (attempt + 1 >= maxAttempts) rethrow;
          continue;
        }

        await _recordKnownStateAndDeviceNumber(
          generation: initialGeneration,
          changeId: initialChangeId,
          deviceNumber: 1,
        );

        debug_log.secureDebugLog(
          '[password_state] initial shared state published successfully '
          '(generation=$initialGeneration, device=1/$currentDeviceId)',
        );
        return;
      }

      final Map<String, dynamic> state = observed.content!;
      final int? remoteGeneration = state['passwordGeneration'] as int?;
      final String remoteChangeId =
          (state['passwordChangeId'] ?? '').toString().trim();
      final String remoteChangedAt =
          (state['passwordChangedAt'] ?? '').toString().trim();
      final String remoteChangedByDeviceId =
          (state['changedByDeviceId'] ?? '').toString().trim();

      if (remoteGeneration == null ||
          remoteGeneration < 1 ||
          remoteChangeId.isEmpty ||
          remoteChangedAt.isEmpty ||
          remoteChangedByDeviceId.isEmpty) {
        throw const FormatException(
          'existing password_state.json has incomplete shared-state fields',
        );
      }

      final bool hasExplicitDeviceRegistry =
          state['devices'] is List && (state['devices'] as List).isNotEmpty;
      List<PasswordStateDevice> devices = await _legacyAwareDevices(
        state: state,
        currentDeviceId: currentDeviceId,
      );

      PasswordStateDevice? existing;
      for (final PasswordStateDevice device in devices) {
        if (device.deviceId == currentDeviceId) {
          existing = device;
          break;
        }
      }

      if (existing != null) {
        final int localGeneration = getKnownGeneration();
        final String? localChangeId = getKnownChangeId();

        // A freshly installed/joining device has no local shared-state record.
        // Adopt the repository's canonical generation and change ID.
        final bool localStateMatches = localGeneration == remoteGeneration &&
            localChangeId == remoteChangeId;
        if (localGeneration == 0 || localStateMatches) {
          // If this is an older state file that predates the device registry,
          // migrate it now so the backup has an explicit Device 1 record.
          if (!hasExplicitDeviceRegistry) {
            final Map<String, dynamic> migratedState = _buildStateJson(
              generation: remoteGeneration,
              changeId: remoteChangeId,
              changedAt: remoteChangedAt,
              changedByDeviceId: remoteChangedByDeviceId,
              devices: devices,
            );
            try {
              await service.updateFileWithFastForwardCheck(
                path: fileName,
                content: jsonEncode(migratedState),
                message: 'migrate password state device registry',
                expectedParentSha: observed.refSha,
              );
            } on GithubConditionalWriteConflict {
              if (attempt + 1 >= maxAttempts) rethrow;
              continue;
            }
          }

          await _recordKnownStateAndDeviceNumber(
            generation: remoteGeneration,
            changeId: remoteChangeId,
            deviceNumber: existing.deviceNumber,
          );
          return;
        }

        if (localGeneration < remoteGeneration) {
          // This device has already changed password-state locally and is now
          // behind a newer shared generation. Do not silently acknowledge it
          // merely because the GitHub token was re-entered.
          throw GithubSyncException(
            'THIS DEVICE IS BEHIND THE SHARED PASSWORD STATE. '
            'UPDATE THIS DEVICE TO THE CURRENT PASSWORD BEFORE RE-REGISTERING IT.',
          );
        }

        throw GithubSyncException(
          'THIS DEVICE HAS A PASSWORD-STATE CONFLICT WITH THE SELECTED GITHUB BACKUP.',
        );
      }

      final int nextDeviceNumber = _nextDeviceNumber(devices);
      final PasswordStateDevice newDevice = PasswordStateDevice(
        deviceNumber: nextDeviceNumber,
        deviceId: currentDeviceId,
        passwordGeneration: remoteGeneration,
      );
      devices = <PasswordStateDevice>[...devices, newDevice];

      final Map<String, dynamic> nextState = _buildStateJson(
        generation: remoteGeneration,
        changeId: remoteChangeId,
        changedAt: remoteChangedAt,
        changedByDeviceId: remoteChangedByDeviceId,
        devices: devices,
      );

      try {
        await service.updateFileWithFastForwardCheck(
          path: fileName,
          content: jsonEncode(nextState),
          message: 'register device $nextDeviceNumber',
          expectedParentSha: observed.refSha,
        );
      } on GithubConditionalWriteConflict {
        if (attempt + 1 >= maxAttempts) rethrow;
        continue;
      }

      await _recordKnownStateAndDeviceNumber(
        generation: remoteGeneration,
        changeId: remoteChangeId,
        deviceNumber: nextDeviceNumber,
      );

      debug_log.secureDebugLog(
        '[password_state] device registered successfully '
        '(device=$nextDeviceNumber/$currentDeviceId generation=$remoteGeneration)',
      );
      return;
    }

    throw GithubConditionalWriteConflict(
      'DEVICE REGISTRATION FAILED after repeated concurrent-write retries.',
    );
  }

  /// Backwards-compatible name retained for callers from the earlier design.
  static Future<void> initializeInitialState({
    required GithubBackupService service,
  }) async {
    await initializeOrJoinState(
      service: service,
      allowCreateInitialState: true,
    );
  }

  static Future<void> publishNewState({
    required GithubBackupService service,
    required int newGeneration,
    required String newChangeId,
    required String deviceId,
    required String? expectedParentSha,
    Map<String, dynamic>? baseState,
  }) async {
    Map<String, dynamic>? remoteState = baseState;

    if (remoteState == null) {
      final ({Map<String, dynamic>? content, String? refSha}) fetched =
          await service.fetchNoteFileWithRefSha(fileName);
      if (fetched.content == null) {
        throw GithubSyncException(
          'PASSWORD STATE PUBLISH FAILED: shared password state does not exist.',
        );
      }
      if (expectedParentSha != fetched.refSha) {
        throw GithubConditionalWriteConflict(
          'password_state.json changed before the publish began',
        );
      }
      remoteState = fetched.content;
    }

    final Map<String, dynamic> state = remoteState!;
    final int? remoteGeneration = state['passwordGeneration'] as int?;
    final String remoteChangeId =
        (state['passwordChangeId'] ?? '').toString().trim();
    final String remoteChangedAt =
        (state['passwordChangedAt'] ?? '').toString().trim();
    final String remoteChangedByDeviceId =
        (state['changedByDeviceId'] ?? '').toString().trim();

    if (remoteGeneration == null ||
        remoteGeneration < 1 ||
        remoteChangeId.isEmpty ||
        remoteChangedAt.isEmpty ||
        remoteChangedByDeviceId.isEmpty) {
      throw const FormatException(
        'existing password_state.json has incomplete shared-state fields',
      );
    }

    final List<PasswordStateDevice> decodedDevices = await _legacyAwareDevices(
      state: remoteState,
      currentDeviceId: deviceId,
    );
    final List<PasswordStateDevice> devices = decodedDevices
        .map(
          (device) => device.deviceId == deviceId
              ? PasswordStateDevice(
                  deviceNumber: device.deviceNumber,
                  deviceId: device.deviceId,
                  passwordGeneration: newGeneration,
                )
              : device,
        )
        .toList();

    if (!devices.any((device) => device.deviceId == deviceId)) {
      devices.add(
        PasswordStateDevice(
          deviceNumber: _nextDeviceNumber(devices),
          deviceId: deviceId,
          passwordGeneration: newGeneration,
        ),
      );
    }

    final String nowIso = DateTime.now().toUtc().toIso8601String();
    final String json = jsonEncode(_buildStateJson(
      generation: newGeneration,
      changeId: newChangeId,
      changedAt: nowIso,
      changedByDeviceId: deviceId,
      devices: devices,
    ));

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

    try {
      final Map<String, dynamic> remote = fetched.content!;
      final int? remoteGeneration = remote['passwordGeneration'] as int?;
      final String remoteChangeId =
          (remote['passwordChangeId'] ?? '').toString().trim();
      final String remoteChangedAtRaw =
          (remote['passwordChangedAt'] ?? '').toString().trim();
      final String remoteChangedByDeviceId =
          (remote['changedByDeviceId'] ?? '').toString().trim();

      if (remoteGeneration == null ||
          remoteGeneration < 1 ||
          remoteChangeId.isEmpty ||
          remoteChangedAtRaw.isEmpty ||
          remoteChangedByDeviceId.isEmpty) {
        return const PasswordStateResult(
            comparison: PasswordStateComparison.checkFailed);
      }

      final List<PasswordStateDevice> devices = _decodeDevices(remote);
      final DateTime? remoteChangedAt = DateTime.tryParse(remoteChangedAtRaw);

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
        devices: devices,
      );
    } catch (_) {
      return const PasswordStateResult(
          comparison: PasswordStateComparison.checkFailed);
    }
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
    final String remoteChangeId =
        (remote?['passwordChangeId'] ?? '').toString().trim();

    if (remoteGeneration == null || remoteChangeId.isEmpty) {
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
          baseState: remote,
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
