import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/screen_security.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/activation_contract.dart';

/// NORMAL-BUILD isolation test.
///
/// Verifies the behaviour of a build compiled WITHOUT
/// `--dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true`. It deliberately has
/// NO shared setUp/tearDown that calls `resetForTesting()` (those methods
/// throw in a normal build - that protection is kept), and it never calls
/// the destructive resets except to prove they refuse.
///
/// Run it WITHOUT the define:
///
///     flutter test test/normal_build_checkpoint_isolation_test.dart
///
/// With the define it is reported as SKIPPED (the test-control build is
/// covered by the other suites). A skipped test is not a pass.
///
/// Evidence: written against the real production path; see the report for
/// whether it was executed.
const List<String> _mnemonic = [
  'abandon',
  'ability',
  'able',
  'about',
  'above',
  'absent',
  'absorb',
  'abstract',
  'absurd',
  'abuse',
  'access',
  'accident',
];
const String _password = 'P4ssword-Normal!';

Future<void> main() async {
  final bool normalBuild = !SecurityCheckpoints.isTestControlEnabled;
  final Object skipReason = normalBuild
      ? false
      : 'verifies the NORMAL build: run without '
          '--dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true';

  group(
      'normal build: checkpoint controls are inert and destructive resets '
      'refuse', () {
    test('reach never returns a Future, so production code never suspends', () {
      for (final SecurityCheckpoint cp in SecurityCheckpoint.values) {
        expect(SecurityCheckpoints.reach(cp), isNull, reason: '$cp');
      }
    });

    test(
        'arm and waitUntilPaused throw; release and reset are no-ops, for '
        'every checkpoint', () async {
      for (final SecurityCheckpoint cp in SecurityCheckpoint.values) {
        expect(() => SecurityCheckpoints.arm(cp), throwsStateError,
            reason: '$cp');
        await expectLater(
            SecurityCheckpoints.waitUntilPaused(cp), throwsStateError,
            reason: '$cp');
        expect(() => SecurityCheckpoints.release(cp), returnsNormally);
        // Still not armed after the refused arm():
        expect(SecurityCheckpoints.reach(cp), isNull, reason: '$cp');
      }
      expect(() => SecurityCheckpoints.reset(), returnsNormally);
    });

    test('destructive resets THROW and change nothing', () {
      final ssm = SessionSecurityManager.instance;
      final SessionState stateBefore = ssm.state;
      final int epochBefore = ssm.epoch;
      expect(() => ssm.resetForTesting(), throwsStateError);
      expect(
          () => MasterKeyManager.instance.resetForTesting(), throwsStateError);
      expect(ssm.state, stateBefore);
      expect(ssm.epoch, epochBefore);
    });

    test('screen acknowledgement test control is inert without its define',
        () {
      expect(() => ScreenSecurity.useTestAcknowledgement(), throwsStateError);
      expect(
        ScreenSecurity.satisfiesPolicy(
            ScreenSecurityStatus.unsupportedPlatform),
        isFalse,
      );
      expect(
        ScreenSecurity.satisfiesPolicy(ScreenSecurityStatus.unavailable),
        isFalse,
      );
    });

    test(
        'the real establish path completes and unsupported capture policy '
        'keeps the normal build locked', () async {
      final Directory tempDir =
          await Directory.systemTemp.createTemp('rocen_normal_build_');
      Hive.init(tempDir.path);
      await Hive.openBox(MasterKeyLocalStore.boxName);
      final ssm = SessionSecurityManager.instance;
      try {
        // A fresh test isolate starts in BOOTSTRAP with no authority.
        expect(ssm.state, SessionState.bootstrap);
        await MasterKeyProductionService.instance.establishFirstDevice(
          password: _password,
          mnemonicWords: _mnemonic,
        );
        ssm.finishBootstrap();
        await expectLater(
          ssm.unlock(
            password: _password,
            activateRoot: satisfyActivationContract,
            teardownRoot: () {},
          ),
          throwsA(isA<ScreenCaptureProtectionException>()),
        );
        expect(ssm.state, SessionState.locked);
        expect(() => ssm.captureAuthorization(),
            throwsA(isA<SessionAuthorizationException>()));
        expect(ssm.activationDiagnostics.sessionKeysInstalled, isFalse);
      } finally {
        ssm.lockSync();
        await Hive.close();
        await tempDir.delete(recursive: true);
      }
    });
  }, skip: skipReason);
}
