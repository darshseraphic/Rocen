import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rocen/core/master_key_production_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('rocen_master_store_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(MasterKeyLocalStore.boxName);
  });

  setUp(() async {
    await Hive.box(MasterKeyLocalStore.boxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  MasterKeyLocalRecord sample({
    RemoteRecoveryStatus status = RemoteRecoveryStatus.unpublished,
    String? repository,
    String? previous,
  }) => MasterKeyLocalRecord.authoritative(
        passwordVerifier: 'verifier',
        passwordWrap: '{"v":1}',
        recoveryWrap: '{"v":1,"kind":"recovery"}',
        remoteRecoveryStatus: status,
        repository: repository,
        previousPublishedRecoveryWrap: previous,
      );

  test('exact record round-trips through JSON and Hive', () async {
    final record = sample();
    final json = record.toJsonString();
    expect(json, contains('"schema":1'));
    expect(json, contains('"revision":1'));
    expect(json, contains('"authority":"authoritative"'));
    expect(json, contains('"passwordVerifier":"verifier"'));
    expect(json, contains('"passwordWrap":"{\\"v\\":1}"'));
    expect(json, contains('"recoveryWrap":"{\\"v\\":1,\\"kind\\":\\"recovery\\"}"'));
    expect(json, isNot(contains('masterKey')));
    expect(json, isNot(contains('mnemonic')));

    // No public write API exists: put the serialization straight into the
    // storage primitive, then read it back through the real reader.
    await Hive.box(MasterKeyLocalStore.boxName)
        .put(MasterKeyLocalStore.recordKey, json);
    final decoded = await MasterKeyLocalStore.read();
    expect(decoded, isNotNull);
    expect(decoded!.toJsonString(), json);
  });

  test('local-only authority may be unpublished without a repository', () {
    expect(() => sample(), returnsNormally);
  });

  test('published authority without repository is rejected', () {
    expect(
      () => sample(status: RemoteRecoveryStatus.published),
      throwsA(isA<FormatException>()),
    );
  });

  test('published authority with repository is valid', () {
    final record = sample(
      status: RemoteRecoveryStatus.published,
      repository: 'owner/repo',
    );
    expect(record.remoteRecoveryStatus, RemoteRecoveryStatus.published);
    expect(record.repository, 'owner/repo');
  });

  test('pending previous remote wrapper survives round-trip', () {
    final record = sample(
      status: RemoteRecoveryStatus.unpublished,
      repository: 'owner/repo',
      previous: '{"old":true}',
    );
    final decoded = MasterKeyLocalRecord.fromJsonString(record.toJsonString());
    expect(decoded.previousPublishedRecoveryWrap, '{"old":true}');
    expect(decoded.repository, 'owner/repo');
  });

  test('unsupported authority/schema/status is rejected', () {
    expect(
      () => MasterKeyLocalRecord.fromJsonString('{"schema":2}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MasterKeyLocalRecord.fromJsonString(
        '{"schema":1,"authority":"provisional"}',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MasterKeyLocalRecord.fromJsonString(
        '{"schema":1,"authority":"authoritative","passwordVerifier":"v","passwordWrap":"p","recoveryWrap":"r","remoteRecovery":{"status":"bogus"}}',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('revision rule rejects a stale authority writer (pure rule; the '
      'durable write itself is library-private and exercised through the '
      'production service)', () async {
    final first = sample();
    final committed = first.copyWith(repository: 'owner/current');
    final stale = first.copyWith(repository: 'owner/stale');

    // Initial creation must be revision 1.
    expect(
      () => MasterKeyLocalStore.checkRevisionTransition(
          current: null, next: committed),
      throwsA(isA<MasterKeyLocalRevisionConflict>()),
    );
    expect(
      () => MasterKeyLocalStore.checkRevisionTransition(
          current: null, next: first),
      returnsNormally,
    );
    // Exactly current+1 is accepted; a writer built from an older read
    // (same revision as `committed`... i.e. not current+1) is rejected.
    expect(
      () => MasterKeyLocalStore.checkRevisionTransition(
          current: first, next: committed),
      returnsNormally,
    );
    expect(
      () => MasterKeyLocalStore.checkRevisionTransition(
          current: committed, next: stale),
      throwsA(isA<MasterKeyLocalRevisionConflict>()),
    );

    await Hive.box(MasterKeyLocalStore.boxName).put(
        MasterKeyLocalStore.recordKey, committed.toJsonString());
    final current = await MasterKeyLocalStore.read();
    expect(current!.repository, 'owner/current');
    expect(current.revision, 2);
  });

  group('schema 1 has an EXACT key set (fail closed on unknown fields)', () {
    Map<String, dynamic> asMap(MasterKeyLocalRecord r) =>
        jsonDecode(r.toJsonString()) as Map<String, dynamic>;

    test('an unexpected TOP-LEVEL field is rejected by the parser and by '
        'the store reader', () async {
      final Map<String, dynamic> m = asMap(sample())..['future'] = true;
      final String raw = jsonEncode(m);
      expect(() => MasterKeyLocalRecord.fromJsonString(raw),
          throwsA(isA<FormatException>()));
      await Hive.box(MasterKeyLocalStore.boxName)
          .put(MasterKeyLocalStore.recordKey, raw);
      await expectLater(
          MasterKeyLocalStore.read(), throwsA(isA<FormatException>()));
    });

    test('an unexpected field INSIDE remoteRecovery is rejected', () async {
      final Map<String, dynamic> m = asMap(sample());
      (m['remoteRecovery'] as Map<String, dynamic>)['future'] = 'x';
      final String raw = jsonEncode(m);
      expect(() => MasterKeyLocalRecord.fromJsonString(raw),
          throwsA(isA<FormatException>()));
      await Hive.box(MasterKeyLocalStore.boxName)
          .put(MasterKeyLocalStore.recordKey, raw);
      await expectLater(
          MasterKeyLocalStore.read(), throwsA(isA<FormatException>()));
    });

    test('valid records - with and without the optional fields - still '
        'parse and round-trip', () {
      final MasterKeyLocalRecord bare = sample();
      final MasterKeyLocalRecord full = sample(
        status: RemoteRecoveryStatus.published,
        repository: 'owner/repo',
        previous: '{"v":1,"kind":"old"}',
      );
      for (final MasterKeyLocalRecord r in <MasterKeyLocalRecord>[bare, full]) {
        final MasterKeyLocalRecord back =
            MasterKeyLocalRecord.fromJsonString(r.toJsonString());
        expect(back.isSamePersistedRecordAs(r), isTrue);
        expect(back.toJsonString(), r.toJsonString());
      }
    });
  });

  group('strict persisted types and canonical optional metadata', () {
    Map<String, dynamic> asMap(MasterKeyLocalRecord r) =>
        jsonDecode(r.toJsonString()) as Map<String, dynamic>;

    MasterKeyLocalRecord full() => sample(
          status: RemoteRecoveryStatus.published,
          repository: 'owner/repo',
          previous: '{"v":1,"kind":"old"}',
        );

    void expectRejected(void Function(Map<String, dynamic> m) mutate,
        String reason) {
      final Map<String, dynamic> m = asMap(full());
      mutate(m);
      expect(() => MasterKeyLocalRecord.fromJsonString(jsonEncode(m)),
          throwsA(isA<FormatException>()),
          reason: reason);
    }

    test('schema and revision must be JSON INTEGERS (no numeric strings, '
        'doubles, booleans or null)', () {
      expectRejected((m) => m['schema'] = '1', 'schema "1"');
      expectRejected((m) => m['schema'] = 1.0, 'schema 1.0');
      expectRejected((m) => m['schema'] = true, 'schema true');
      expectRejected((m) => m['schema'] = null, 'schema null');
      expectRejected((m) => m.remove('schema'), 'schema missing');
      expectRejected((m) => m['revision'] = '2', 'revision "2"');
      expectRejected((m) => m['revision'] = 2.0, 'revision 2.0');
      expectRejected((m) => m['revision'] = null, 'revision null');
      expectRejected((m) => m['revision'] = 0, 'revision 0');
      expectRejected((m) => m['revision'] = -1, 'revision -1');
      expectRejected((m) => m.remove('revision'), 'revision missing');
    });

    test('credential fields must be STRINGS and are never stringified', () {
      for (final String key in <String>[
        'authority',
        'passwordVerifier',
        'passwordWrap',
        'recoveryWrap',
      ]) {
        expectRejected((m) => m[key] = 123, '$key as int');
        expectRejected((m) => m[key] = <String, dynamic>{'a': 1}, '$key as map');
        expectRejected((m) => m[key] = <String>['x'], '$key as list');
        expectRejected((m) => m[key] = null, '$key as null');
        expectRejected((m) => m.remove(key), '$key missing');
      }
      expectRejected((m) => m['passwordWrap'] = '', 'empty passwordWrap');
    });

    test('nested remoteRecovery field types are enforced', () {
      expectRejected((m) => m['remoteRecovery'] = <String>['x'], 'list');
      expectRejected((m) => m['remoteRecovery'] = 'x', 'string');
      expectRejected((m) => m['remoteRecovery'] = null, 'null');
      expectRejected(
          (m) => (m['remoteRecovery'] as Map<String, dynamic>)['status'] = 1,
          'status int');
      expectRejected(
          (m) => (m['remoteRecovery'] as Map<String, dynamic>)['status'] = null,
          'status null');
      expectRejected(
          (m) => (m['remoteRecovery'] as Map<String, dynamic>)['status'] = 'nope',
          'status unknown');
      expectRejected(
          (m) => (m['remoteRecovery'] as Map<String, dynamic>)['repository'] = 5,
          'repository int');
      expectRejected(
          (m) => (m['remoteRecovery'] as Map<String, dynamic>)['repository'] = null,
          'repository null');
      expectRejected(
          (m) => (m['remoteRecovery']
              as Map<String, dynamic>)['previousPublishedRecoveryWrap'] = 7,
          'previous int');
    });

    test('whitespace-altered or empty optional metadata is rejected, never '
        'trimmed into a different value', () {
      for (final String bad in <String>[
        ' owner/repo',
        'owner/repo ',
        ' owner/repo ',
        'owner/repo\n',
        '   ',
        '',
      ]) {
        expectRejected(
            (m) => (m['remoteRecovery'] as Map<String, dynamic>)['repository'] = bad,
            'repository "$bad"');
        expectRejected(
            (m) => (m['remoteRecovery']
                as Map<String, dynamic>)['previousPublishedRecoveryWrap'] = bad,
            'previous "$bad"');
      }
    });

    test('the WRITE side refuses non-canonical optional metadata instead of '
        'persisting something the strict parser cannot read back', () {
      expect(
          () => sample(
                status: RemoteRecoveryStatus.published,
                repository: ' owner/repo ',
              ).toJsonString(),
          throwsA(isA<FormatException>()));
      expect(
          () => sample(previous: ' padded ').toJsonString(),
          throwsA(isA<FormatException>()));
    });

    test('valid records with ABSENT optional fields and with all optional '
        'fields still round-trip byte-for-byte', () {
      final MasterKeyLocalRecord bare = sample();
      final Map<String, dynamic> m = asMap(bare);
      expect((m['remoteRecovery'] as Map<String, dynamic>).containsKey('repository'),
          isFalse);
      for (final MasterKeyLocalRecord r in <MasterKeyLocalRecord>[bare, full()]) {
        final MasterKeyLocalRecord back =
            MasterKeyLocalRecord.fromJsonString(r.toJsonString());
        expect(back.isSamePersistedRecordAs(r), isTrue);
        expect(back.toJsonString(), r.toJsonString());
      }
    });
  });

  group('local-record canonicality: validate(), serializer and parser agree',
      () {
    test('an explicitly supplied EMPTY optional value is refused at '
        'validation/write time instead of being silently omitted', () {
      expect(() => sample(repository: ''), throwsA(isA<FormatException>()));
      expect(() => sample(previous: ''), throwsA(isA<FormatException>()));
      expect(() => sample(repository: '   '), throwsA(isA<FormatException>()));
      expect(() => sample(repository: ' owner/repo'),
          throwsA(isA<FormatException>()));
      final MasterKeyLocalRecord ok = sample();
      // copyWith builds an in-memory record; the contract is that an invalid
      // record is refused by validate() and can never be SERIALISED/written.
      expect(() => ok.copyWith(repository: '').validate(),
          throwsA(isA<FormatException>()));
      expect(() => ok.copyWith(repository: '').toJsonString(),
          throwsA(isA<FormatException>()));
    });

    test('absent optional fields stay supported and are not serialised',
        () {
      final Map<String, dynamic> m =
          jsonDecode(sample().toJsonString()) as Map<String, dynamic>;
      final Map<String, dynamic> remote =
          m['remoteRecovery'] as Map<String, dynamic>;
      expect(remote.keys.toSet(), <String>{'status'});
    });

    test('a record with a DUPLICATE top-level property is rejected '
        '(jsonDecode alone would keep the last value)', () async {
      final String raw = sample().toJsonString();
      final String dup = raw.replaceFirst('"revision":1', '"revision":1,"revision":2');
      expect(dup, isNot(raw), reason: 'test setup: duplicate was injected');
      expect(jsonDecode(dup), isA<Map>(), reason: 'jsonDecode accepts it');
      expect(() => MasterKeyLocalRecord.fromJsonString(dup),
          throwsA(isA<FormatException>()));
      await Hive.box(MasterKeyLocalStore.boxName)
          .put(MasterKeyLocalStore.recordKey, dup);
      await expectLater(
          MasterKeyLocalStore.read(), throwsA(isA<FormatException>()));
    });

    test('a record with a DUPLICATE nested remoteRecovery property is '
        'rejected', () {
      final String raw = sample().toJsonString();
      final String dup = raw.replaceFirst(
          '"status":"unpublished"', '"status":"unpublished","status":"published"');
      expect(dup, isNot(raw));
      expect(() => MasterKeyLocalRecord.fromJsonString(dup),
          throwsA(isA<FormatException>()));
    });

    test('an escaped duplicate (\\u0061 vs a) is still a duplicate', () {
      final String raw = sample().toJsonString();
      final String dup = raw.replaceFirst('"authority":', '"\\u0061uthority":"x","authority":');
      expect(dup, isNot(raw));
      expect(() => MasterKeyLocalRecord.fromJsonString(dup),
          throwsA(isA<FormatException>()));
    });

    test('a valid record parses; whitespace or key-order differences are '
        'content-identical and are NOT treated as a different record (raw '
        'byte identity is deliberately not asserted)', () {
      final MasterKeyLocalRecord r = sample(
        status: RemoteRecoveryStatus.published,
        repository: 'owner/repo',
      );
      final String pretty =
          const JsonEncoder.withIndent('  ').convert(jsonDecode(r.toJsonString()));
      final MasterKeyLocalRecord back = MasterKeyLocalRecord.fromJsonString(pretty);
      expect(back.isSamePersistedRecordAs(r), isTrue);
    });
  });
}
