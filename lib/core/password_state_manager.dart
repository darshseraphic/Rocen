import 'dart:convert';
import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';

import 'debug_log.dart' as debug_log;
import 'github_backup_service.dart';

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
    final int? generation = raw['passwordGeneration'] is int
        ? raw['passwordGeneration'] as int
        : int.tryParse('${raw['passwordGeneration'] ?? ''}');
    final String deviceId = (raw['deviceId'] ?? '').toString().trim();
    if (deviceNumber == null || deviceNumber < 1) {
      throw const FormatException('deviceNumber is invalid');
    }
    if (generation == null || generation < 1) {
      throw const FormatException('passwordGeneration is invalid');
    }
    if (deviceId.isEmpty) {
      throw const FormatException('deviceId is empty');
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

class PasswordStateManager {
  static const String fileName = 'password_state.json';
  static const String _boxName = 'rocen_settings_box';
  static const String _keyDeviceId = 'device_id';
  static const String _keyDeviceNumber = 'device_number';
  static const String _keyKnownGeneration = 'known_password_generation';
  static const String _keyRegisteredAt = 'device_registered_at';

  static String getOrCreateDeviceId() {
    final box = Hive.box(_boxName);
    final String? existing = box.get(_keyDeviceId)?.toString();
    if (existing != null && existing.isNotEmpty) return existing;

    final Random random = Random.secure();
    final String suffix = List<int>.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final String deviceId = 'device-$suffix';
    box.put(_keyDeviceId, deviceId);
    box.put(_keyRegisteredAt, DateTime.now().toUtc().toIso8601String());
    return deviceId;
  }

  static int? getDeviceNumber() {
    final dynamic value = Hive.box(_boxName).get(_keyDeviceNumber);
    if (value is int && value > 0) return value;
    return int.tryParse('${value ?? ''}');
  }

  static int getKnownGeneration() {
    final dynamic value = Hive.box(_boxName).get(_keyKnownGeneration);
    return value is int ? value : int.tryParse('${value ?? ''}') ?? 0;
  }

  static String generateChangeId() {
    final Random random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<void> _recordKnownStateAndDeviceNumber({
    required int generation,
    required int deviceNumber,
  }) async {
    final box = Hive.box(_boxName);
    await box.put(_keyKnownGeneration, generation);
    await box.put(_keyDeviceNumber, deviceNumber);
  }

  static List<PasswordStateDevice> _decodeDevices(Map<String, dynamic> state) {
    final dynamic raw = state['devices'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException(
        'password_state.json requires a non-empty devices array',
      );
    }

    final List<PasswordStateDevice> devices = raw
        .map(PasswordStateDevice.fromJson)
        .toList(growable: false);
    final Set<int> numbers = <int>{};
    final Set<String> ids = <String>{};
    for (final device in devices) {
      if (!numbers.add(device.deviceNumber)) {
        throw const FormatException('duplicate deviceNumber in password state');
      }
      if (!ids.add(device.deviceId)) {
        throw const FormatException('duplicate deviceId in password state');
      }
    }
    return devices;
  }

  static int _nextDeviceNumber(List<PasswordStateDevice> devices) {
    int max = 0;
    for (final device in devices) {
      if (device.deviceNumber > max) max = device.deviceNumber;
    }
    return max + 1;
  }

  static Map<String, dynamic> _buildStateJson({
    required int generation,
    required String changeId,
    required String changedAt,
    required String changedByDeviceId,
    required List<PasswordStateDevice> devices,
  }) {
    return {
      'passwordGeneration': generation,
      'passwordChangeId': changeId,
      'passwordChangedAt': changedAt,
      'changedByDeviceId': changedByDeviceId,
      'devices': devices.map((d) => d.toJson()).toList(),
    };
  }

  /// Creates the shared state on a clean repository or registers this device
  /// against an already-established Block B authority state.
  static Future<void> initializeOrJoinState({
    required GithubBackupService service,
    required bool allowCreateInitialState,
    int maxAttempts = 4,
  }) async {
    final String currentDeviceId = getOrCreateDeviceId();
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final observed = await service.fetchNoteFileWithRefSha(fileName);
      if (observed.content == null) {
        if (!allowCreateInitialState) {
          throw GithubSyncException(
            'password_state.json is missing from the selected existing repository',
          );
        }
        if (observed.refSha == null) {
          throw GithubSyncException(
            'cannot create password state without an initialized branch',
          );
        }
        final String changeId = generateChangeId();
        final Map<String, dynamic> state = _buildStateJson(
          generation: 1,
          changeId: changeId,
          changedAt: DateTime.now().toUtc().toIso8601String(),
          changedByDeviceId: currentDeviceId,
          devices: [
            PasswordStateDevice(
              deviceNumber: 1,
              deviceId: currentDeviceId,
              passwordGeneration: 1,
            ),
          ],
        );
        try {
          await service.updateFileWithFastForwardCheck(
            path: fileName,
            content: jsonEncode(state),
            message: 'initial password state',
            expectedParentSha: observed.refSha,
          );
        } on GithubConditionalWriteConflict {
          if (attempt + 1 >= maxAttempts) rethrow;
          continue;
        }
        await _recordKnownStateAndDeviceNumber(
          generation: 1,
          deviceNumber: 1,
        );
        debug_log.secureDebugLog('[password_state] initialized shared state');
        return;
      }

      final Map<String, dynamic> state = observed.content!;
      final int? remoteGeneration = state['passwordGeneration'] is int
          ? state['passwordGeneration'] as int
          : int.tryParse('${state['passwordGeneration'] ?? ''}');
      final String changeId =
          (state['passwordChangeId'] ?? '').toString().trim();
      final String changedAt =
          (state['passwordChangedAt'] ?? '').toString().trim();
      final String changedBy =
          (state['changedByDeviceId'] ?? '').toString().trim();
      if (remoteGeneration == null ||
          remoteGeneration < 1 ||
          changeId.isEmpty ||
          changedAt.isEmpty ||
          changedBy.isEmpty) {
        throw const FormatException('password_state.json is structurally invalid');
      }

      final List<PasswordStateDevice> devices = _decodeDevices(state);
      final List<PasswordStateDevice> existing = devices
          .where((device) => device.deviceId == currentDeviceId)
          .toList(growable: false);
      if (existing.isNotEmpty) {
        await _recordKnownStateAndDeviceNumber(
          generation: remoteGeneration,
          deviceNumber: existing.first.deviceNumber,
        );
        return;
      }

      final int nextNumber = _nextDeviceNumber(devices);
      final List<PasswordStateDevice> nextDevices = [
        ...devices,
        PasswordStateDevice(
          deviceNumber: nextNumber,
          deviceId: currentDeviceId,
          passwordGeneration: remoteGeneration,
        ),
      ];
      final Map<String, dynamic> nextState = _buildStateJson(
        generation: remoteGeneration,
        changeId: changeId,
        changedAt: changedAt,
        changedByDeviceId: changedBy,
        devices: nextDevices,
      );
      try {
        await service.updateFileWithFastForwardCheck(
          path: fileName,
          content: jsonEncode(nextState),
          message: 'register device $nextNumber',
          expectedParentSha: observed.refSha,
        );
      } on GithubConditionalWriteConflict {
        if (attempt + 1 >= maxAttempts) rethrow;
        continue;
      }
      await _recordKnownStateAndDeviceNumber(
        generation: remoteGeneration,
        deviceNumber: nextNumber,
      );
      return;
    }
    throw GithubConditionalWriteConflict(
      'password-state device registration retries exhausted',
    );
  }

  /// Publishes the new recovery wrapper and the corresponding password-state
  /// generation in one non-force CAS commit. A stale branch is a hard conflict.
  static Future<void> publishRotationAtomically({
    required GithubBackupService service,
    required String recoveryWrap,
    int? expectedGeneration,
  }) async {
    final String deviceId = getOrCreateDeviceId();
    final observed = await service.fetchNoteFileWithRefSha(fileName);
    if (observed.content == null || observed.refSha == null) {
      throw GithubSyncException(
        'password_state.json is missing for password rotation',
      );
    }

    final dynamic rawGeneration = observed.content!['passwordGeneration'];
    final int? remoteGeneration = rawGeneration is int
        ? rawGeneration
        : int.tryParse('${rawGeneration ?? ''}');
    if (remoteGeneration == null || remoteGeneration < 1) {
      throw const FormatException('password_state.json generation is invalid');
    }
    if (expectedGeneration != null && remoteGeneration != expectedGeneration) {
      throw GithubConditionalWriteConflict(
        'remote password generation changed: expected $expectedGeneration, actual $remoteGeneration',
      );
    }

    final String changeId = generateChangeId();
    final List<PasswordStateDevice> devices = _decodeDevices(observed.content!);
    final List<PasswordStateDevice> nextDevices = devices
        .map(
          (device) => device.deviceId == deviceId
              ? PasswordStateDevice(
                  deviceNumber: device.deviceNumber,
                  deviceId: device.deviceId,
                  passwordGeneration: remoteGeneration + 1,
                )
              : device,
        )
        .toList();
    if (!nextDevices.any((device) => device.deviceId == deviceId)) {
      nextDevices.add(
        PasswordStateDevice(
          deviceNumber: _nextDeviceNumber(nextDevices),
          deviceId: deviceId,
          passwordGeneration: remoteGeneration + 1,
        ),
      );
    }

    final String nextState = jsonEncode(
      _buildStateJson(
        generation: remoteGeneration + 1,
        changeId: changeId,
        changedAt: DateTime.now().toUtc().toIso8601String(),
        changedByDeviceId: deviceId,
        devices: nextDevices,
      ),
    );

    await service.updateFilesWithFastForwardCheck(
      updates: {
        'device_key.json': recoveryWrap,
        fileName: nextState,
      },
      message: 'rocen: password rotation',
      expectedParentSha: observed.refSha,
    );

    final PasswordStateDevice thisDevice = nextDevices.firstWhere(
      (device) => device.deviceId == deviceId,
    );
    await _recordKnownStateAndDeviceNumber(
      generation: remoteGeneration + 1,
      deviceNumber: thisDevice.deviceNumber,
    );
  }
}
