import 'package:flutter_test/flutter_test.dart';
import 'package:rocen/core/github_backup_service.dart';
import 'support/fake_github_remote.dart';

void main() {
  group('raw reserved authority JSON rejects duplicate properties', () {
    final Map<String, List<String>> fixtures = <String, List<String>>{
      'device_key.json': <String>[
        '{"schema":1,"schema":1}',
        '{"device":{"id":"a","id":"b"}}',
        '{"a":1,"\\u0061":2}',
      ],
      'password_state.json': <String>[
        '{"passwordGeneration":1,"passwordGeneration":2}',
        '{"devices":[{"deviceNumber":1,"deviceNumber":2}]}',
        '{"devices":[{"a":1,"\\u0061":2}]}',
      ],
    };

    for (final MapEntry<String, List<String>> entry in fixtures.entries) {
      for (final String raw in entry.value) {
        test('${entry.key} rejects duplicate fixture', () async {
          final FakeGithubRemote remote = FakeGithubRemote()
            ..seed(entry.key, raw);
          await expectLater(
            remote.service.fetchNoteFile(entry.key),
            throwsA(isA<GithubSyncException>()),
          );
          expect(remote.mutationCount, 0);
          expect(remote.contentsRequests, hasLength(1),
              reason: 'fixture traversed actual GitHub Contents decoding');
        });
      }
    }

    test(
        'valid authority objects still decode and generic JSON compatibility '
        'does not acquire the reserved-file restriction', () async {
      final remote = FakeGithubRemote()
        ..seed('device_key.json', '{"schema":1,"devices":[]}')
        ..seed('backup.json', '{"a":1,"a":2}');
      expect(await remote.service.fetchNoteFile('device_key.json'),
          <String, dynamic>{'schema': 1, 'devices': <dynamic>[]});
      expect(await remote.service.fetchNoteFile('backup.json'),
          <String, dynamic>{'a': 2});
    });

    test('generic Contents payload above authority cap remains compatible',
        () async {
      final String value = List<String>.filled(270000, 'x').join();
      final String raw = '{"payload":"$value"}';
      final FakeGithubRemote remote = FakeGithubRemote()
        ..seed('large-backup.json', raw);
      final Map<String, dynamic>? parsed =
          await remote.service.fetchNoteFile('large-backup.json');
      expect(parsed?['payload'], value);
      expect(remote.contentsRequests, hasLength(1));
      expect(remote.mutationCount, 0);
    });
  });
}
