import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_manager.dart';
import 'package:rocen/core/master_key_production_service.dart';
import 'package:rocen/core/session_security_manager.dart';
import 'support/activation_contract.dart';

/// Race tests pause REAL production code and therefore need the test-control
/// build flag: `flutter test --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true`.
/// Without it they are reported as SKIPPED, never as passed.
final Object _skipUnlessControl = SecurityCheckpoints.isTestControlEnabled
    ? false
    : 'run with --dart-define=ROCEN_SECURITY_TEST_CHECKPOINTS=true';

/// The activation transaction is INTERNAL: `_ActivationTransaction` is a
/// library-private class with a library-private constructor, so these tests
/// cannot (and must not) construct it. They verify its lifecycle only through
/// the real SessionSecurityManager boundary (runtime) and through the source
/// (static). Statuses are annotated per test.
///
/// Evidence: NOT executed in the authoring environment (no Dart/Flutter
/// runtime). Runtime tests are written against the real production path.
const List<String> _mnemonic = [
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];
const String _password = 'P4ssword-Zulu!';

String _src(String name) =>
    File('${Directory.current.path}/lib/core/$name').readAsStringSync();

Future<void> main() async {
  late Directory tempDir;
  final ssm = SessionSecurityManager.instance;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_atx_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    MasterKeyManager.instance.resetForTesting();
    ssm.resetForTesting();
    SecurityCheckpoints.reset();
    await Hive.box(MasterKeyLocalStore.boxName).clear();
    enableSimulatedScreenAcknowledgementForTest();
  });

  tearDown(() {
    SecurityCheckpoints.reset();
    ssm.lockSync();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('visibility (SOURCE-REVIEWED ONLY - static)', () {
    test('ActivationTransaction is library-private, with a private '
        'constructor, and not named anywhere outside the session library',
        () {
      final String tx = _src('activation_transaction.dart');
      expect(tx, contains('class _ActivationTransaction {'));
      expect(tx, contains('_ActivationTransaction(this._epoch);'));
      expect(tx, isNot(contains('class ActivationTransaction')));

      final Directory lib = Directory('${Directory.current.path}/lib');
      for (final FileSystemEntity f in lib.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String name = f.uri.pathSegments.last;
        if (<String>{
          'session_security_manager.dart',
          'activation_transaction.dart',
          'session_key_material.dart',
          'session_unlock_service.dart',
          'security_checkpoints.dart',
        }.contains(name)) {
          continue;
        }
        expect(f.readAsStringSync(), isNot(contains('ActivationTransaction')),
            reason: '${f.path} must not reference the internal transaction');
      }
    });

    test('only SessionSecurityManager.unlock constructs it', () {
      final String mgr = _src('session_security_manager.dart');
      expect('_ActivationTransaction('.allMatches(mgr).length, 1);
    });
  });

  group('stale adoption (SOURCE-REVIEWED ONLY for buffer clearing)', () {
    test('adoptCandidateMk rejects a stale transaction and zeroes the '
        'incoming buffer on every exit path', () {
      final String tx = _src('activation_transaction.dart');
      final int i = tx.indexOf('void adoptCandidateMk(Uint8List incoming)');
      expect(i, greaterThan(0));
      final String body = tx.substring(i, i + 900);
      expect(body, contains('if (_stale)'));
      expect(body, contains("StaleActivationTransactionException('ADOPT_CANDIDATE_MK')"));
      expect(body, contains('finally {\n      zeroBytes(incoming);'));
    });

    test('derived NEK/TEK are zeroed on arrival at a stale transaction', () {
      final String tx = _src('activation_transaction.dart');
      for (final String fn in <String>['_adoptNek', '_adoptTek']) {
        final int i = tx.indexOf('void $fn(SecureBytes derived)');
        expect(i, greaterThan(0));
        final String body = tx.substring(i, i + 260);
        expect(body, contains('derived.zero();'));
      }
    });

    test('transferTo is synchronous, one-way and refuses a stale '
        'transaction', () {
      final String tx = _src('activation_transaction.dart');
      final int i = tx.indexOf('void transferTo(SessionKeyMaterial target)');
      final int end = tx.indexOf('void invalidate()');
      final String body = tx.substring(i, end);
      expect(body, isNot(contains('await')));
      expect(body, contains("StaleActivationTransactionException('TRANSFER_TO_SESSION')"));
      expect(body, contains('_mk = null;'));
      expect(body, contains('_nek = null;'));
      expect(body, contains('_tek = null;'));
    });
  });

  group('lifecycle through the real boundary (runtime)', () {
    setUp(() async {
      await MasterKeyProductionService.instance.establishFirstDevice(
        password: _password,
        mnemonicWords: _mnemonic,
      );
      ssm.finishBootstrap();
    });

    test('repeated invalidation is safe; stale transaction stays stale and '
        'empty', () async {
      SecurityCheckpoints.arm(SecurityCheckpoint.afterNekDerivation);
      final Future<void> attempt = ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      await SecurityCheckpoints.waitUntilPaused(
          SecurityCheckpoint.afterNekDerivation);
      ssm.lockSync();
      expect(() => ssm.lockSync(), returnsNormally);
      expect(() => ssm.lockSync(), returnsNormally);
      final d = ssm.activationDiagnostics;
      expect(d.transactionStale, isTrue);
      expect(d.transactionOwnsMk || d.transactionOwnsNek || d.transactionOwnsTek,
          isFalse);
      SecurityCheckpoints.release(SecurityCheckpoint.afterNekDerivation);
      await expectLater(attempt, throwsA(isA<SessionActivationException>()));
      expect(ssm.activationDiagnostics.transactionPresent, isFalse,
          reason: 'unlock() always detaches its transaction on exit');
    }, skip: _skipUnlessControl);

    test('ownership transfer removes transaction ownership (committed '
        'session: SessionKeyMaterial owns, transaction owns nothing)',
        () async {
      await ssm.unlock(
        password: _password,
        activateRoot: satisfyActivationContract,
        teardownRoot: () {},
      );
      final d = ssm.activationDiagnostics;
      expect(d.sessionKeysInstalled, isTrue);
      expect(d.transactionPresent, isFalse);
    });

    test('rollback (activateRoot throws) clears ownership and returns to '
        'LOCKED with nothing installed', () async {
      await expectLater(
        ssm.unlock(
          password: _password,
          activateRoot: (_) async => throw StateError('boom'),
          teardownRoot: () {},
        ),
        throwsA(isA<SessionActivationException>()),
      );
      final d = ssm.activationDiagnostics;
      expect(ssm.state, SessionState.locked);
      expect(d.sessionKeysInstalled, isFalse);
      expect(d.transactionPresent, isFalse);
      expect(d.registeredSessionResources, 0);
    });

    test('a wrong password leaves no transaction-owned material', () async {
      await expectLater(
        ssm.unlock(
          password: 'wrong-password-123',
          activateRoot: satisfyActivationContract,
          teardownRoot: () {},
        ),
        throwsA(isA<SessionAuthenticationException>()),
      );
      final d = ssm.activationDiagnostics;
      expect(d.transactionOwnsMk || d.transactionOwnsNek || d.transactionOwnsTek,
          isFalse);
      expect(ssm.state, SessionState.locked);
    });
  });
}
