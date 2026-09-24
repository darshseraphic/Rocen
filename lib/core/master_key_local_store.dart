import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class MasterKeyLocalRevisionConflict implements Exception {
  final String message;
  const MasterKeyLocalRevisionConflict(this.message);

  @override
  String toString() => 'MasterKeyLocalRevisionConflict: $message';
}

/// Durable local authority record for the Block B master-key architecture.
///
/// `authority == authoritative` means that this device has durably established
/// the local dataset MK. It does NOT imply that Recovery wrapper publication to
/// GitHub has completed; that state is represented independently by
/// [remoteRecoveryStatus].
///
/// The plaintext Master Key, mnemonic, derived keys, password and tokens are
/// never stored here.
class MasterKeyLocalStore {
  MasterKeyLocalStore._();

  static const String boxName = 'rocen_settings_box';
  static const String recordKey = 'master_key_record_v1';

  static Future<MasterKeyLocalRecord?> read() async {
    final dynamic raw = Hive.box(boxName).get(recordKey);
    if (raw == null) return null;
    if (raw is! String) {
      throw const FormatException('master key security record is not a string');
    }
    return MasterKeyLocalRecord.fromJsonString(raw);
  }

  /// Writes a new authority record using a durable revision check.
  ///
  /// Initial creation must use revision 1. Subsequent writes must be exactly
  /// one revision newer than the currently persisted record. This prevents a
  /// stale caller from overwriting newer local authority state.
  static Future<void> write(MasterKeyLocalRecord record) async {
    record.validate();
    final Box box = Hive.box(boxName);
    final dynamic rawCurrent = box.get(recordKey);
    final MasterKeyLocalRecord? current;
    if (rawCurrent == null) {
      current = null;
    } else if (rawCurrent is String) {
      current = MasterKeyLocalRecord.fromJsonString(rawCurrent);
    } else {
      throw const FormatException(
        'master key security record has an invalid persisted type',
      );
    }

    if (current == null) {
      if (record.revision != 1) {
        throw const MasterKeyLocalRevisionConflict(
          'initial authority record must use revision 1',
        );
      }
    } else if (record.revision != current.revision + 1) {
      throw MasterKeyLocalRevisionConflict(
        'stale authority write: expected revision ${current.revision + 1}, '
        'received ${record.revision}',
      );
    }

    await box.put(recordKey, record.toJsonString());
  }

  static Future<void> clear() async {
    await Hive.box(boxName).delete(recordKey);
  }
}

enum RemoteRecoveryStatus { unpublished, published, conflict }

class MasterKeyLocalRecord {
  static const int schema = 1;
  static const String authoritativeValue = 'authoritative';

  final int schemaVersion;
  final int revision;
  final String authority;
  final String passwordVerifier;
  final String passwordWrap;
  final String recoveryWrap;
  final RemoteRecoveryStatus remoteRecoveryStatus;
  final String? repository;
  final String? previousPublishedRecoveryWrap;

  const MasterKeyLocalRecord({
    required this.schemaVersion,
    required this.revision,
    required this.authority,
    required this.passwordVerifier,
    required this.passwordWrap,
    required this.recoveryWrap,
    required this.remoteRecoveryStatus,
    required this.repository,
    required this.previousPublishedRecoveryWrap,
  });

  factory MasterKeyLocalRecord.authoritative({
    required String passwordVerifier,
    required String passwordWrap,
    required String recoveryWrap,
    required RemoteRecoveryStatus remoteRecoveryStatus,
    String? repository,
    String? previousPublishedRecoveryWrap,
  }) {
    final MasterKeyLocalRecord record = MasterKeyLocalRecord(
      schemaVersion: schema,
      revision: 1,
      authority: authoritativeValue,
      passwordVerifier: passwordVerifier,
      passwordWrap: passwordWrap,
      recoveryWrap: recoveryWrap,
      remoteRecoveryStatus: remoteRecoveryStatus,
      repository: repository,
      previousPublishedRecoveryWrap: previousPublishedRecoveryWrap,
    );
    record.validate();
    return record;
  }

  factory MasterKeyLocalRecord.fromJsonString(String json) {
    final dynamic decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('master key security record is not an object');
    }
    final int? version = decoded['schema'] is int
        ? decoded['schema'] as int
        : int.tryParse('${decoded['schema'] ?? ''}');
    if (version != schema) {
      throw FormatException(
        'unsupported master key record schema: ${decoded['schema']}',
      );
    }
    final int? revision = decoded['revision'] is int
        ? decoded['revision'] as int
        : int.tryParse('${decoded['revision'] ?? ''}');
    if (revision == null || revision < 1) {
      throw const FormatException('master key record revision is invalid');
    }

    final String authority = (decoded['authority'] ?? '').toString();
    if (authority != authoritativeValue) {
      throw const FormatException('master key record is not authoritative');
    }
    final String verifier = (decoded['passwordVerifier'] ?? '').toString();
    final String passwordWrap = (decoded['passwordWrap'] ?? '').toString();
    final String recoveryWrap = (decoded['recoveryWrap'] ?? '').toString();
    if (verifier.isEmpty || passwordWrap.isEmpty || recoveryWrap.isEmpty) {
      throw const FormatException('master key record is incomplete');
    }

    final dynamic remoteRaw = decoded['remoteRecovery'];
    if (remoteRaw is! Map) {
      throw const FormatException('master key record remoteRecovery is missing');
    }
    final String statusRaw = (remoteRaw['status'] ?? '').toString();
    RemoteRecoveryStatus? status;
    for (final candidate in RemoteRecoveryStatus.values) {
      if (candidate.name == statusRaw) {
        status = candidate;
        break;
      }
    }
    if (status == null) {
      throw FormatException('unsupported remote recovery status: $statusRaw');
    }
    final String repositoryValue =
        (remoteRaw['repository'] ?? '').toString().trim();
    final String? repository = repositoryValue.isEmpty ? null : repositoryValue;
    final String previousValue =
        (remoteRaw['previousPublishedRecoveryWrap'] ?? '').toString().trim();
    final String? previousPublishedRecoveryWrap =
        previousValue.isEmpty ? null : previousValue;

    final record = MasterKeyLocalRecord(
      schemaVersion: version!,
      revision: revision,
      authority: authority,
      passwordVerifier: verifier,
      passwordWrap: passwordWrap,
      recoveryWrap: recoveryWrap,
      remoteRecoveryStatus: status,
      repository: repository,
      previousPublishedRecoveryWrap: previousPublishedRecoveryWrap,
    );
    record.validate();
    return record;
  }

  void validate() {
    if (schemaVersion != schema) {
      throw const FormatException('unsupported master key record schema');
    }
    if (revision < 1) {
      throw const FormatException('master key record revision is invalid');
    }
    if (authority != authoritativeValue) {
      throw const FormatException('master key record is not authoritative');
    }
    if (passwordVerifier.isEmpty || passwordWrap.isEmpty || recoveryWrap.isEmpty) {
      throw const FormatException('master key record is incomplete');
    }
    if (remoteRecoveryStatus == RemoteRecoveryStatus.published &&
        (repository == null || repository!.trim().isEmpty)) {
      throw const FormatException('published remote recovery requires repository');
    }
  }

  String toJsonString() {
    validate();
    return jsonEncode({
      'schema': schemaVersion,
      'revision': revision,
      'authority': authority,
      'passwordVerifier': passwordVerifier,
      'passwordWrap': passwordWrap,
      'recoveryWrap': recoveryWrap,
      'remoteRecovery': {
        'status': remoteRecoveryStatus.name,
        if (repository != null && repository!.trim().isNotEmpty)
          'repository': repository,
        if (previousPublishedRecoveryWrap != null &&
            previousPublishedRecoveryWrap!.trim().isNotEmpty)
          'previousPublishedRecoveryWrap': previousPublishedRecoveryWrap,
      },
    });
  }

  MasterKeyLocalRecord copyWith({
    String? passwordVerifier,
    String? passwordWrap,
    String? recoveryWrap,
    RemoteRecoveryStatus? remoteRecoveryStatus,
    String? repository,
    String? previousPublishedRecoveryWrap,
    bool clearPreviousPublishedRecoveryWrap = false,
  }) {
    return MasterKeyLocalRecord(
      schemaVersion: schemaVersion,
      revision: revision + 1,
      authority: authority,
      passwordVerifier: passwordVerifier ?? this.passwordVerifier,
      passwordWrap: passwordWrap ?? this.passwordWrap,
      recoveryWrap: recoveryWrap ?? this.recoveryWrap,
      remoteRecoveryStatus: remoteRecoveryStatus ?? this.remoteRecoveryStatus,
      repository: repository ?? this.repository,
      previousPublishedRecoveryWrap: clearPreviousPublishedRecoveryWrap
          ? null
          : (previousPublishedRecoveryWrap ?? this.previousPublishedRecoveryWrap),
    );
  }
}
