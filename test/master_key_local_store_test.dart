import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:Rocen/core/master_key_local_store.dart';

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

    await MasterKeyLocalStore.write(record);
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

  test('stale authority writer is rejected by durable revision check', () async {
    final first = sample();
    await MasterKeyLocalStore.write(first);
    final stale = first.copyWith(repository: 'owner/stale');
    final committed = first.copyWith(repository: 'owner/current');
    await MasterKeyLocalStore.write(committed);

    expect(
      () => MasterKeyLocalStore.write(stale),
      throwsA(isA<MasterKeyLocalRevisionConflict>()),
    );

    final current = await MasterKeyLocalStore.read();
    expect(current!.repository, 'owner/current');
    expect(current.revision, 2);
  });

}
