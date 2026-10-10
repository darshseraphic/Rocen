import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mechanical, source-level enforcement of the Stage 5 single-owner invariant.
///
///   UNLOCKED -> SessionKeyMaterial is the sole live owner of MK / NEK / TEK.
///   LOCKED   -> no live authoritative session key material remains anywhere.
///
/// These checks read the real source (same convention as
/// final_cutover_security_static_test.dart). They cannot prove Dart's GC has
/// erased every historical copy - nothing can - but they do prove that no
/// class, static field, provider or feature deliberately retains MK/NEK/TEK,
/// and they fail loudly if a future change reintroduces a second owner.
void main() {
  final Directory libRoot = Directory('${Directory.current.path}/lib');

  List<File> dartFiles() => libRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String read(String relative) =>
      File('${libRoot.path}/$relative').readAsStringSync().replaceAll('\r\n', '\n');

  /// Source with // and /// comments removed, so prose cannot satisfy or
  /// trip a structural check.
  String code(String relative) => read(relative)
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('MasterKeyManager is a controller, never a key custodian', () {
    test('declares no key-bearing field of any kind', () {
      final String src = code('core/master_key_manager.dart');
      // No SecureBytes anywhere, and no Uint8List field.
      expect(src, isNot(contains('SecureBytes')));
      expect(src, isNot(contains("import 'secure_bytes.dart'")));
      final RegExp classLevelBytesField = RegExp(
        r'^  (static\s+)?(final\s+)?(late\s+)?(Uint8List|List<int>)\??\s+_?\w+\s*(=|;)',
        multiLine: true,
      );
      expect(classLevelBytesField.hasMatch(src), isFalse,
          reason: 'MasterKeyManager must not gain a Uint8List/List<int> field');
    });

    test('the only bytes it touches are a transient local returned to the '
        'caller', () {
      final String src = code('core/master_key_manager.dart');
      expect(src, contains('Uint8List generateProvisionalMasterKeyBytes()'));
      // The generated buffer is a local `generated`, returned - never stored.
      expect(src, isNot(contains('_masterKeyBytes')));
      expect(src, isNot(contains('this._')));
    });

    test('the retired byte-holding API is gone from the entire source tree', () {
      const List<String> retired = <String>[
        'requireAuthoritativeMasterKeyBytes',
        'requireProvisionalMasterKeyBytes',
        'setAuthoritativeMasterKeyFromRecovery',
        'promoteProvisionalToAuthoritative',
        'discardProvisionalMasterKey',
        'generateProvisionalMasterKey(',
      ];
      for (final File f in dartFiles()) {
        final String text = f.readAsStringSync();
        for (final String name in retired) {
          // Allow the name only inside comments (documentation of the change).
          final String noComments = text
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n');
          expect(noComments, isNot(contains(name)),
              reason: '${f.path} still references retired API $name');
        }
      }
    });

    test('MasterKeyState is operation-scoped: reset when the lease ends', () {
      final String src = code('core/master_key_manager.dart');
      final int finallyIdx = src.indexOf('lease._released = true;');
      expect(finallyIdx, greaterThan(0));
      final String tail = src.substring(finallyIdx, finallyIdx + 400);
      expect(tail, contains('_state = MasterKeyState.none'));
    });
  });

  group('SessionKeyMaterial is the sole, structurally-unforgeable owner', () {
    test('it is a private-constructor part of the session manager library', () {
      final String skm = code('core/session_key_material.dart');
      final String ssm = code('core/session_security_manager.dart');
      expect(skm, contains("part of 'session_security_manager.dart'"));
      expect(ssm, contains("part 'session_key_material.dart'"));
      expect(skm, contains('SessionKeyMaterial._();'));
      expect(ssm, contains('SessionKeyMaterial._()'));
    });

    test('nothing outside the session manager library can construct it', () {
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1);
        if (rel.endsWith('core/session_security_manager.dart') ||
            rel.endsWith('core/session_key_material.dart')) {
          continue;
        }
        final String text = f.readAsStringSync();
        expect(text, isNot(contains('SessionKeyMaterial')),
            reason: '$rel must not reference SessionKeyMaterial at all');
      }
    });

    test('it holds exactly MK, NEK and TEK - no other key-bearing field', () {
      final String src = code('core/session_key_material.dart');
      final RegExp fields = RegExp(
        r'^  (static\s+)?(final\s+)?(late\s+)?(SecureBytes|Uint8List|List<int>)\??\s+(_?\w+)\s*(=|;)',
        multiLine: true,
      );
      final Set<String> names =
          fields.allMatches(src).map((m) => m.group(5)!).toSet();
      expect(names, equals(<String>{'_mk', '_nek', '_tek'}));
    });

    test('there is no accessor that returns the raw Master Key', () {
      final String src = code('core/session_key_material.dart');
      expect(src, isNot(contains('mkBytes')));
      expect(src, isNot(contains('mkBytesForAuditOnly')));
      // Only NEK/TEK copies are exposed.
      expect(src, contains('Uint8List nekBytes()'));
      expect(src, contains('Uint8List tekBytes()'));
    });

    test('destroy zeroes all three and bumps the stale-install generation', () {
      final String src = code('core/session_key_material.dart');
      final int d = src.indexOf('void destroy()');
      final String body = src.substring(d, d + 700);
      expect(body, contains('_generation++'));
      expect(body, contains('_mk?.zero()'));
      expect(body, contains('_nek?.zero()'));
      expect(body, contains('_tek?.zero()'));
      expect(body, contains('_installed = false'));
    });

    test('install refuses to publish a stale install', () {
      final String src = code('core/session_key_material.dart');
      expect(src, contains('generationAtStart'));
      expect(src, contains('_generation != generationAtStart'));
    });
  });

  group('no other owner, cache, or retention channel exists', () {
    test('no static mutable byte/key state anywhere in lib/', () {
      final RegExp staticBytes = RegExp(
        r'^\s*static\s+(?!const)(?!final\s+(int|String|bool|double|Duration|RegExp|Sha256|Hkdf)\b)(SecureBytes|Uint8List|List<int>)',
        multiLine: true,
      );
      for (final File f in dartFiles()) {
        final String text = f.readAsStringSync().replaceAll('\r\n', '\n');
        final String noComments = text
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        // Static METHODS returning bytes are fine; static FIELDS are not.
        for (final RegExpMatch m in staticBytes.allMatches(noComments)) {
          final String line = noComments.substring(m.start, noComments.indexOf('\n', m.start));
          expect(line.contains('('), isTrue,
              reason: '${f.path}: static byte-bearing FIELD found: ${line.trim()}');
        }
      }
    });

    test('no provider, notifier or feature holds key material', () {
      final RegExp keyish = RegExp(
          r'(SecureBytes|Uint8List)\s+_?(mk|nek|tek|masterKey|noteKey|tokenKey)\b',
          caseSensitive: false);
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1);
        if (!rel.contains('features/') && !rel.endsWith('main.dart') &&
            !rel.endsWith('navbar.dart')) {
          continue;
        }
        expect(keyish.hasMatch(f.readAsStringSync()), isFalse,
            reason: '$rel must not declare a key-material field/variable');
      }
    });

    test('feature code never touches the manager, unlock service or derivation',
        () {
      const List<String> forbidden = <String>[
        'MasterKeyManager',
        'DomainKeyDerivation',
        'unlockWithPassword',
        'SessionKeyMaterial',
      ];
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1);
        if (!rel.contains('features/')) continue;
        final String text = f.readAsStringSync();
        for (final String name in forbidden) {
          expect(text, isNot(contains(name)),
              reason: '$rel must not reference $name');
        }
      }
    });

    test('the only NEK/TEK egress is the authorization-gated session API', () {
      final String src = code('core/session_security_manager.dart');
      final int nek = src.indexOf('Uint8List requireNoteEncryptionKey()');
      final int tek = src.indexOf('Uint8List requireGithubTokenEncryptionKey()');
      expect(nek, greaterThan(0));
      expect(tek, greaterThan(0));
      expect(src.substring(nek, nek + 160), contains('_requireUnlocked()'));
      expect(src.substring(tek, tek + 160), contains('_requireUnlocked()'));
    });

    test('the unlock path hands ownership onward instead of caching', () {
      final String src = code('core/session_unlock_service.dart');
      // unlockWithPassword returns the buffer; the service declares no
      // class-level byte field of its own.
      final RegExp classLevelBytes = RegExp(
        r'^  (static\s+)?(final\s+)?(late\s+)?(Uint8List|SecureBytes|List<int>)\??\s+_?\w+\s*(=|;)',
        multiLine: true,
      );
      expect(classLevelBytes.hasMatch(src), isFalse);
      expect(src, contains('zeroBytes(unwrapped)'));
    });

    test('Stage 4 derivation takes its input explicitly and reads no global',
        () {
      final String src = code('core/domain_key_derivation.dart');
      expect(src, isNot(contains('MasterKeyManager.instance')));
      expect(src, contains('deriveNoteEncryptionKey(\n    Uint8List masterKeyBytes'));
      expect(src, contains('deriveGithubTokenEncryptionKey(\n    Uint8List masterKeyBytes'));
    });

    test('frozen Stage 4 labels are unchanged', () {
      final String src = code('core/domain_key_derivation.dart');
      expect(src, contains("'rocen:v2:notes'"));
      expect(src, contains("'rocen:v2:github_token'"));
    });
  });

  group('the outer ProviderScope carries no session secret', () {
    test('main.dart declares exactly one provider: the theme', () {
      final String src = code('main.dart');
      final RegExp providers = RegExp(
          r'(final\s+\w+\s*=\s*(Notifier|State|Future|Stream|Async)?\w*Provider)');
      final List<String> found =
          providers.allMatches(src).map((m) => m.group(0)!).toList();
      expect(found.length, 1, reason: 'found: $found');
      expect(src, contains('themeProvider'));
    });

    test('navigation state is pure data (no widget instance retained)', () {
      final String src = code('navbar.dart');
      expect(src, isNot(contains('final Widget')));
      expect(src, isNot(contains('Widget screen')));
      expect(src, isNot(contains('Widget Function')));
      expect(src, isNot(contains('QuickNoteScreen')));
    });
  });
}
