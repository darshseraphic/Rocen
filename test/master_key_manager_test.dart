import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/master_key_manager.dart';

void main() {
  setUp(() {
    MasterKeyManager.instance.resetForTesting();
  });

  test('fresh generation produces a 32-byte PROVISIONAL key', () {
    MasterKeyManager.instance.generateProvisionalMasterKey();
    expect(MasterKeyManager.instance.state, MasterKeyState.provisional);
    final bytes = MasterKeyManager.instance.requireProvisionalMasterKeyBytes();
    try {
      expect(bytes.length, 32);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  });

  test('PROVISIONAL key cannot be accessed through authoritative gate', () {
    MasterKeyManager.instance.generateProvisionalMasterKey();
    expect(
      () => MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes(),
      throwsA(isA<DatasetNotInitializedException>()),
    );
  });

  test('promotion is the only generation-to-authority transition', () {
    MasterKeyManager.instance.generateProvisionalMasterKey();
    MasterKeyManager.instance.promoteProvisionalToAuthoritative();
    expect(MasterKeyManager.instance.state, MasterKeyState.authoritative);
    final bytes = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
    try {
      expect(bytes.length, 32);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  });

  test('authoritative accessor returns a defensive copy', () {
    MasterKeyManager.instance.generateProvisionalMasterKey();
    MasterKeyManager.instance.promoteProvisionalToAuthoritative();
    final first = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
    final expected = List<int>.from(first);
    first[0] ^= 0xFF;
    try {
      expect(
        MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes(),
        expected,
      );
    } finally {
      first.fillRange(0, first.length, 0);
    }
  });

  test('cannot generate a second key while authoritative', () {
    MasterKeyManager.instance.generateProvisionalMasterKey();
    MasterKeyManager.instance.promoteProvisionalToAuthoritative();
    expect(
      () => MasterKeyManager.instance.generateProvisionalMasterKey(),
      throwsStateError,
    );
  });

  test('cannot overwrite authoritative key through recovery setter', () {
    MasterKeyManager.instance.generateProvisionalMasterKey();
    MasterKeyManager.instance.promoteProvisionalToAuthoritative();
    final original = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
    final candidate = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
    expect(
      () => MasterKeyManager.instance.setAuthoritativeMasterKeyFromRecovery(candidate),
      throwsStateError,
    );
    expect(candidate, everyElement(0));
    try {
      expect(MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes(), original);
    } finally {
      original.fillRange(0, original.length, 0);
    }
  });

  test('initialization lease owner may install recovered key', () async {
    final candidate = Uint8List.fromList(List<int>.generate(32, (i) => i));
    await MasterKeyManager.instance.runExclusiveInitialization<void>(
      (lease) async {
        MasterKeyManager.instance.setAuthoritativeMasterKeyFromRecovery(
          candidate,
          lease: lease,
        );
      },
    );
    expect(candidate, everyElement(0));
    final live = MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes();
    try {
      expect(live, List<int>.generate(32, (i) => i));
    } finally {
      live.fillRange(0, live.length, 0);
    }
  });

  test('unrelated caller cannot install during another initialization', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final initialization =
        MasterKeyManager.instance.runExclusiveInitialization<void>(
      (lease) async {
        started.complete();
        await release.future;
      },
    );
    await started.future;

    final candidate = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
    expect(
      () => MasterKeyManager.instance.setAuthoritativeMasterKeyFromRecovery(
        candidate,
      ),
      throwsStateError,
    );
    expect(candidate, everyElement(0));

    release.complete();
    await initialization;
  });

  test('rejected invalid-length recovery candidate is zeroed under lease', () async {
    final candidate = Uint8List.fromList([1, 2, 3]);
    await expectLater(
      MasterKeyManager.instance.runExclusiveInitialization<void>(
        (lease) async {
          MasterKeyManager.instance.setAuthoritativeMasterKeyFromRecovery(
            candidate,
            lease: lease,
          );
        },
      ),
      throwsArgumentError,
    );
    expect(candidate, everyElement(0));
  });

  test('recovery installation without a lease is rejected and zeroes candidate', () {
    final candidate = Uint8List.fromList(List<int>.generate(32, (i) => i));
    expect(
      () => MasterKeyManager.instance.setAuthoritativeMasterKeyFromRecovery(candidate),
      throwsStateError,
    );
    expect(candidate, everyElement(0));
  });

  test('provisional discard returns manager to NONE', () {
    MasterKeyManager.instance.generateProvisionalMasterKey();
    MasterKeyManager.instance.discardProvisionalMasterKey();
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(
      () => MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes(),
      throwsA(isA<DatasetNotInitializedException>()),
    );
  });

  test('cannot discard an authoritative key', () {
    MasterKeyManager.instance.generateProvisionalMasterKey();
    MasterKeyManager.instance.promoteProvisionalToAuthoritative();
    expect(
      () => MasterKeyManager.instance.discardProvisionalMasterKey(),
      throwsStateError,
    );
  });

  test('exclusive initialization shares one in-flight operation', () async {
    final firstStarted = Future<void>.delayed(
      const Duration(milliseconds: 1),
      () {},
    );
    var calls = 0;
    final first = MasterKeyManager.instance.runExclusiveInitialization<void>(
      (lease) async {
        calls++;
        await firstStarted;
      },
    );
    final second = MasterKeyManager.instance.runExclusiveInitialization<void>(
      (lease) async {
        calls++;
      },
    );
    await Future.wait([first, second]);
    expect(calls, 1);
    expect(MasterKeyManager.instance.isInitializationInFlight, isFalse);
  });

  test('exclusive initialization guard clears after failure', () async {
    await expectLater(
      MasterKeyManager.instance.runExclusiveInitialization<void>(
        (lease) async => throw StateError('expected failure'),
      ),
      throwsStateError,
    );
    expect(MasterKeyManager.instance.isInitializationInFlight, isFalse);
  });

  test('resetForTesting clears live key material and state', () {
    MasterKeyManager.instance.generateProvisionalMasterKey();
    MasterKeyManager.instance.promoteProvisionalToAuthoritative();
    MasterKeyManager.instance.resetForTesting();
    expect(MasterKeyManager.instance.state, MasterKeyState.none);
    expect(
      () => MasterKeyManager.instance.requireAuthoritativeMasterKeyBytes(),
      throwsA(isA<DatasetNotInitializedException>()),
    );
  });
}
