import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'secure_bytes.dart';

enum MasterKeyState { none, provisional, authoritative }

class DatasetNotInitializedException implements Exception {
  final String message;
  const DatasetNotInitializedException(this.message);

  @override
  String toString() => 'DatasetNotInitializedException: $message';
}

/// Opaque capability issued only to the callback that owns the current
/// exclusive initialization operation. Callers cannot construct a valid
/// instance themselves, so recovery installation remains serialized and
/// authority replacement stays prohibited for unrelated code.
class MasterKeyInitializationLease {
  final MasterKeyManager _owner;
  bool _released = false;

  MasterKeyInitializationLease._(this._owner);
}

/// Sole authoritative in-memory owner for the dataset Master Key before
/// Stage 5 introduces the session-level owner.
class MasterKeyManager {
  MasterKeyManager._();

  static const int masterKeyLengthBytes = 32;
  static final MasterKeyManager instance = MasterKeyManager._();

  MasterKeyState _state = MasterKeyState.none;
  SecureBytes? _masterKeyBytes;
  Future<dynamic>? _inFlightInitialization;
  MasterKeyInitializationLease? _activeInitializationLease;

  MasterKeyState get state => _state;
  bool get isInitializationInFlight => _inFlightInitialization != null;

  Uint8List requireAuthoritativeMasterKeyBytes() {
    if (_state != MasterKeyState.authoritative || _masterKeyBytes == null) {
      throw DatasetNotInitializedException(
        'Master Key is not authoritative (state=$_state).',
      );
    }
    return Uint8List.fromList(_masterKeyBytes!.bytes);
  }

  /// Narrow initialization-only access. This buffer may be used only to build
  /// the Password/Recovery wrappers and must be zeroed immediately afterward.
  /// It must never be passed to a data encryption/persistence path.
  Uint8List requireProvisionalMasterKeyBytes() {
    if (_state != MasterKeyState.provisional || _masterKeyBytes == null) {
      throw DatasetNotInitializedException(
        'Master Key is not provisional (state=$_state).',
      );
    }
    return Uint8List.fromList(_masterKeyBytes!.bytes);
  }

  void generateProvisionalMasterKey() {
    if (_state == MasterKeyState.authoritative) {
      throw StateError('an authoritative Master Key already exists');
    }
    if (_state == MasterKeyState.provisional) {
      throw StateError('a provisional Master Key already exists');
    }

    final Random random = Random.secure();
    final Uint8List generated = Uint8List.fromList(
      List<int>.generate(masterKeyLengthBytes, (_) => random.nextInt(256)),
    );
    try {
      final SecureBytes secure = SecureBytes(generated);
      _masterKeyBytes?.zero();
      _masterKeyBytes = secure;
      _state = MasterKeyState.provisional;
    } finally {
      zeroBytes(generated);
    }
  }

  void discardProvisionalMasterKey() {
    if (_state == MasterKeyState.authoritative) {
      throw StateError('refusing to discard authoritative Master Key');
    }
    _masterKeyBytes?.zero();
    _masterKeyBytes = null;
    _state = MasterKeyState.none;
  }

  void promoteProvisionalToAuthoritative() {
    if (_state != MasterKeyState.provisional || _masterKeyBytes == null) {
      throw StateError('no provisional Master Key is available');
    }
    _state = MasterKeyState.authoritative;
  }

  /// Installs a recovered MK only when the caller owns the active
  /// initialization lease. An unrelated caller cannot use this path while
  /// initialization is in flight, and an already-authoritative MK can never
  /// be replaced.
  void setAuthoritativeMasterKeyFromRecovery(
    Uint8List recoveredKeyBytes, {
    MasterKeyInitializationLease? lease,
  }) {
    try {
      _validateInitializationLease(lease);
      if (recoveredKeyBytes.length != masterKeyLengthBytes) {
        throw ArgumentError(
          'recovered Master Key must be exactly $masterKeyLengthBytes bytes',
        );
      }
      if (_state == MasterKeyState.authoritative) {
        throw StateError('refusing to replace an authoritative Master Key');
      }

      final SecureBytes replacement = SecureBytes(recoveredKeyBytes);
      try {
        _masterKeyBytes?.zero();
        _masterKeyBytes = replacement;
        _state = MasterKeyState.authoritative;
      } catch (_) {
        replacement.zero();
        rethrow;
      }
    } finally {
      zeroBytes(recoveredKeyBytes);
    }
  }

  Future<T> runExclusiveInitialization<T>(
    Future<T> Function(MasterKeyInitializationLease lease) operation,
  ) {
    final Future<dynamic>? existing = _inFlightInitialization;
    if (existing != null) {
      return existing.then((value) => value as T);
    }

    final MasterKeyInitializationLease lease =
        MasterKeyInitializationLease._(this);
    final Completer<T> completer = Completer<T>();
    _activeInitializationLease = lease;
    _inFlightInitialization = completer.future;

    Future<void>(() async {
      try {
        completer.complete(await operation(lease));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        lease._released = true;
        if (identical(_activeInitializationLease, lease)) {
          _activeInitializationLease = null;
        }
        if (identical(_inFlightInitialization, completer.future)) {
          _inFlightInitialization = null;
        }
      }
    });

    return completer.future;
  }

  void _validateInitializationLease(MasterKeyInitializationLease? lease) {
    if (lease == null || !identical(lease._owner, this) ||
        !identical(_activeInitializationLease, lease) ||
        lease._released ||
        _inFlightInitialization == null) {
      throw StateError('Master Key recovery installation requires the active initialization lease');
    }
  }

  void resetForTesting() {
    if (_inFlightInitialization != null) {
      throw StateError('cannot reset while initialization is in flight');
    }
    _activeInitializationLease = null;
    _masterKeyBytes?.zero();
    _masterKeyBytes = null;
    _state = MasterKeyState.none;
  }
}
