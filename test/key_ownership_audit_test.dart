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

  String read(String relative) => File('${libRoot.path}/$relative')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

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

    test(
        'the only bytes it touches are a transient local returned to the '
        'caller', () {
      final String src = code('core/master_key_manager.dart');
      expect(src, contains('Uint8List generateProvisionalMasterKeyBytes()'));
      // The generated buffer is a local `generated`, returned - never stored.
      expect(src, isNot(contains('_masterKeyBytes')));
      // No Uint8List-typed private FIELD (the lease's `this._owner` initialising
      // formal is an identity token, not key material, so the former
      // substring test for 'this._' was a false positive).
      expect(
          RegExp(r'^\s*(?:static\s+)?(?:late\s+)?(?:final\s+)?Uint8List\??\s+_\w+',
                  multiLine: true)
              .hasMatch(src),
          isFalse,
          reason: 'MasterKeyManager must not declare a Uint8List field');
    });

    test('the retired byte-holding API is gone from the entire source tree',
        () {
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
      // The session manager library is session_security_manager.dart plus
      // every file that is `part of` it - all of these legitimately
      // reference SessionKeyMaterial, either in code (session_key_material
      // .dart itself) or in documentation explaining the ownership model
      // (the others). Doc-comment mentions in files OUTSIDE this library are
      // also fine (e.g. explaining why a different class is NOT the owner);
      // what must never happen is a reference in actual CODE outside the
      // library, which is what would indicate a second construction site.
      const Set<String> sessionLibraryFiles = {
        'core/session_security_manager.dart',
        'core/session_key_material.dart',
        'core/session_unlock_service.dart',
        'core/activation_transaction.dart',
        'core/security_checkpoints.dart',
      };
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        if (sessionLibraryFiles.contains(rel)) continue;
        final String text = f
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(text, isNot(contains('SessionKeyMaterial')),
            reason: '$rel must not reference SessionKeyMaterial in actual '
                'code');
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
      // NO raw key bytes of any kind leave SessionKeyMaterial.
      expect(src, isNot(contains('_nekBytes')));
      expect(src, isNot(contains('_tekBytes')));
      expect(src, isNot(contains('Uint8List')));
    });

    test('destroy zeroes all three and bumps the stale-install generation', () {
      final String src = code('core/session_key_material.dart');
      final int d = src.indexOf('void _destroy()');
      final int bodyEnd = d + 700 < src.length ? d + 700 : src.length;
      final String body = src.substring(d, bodyEnd);
      expect(body, contains('_generation++'));
      expect(body, contains('mk?.zero()'));
      expect(body, contains('nek?.zero()'));
      expect(body, contains('tek?.zero()'));
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
        r'^[ \t]*static\s+(?!const)(?!final\s+(int|String|bool|double|Duration|RegExp|Sha256|Hkdf)\b)(SecureBytes|Uint8List|List<int>)',
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
          final String line =
              noComments.substring(m.start, noComments.indexOf('\n', m.start));
          expect(line.contains('('), isTrue,
              reason:
                  '${f.path}: static byte-bearing FIELD found: ${line.trim()}');
        }
      }
    });

    test('no provider, notifier or feature holds key material', () {
      final RegExp keyish = RegExp(
          r'(SecureBytes|Uint8List)\s+_?(mk|nek|tek|masterKey|noteKey|tokenKey)\b',
          caseSensitive: false);
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        if (!rel.contains('features/') &&
            !rel.endsWith('main.dart') &&
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
        'SessionKeyMaterial',
        '_authenticateWithPassword',
      ];
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        if (!rel.contains('features/')) continue;
        final String text = f.readAsStringSync();
        for (final String name in forbidden) {
          expect(text, isNot(contains(name)),
              reason: '$rel must not reference $name');
        }
      }
    });

    test(
        'NO raw NEK/TEK/MK egress exists anywhere in production lib/: the '
        'public getters are gone and nothing calls them', () {
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        final String text = code(rel);
        for (final String name in <String>[
          'requireNoteEncryptionKey',
          'requireGithubTokenEncryptionKey',
          '_nekBytes',
          '_tekBytes',
        ]) {
          expect(text, isNot(contains(name)), reason: '$rel references $name');
        }
      }
      // The session manager has no method returning a Uint8List at all.
      final String mgr = code('core/session_security_manager.dart');
      expect(RegExp(r'Uint8List\s+\w+\(').hasMatch(mgr), isFalse);
    });

    test('the unlock path hands ownership onward instead of caching', () {
      final String src = code('core/session_unlock_service.dart');
      // unlockWithPassword returns the buffer; the service declares no
      // class-level byte field of its own.
      final int classStart = src.indexOf('class SessionUnlockService {');
      final int classEnd = src.indexOf('\n}\n', classStart);
      expect(classStart, greaterThanOrEqualTo(0));
      expect(classEnd, greaterThan(classStart));
      final String serviceClass = src.substring(classStart, classEnd + 2);
      final RegExp classLevelBytes = RegExp(
        r'^  (static\s+)?(final\s+)?(late\s+)?(Uint8List|SecureBytes|List<int>)\??\s+_?\w+\s*(=|;)',
        multiLine: true,
      );
      expect(classLevelBytes.hasMatch(serviceClass), isFalse);
      expect(src, contains('zeroBytes(unwrapped)'));
    });

    test('Stage 4 derivation takes its input explicitly and reads no global',
        () {
      final String src = code('core/domain_key_derivation.dart');
      expect(src, isNot(contains('MasterKeyManager.instance')));
      expect(src,
          contains('deriveNoteEncryptionKey(\n    Uint8List masterKeyBytes'));
      expect(
          src,
          contains(
              'deriveGithubTokenEncryptionKey(\n    Uint8List masterKeyBytes'));
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

  group('SecurityCheckpoints has no security authority, mechanically', () {
    test('references no secret-bearing or authorization type/field', () {
      final String src = code('core/security_checkpoints.dart');
      const List<String> forbidden = <String>[
        'SecureBytes',
        'Uint8List',
        'SessionAuthorizationToken',
        'ActivationCapability',
        '_epoch',
        '_state ',
        '_authorization',
        '_activationCapability',
        '_sessionKeyMaterial',
        'PasswordKeyDerivation',
        'DomainKeyDerivation',
        'MasterKeyManager',
      ];
      for (final String name in forbidden) {
        expect(src, isNot(contains(name)),
            reason: 'security_checkpoints.dart must not reference $name');
      }
    });

    test(
        'every public method\'s signature carries only SecurityCheckpoint '
        'values or nothing', () {
      final String src = code('core/security_checkpoints.dart');
      // Every method signature line touching (SecurityCheckpoint or void)
      // parameters/returns - if a future edit adds a parameter of any other
      // type to arm/waitUntilPaused/release/reach, this regex will no longer
      // match all of them and the count check below will fail.
      final RegExp sigs = RegExp(
        r'static\s+(void|Future<void>)\s+\w+\(\s*(SecurityCheckpoint\s+\w+)?\s*\)',
      );
      final int methodCount = RegExp(r'static\s+(void|Future<void>)\s+\w+\(')
          .allMatches(src)
          .length;
      final int matchingCount = sigs.allMatches(src).length;
      expect(matchingCount, methodCount,
          reason:
              'a public method on SecurityCheckpoints has a signature other '
              'than (SecurityCheckpoint) -> void/Future<void> or () -> '
              'void/Future<void>');
    });

    test(
        'reach() returns null (no Future, no suspension) unless the '
        'compile-time test-control flag is on AND the checkpoint is armed', () {
      final String src = code('core/security_checkpoints.dart');
      final int i = src.indexOf('static Future<void>? reach(');
      expect(i, greaterThan(0));
      final int bodyEnd = i + 320 < src.length ? i + 320 : src.length;
      final String body = src.substring(i, bodyEnd);
      expect(body, contains('if (!_enabled) return null;'));
      expect(body, contains('if (_armed[checkpoint] != true) return null;'));
    });

    test(
        'arm and waitUntilPaused throw without the flag; release/reset are '
        'flag-guarded no-ops', () {
      final String src = code('core/security_checkpoints.dart');
      expect(
          src,
          contains(
              'static const bool _enabled = kSecurityTestControlEnabled;'));
      expect(code('core/test_control.dart'),
          contains("bool.fromEnvironment('ROCEN_SECURITY_TEST_CHECKPOINTS')"));
      final int arm = src.indexOf('static void arm(');
      expect(src.substring(arm, arm + 120), contains('_requireEnabled();'));
      final int wait = src.indexOf('static Future<void> waitUntilPaused(');
      expect(src.substring(wait, wait + 160), contains('_requireEnabled();'));
      final int rel = src.indexOf('static void release(');
      expect(src.substring(rel, rel + 100), contains('if (!_enabled) return;'));
      final int rst = src.indexOf('static void reset()');
      expect(src.substring(rst, rst + 100), contains('if (!_enabled) return;'));
    });

    test('production call sites only ever call reach(), never arm/release', () {
      const List<String> productionFiles = <String>[
        'core/session_unlock_service.dart',
        'core/session_key_material.dart',
        'core/session_security_manager.dart',
        'core/master_key_production_service.dart',
        'core/password_state_manager.dart',
      ];
      for (final String rel in productionFiles) {
        final String src = code(rel);
        expect(src, isNot(contains('SecurityCheckpoints.arm(')));
        expect(src, isNot(contains('SecurityCheckpoints.release(')));
        expect(src, isNot(contains('SecurityCheckpoints.reset(')));
      }
    });

    test('no production file outside the session library imports it directly',
        () {
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        if (rel == 'core/security_checkpoints.dart' ||
            rel == 'core/session_security_manager.dart') {
          continue;
        }
        final String text = f.readAsStringSync();
        expect(text, isNot(contains("import 'security_checkpoints.dart'")));
        expect(
            text, isNot(contains("import 'core/security_checkpoints.dart'")));
      }
    });
  });

  group('authorization is structurally non-bypassable', () {
    test(
        'no SessionAuthorizationPolicy-style type exists anywhere - the '
        'bypass was removed, not renamed or hidden', () {
      for (final File f in dartFiles()) {
        final String text = f.readAsStringSync();
        expect(text, isNot(contains('SessionAuthorizationPolicy')),
            reason: '${f.path}: a public type accepting arbitrary '
                'authorization logic must never exist - see '
                'SessionAuthorizationRequiredException\'s own documentation '
                'for why this was rejected even with a named ".none" '
                'constant');
      }
    });

    test(
        'associateRemote and changePassword each take a required, '
        'non-nullable SessionAuthorizationToken', () {
      final String src = code('core/master_key_production_service.dart');
      final RegExp requiredToken = RegExp(
        r'required SessionAuthorizationToken authorizationToken,',
      );
      expect(requiredToken.allMatches(src).length, 2,
          reason: 'expected exactly two required SessionAuthorizationToken '
              'parameters: associateRemote and changePassword');
      // The retired optional/bypassable shapes must never reappear.
      expect(src, isNot(contains('bool Function()? requireSessionAuthorized')));
      expect(src, isNot(contains('SessionAuthorizationToken?')),
          reason: 'the token parameter must never become nullable - that '
              'would reopen the "omit it" bypass');
    });

    test(
        'SessionAuthorizationToken has no public constructor anywhere it '
        'is used - only session_security_manager.dart can mint one', () {
      final String ssmSrc = code('core/session_security_manager.dart');
      // The only constructor is the private, underscore-named one.
      expect(ssmSrc, contains('SessionAuthorizationToken._(this._epoch)'));
      expect(ssmSrc, isNot(contains('SessionAuthorizationToken(')),
          reason: 'no public (non-underscore) constructor may exist');

      // No other file may reference this type in actual CODE - a doc
      // comment explaining what a file cannot do (e.g. SecurityCheckpoints'
      // own documentation) is not a violation, so this check strips
      // comments the same way code() does, rather than scanning raw text.
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        if (rel == 'core/session_security_manager.dart' ||
            rel == 'core/master_key_production_service.dart') {
          continue;
        }
        final String text = f
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(text, isNot(contains('SessionAuthorizationToken')),
            reason: '$rel must not reference SessionAuthorizationToken in '
                'actual code - it has no legitimate reason to construct or '
                'hold one directly');
      }
    });

    test(
        'real application code (settings.dart) only ever obtains a token '
        'via captureAuthorization() - never constructs, caches, or '
        'fabricates one', () {
      final String src = code('features/settings.dart');
      final RegExp captureCalls =
          RegExp(r'SessionSecurityManager\.instance\.captureAuthorization\(\)');
      expect(captureCalls.allMatches(src).length, 2,
          reason: 'expected exactly two captureAuthorization() call sites: '
              'the changePassword and associateRemote authorization '
              'arguments');
      // Must never call the ForTesting entry points - those have no
      // authorization concept at all and exist only for Stage 3's own
      // cryptographic/reconciliation tests.
      expect(src, isNot(contains('ForTesting(')),
          reason: 'settings.dart must never call a *ForTesting production '
              'entry point - those bypass authorization entirely and exist '
              'only for Stage 3 unit tests');
    });

    test(
        'no *ForTesting security mutation exists; the only ForTesting '
        'members are destructive resets that mint nothing and write nothing',
        () {
      final RegExp forTesting = RegExp(r'\w*ForTesting\w*\(');
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        final String text = f
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        for (final RegExpMatch m in forTesting.allMatches(text)) {
          final String name = m.group(0)!;
          final bool allowed = name == 'resetForTesting(' &&
              (rel == 'core/session_security_manager.dart' ||
                  rel == 'core/master_key_manager.dart');
          expect(allowed, isTrue, reason: '$rel declares/uses $name');
        }
      }
      // The two resets: classification is enforced mechanically.
      final String ssm = code('core/session_security_manager.dart');
      final int r = ssm.indexOf('void resetForTesting()');
      final String body = ssm.substring(r, ssm.indexOf('\n  }\n', r));
      expect(body, contains('lockSync();'));
      expect(body, contains('_state = SessionState.bootstrap;'));
      expect(body, isNot(contains('SessionAuthorizationToken._')));
      expect(body, isNot(contains('ActivationCapability._')));
      expect(body, isNot(contains('SessionState.unlocked')));
      expect(body, isNot(contains('MasterKeyLocalStore')));
    });

    test(
        'MasterKeyLocalStore has no public durable mutation; _write is '
        'referenced only from the production service library', () {
      final String store = code('core/master_key_local_store.dart');
      expect(store, isNot(contains('static Future<void> write(')));
      expect(store, isNot(contains('static Future<void> clear(')));
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        final String text = code(rel);
        if (rel == 'core/master_key_local_store.dart' ||
            rel == 'core/master_key_production_service.dart') {
          continue;
        }
        expect(text, isNot(contains('MasterKeyLocalStore._write')),
            reason: rel);
        expect(text, isNot(contains('MasterKeyLocalStore.write(')),
            reason: rel);
      }
      final String svc = code('core/master_key_production_service.dart');
      expect('MasterKeyLocalStore._write('.allMatches(svc).length, 1,
          reason: 'exactly one call site: the fenced helper');
      expect(svc, contains('static Future<void> _fencedWrite('));
      expect(svc, isNot(contains('MasterKeyLocalStore.write(')));
    });

    test(
        'every protected write and remote start is preceded by the final '
        'fence check with no await in between', () {
      final String svc = code('core/master_key_production_service.dart');
      final int fw = svc.indexOf('static Future<void> _fencedWrite(');
      final String body = svc.substring(
          fw, svc.indexOf('static Future<T>? _refuseIfUnauthorized'));
      final int seam = body.indexOf(
          'SecurityCheckpoints.reach(SecurityCheckpoint.beforeProtectedWrite)');
      final int check = body.indexOf('fence.check();');
      final int write = body.indexOf('await MasterKeyLocalStore._write(');
      expect(seam, greaterThan(0));
      expect(check, greaterThan(seam));
      expect(write, greaterThan(check));
      expect(body.substring(check, write), isNot(contains('await')));
      // Remote creates: fence.check() then the authority call, nothing between.
      final RegExp create = RegExp(
          r'fence\.check\(\);\n\s*final GithubAuthorityWriteGrant createGrant = _newGrant\([\s\S]*?\);\n\s*try \{\n\s*await (service|remoteService)\.authorityCreateFileIfAbsent\(');
      expect(create.allMatches(svc).length, 2);
      expect(svc, isNot(contains('.createFileIfAbsent(')));
      expect(
          svc, isNot(contains('PasswordStateManager.initializeOrJoinState')));
      expect(svc,
          isNot(contains('PasswordStateManager.publishRotationAtomically')));
      expect(svc, contains('final _MutationFence fence = _SessionFence('));
      expect(svc, contains('_BootstrapFence(permit)'));
      expect(svc, isNot(contains('_PreSessionFence')));
      expect(svc, isNot(contains('requirePreSession')));
    });
  });

  group('session boundary: provider/UI ownership (static)', () {
    test(
        'the privileged ProviderContainer is a ROOT container owned by '
        'ProtectedSessionResources and destroyed by lockSync via '
        'registration', () {
      final String res = code('core/protected_session_resources.dart');
      expect(res, contains('ProviderContainer()'));
      expect(res, isNot(contains('parent:')));
      expect(res, contains('container.dispose()'));
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        if (rel == 'core/protected_session_resources.dart') continue;
        final String text = code(rel);
        expect(text, isNot(contains('ProviderContainer(')), reason: rel);
      }
      final String main = code('main.dart');
      expect(main,
          contains('_session.registerSessionResource(capability, resources);'));
      expect(main, isNot(contains('ProtectedAppRoot')));
      expect(main, isNot(contains('parentContainer')));
      final int reg = main.indexOf('registerSessionResource(capability');
      final int firstAwait =
          main.indexOf('await ', main.indexOf('_activateProtectedSession('));
      expect(reg, lessThan(firstAwait),
          reason: 'resource registered before any await in activation');
    });

    test(
        'protected MaterialApp/Navigator are session-scoped: the shell and '
        'the session each own a distinct MaterialApp and only the shell is '
        'built when no session exists', () {
      final String main = code('main.dart');
      expect(RegExp(r'(?<![A-Za-z_])MaterialApp\(').allMatches(main).length, 2);
      final int sessionBranch = main.indexOf('return ProtectedSessionApp(');
      final int shellApp =
          main.indexOf("key: const ValueKey<String>('rocen-shell-app')");
      expect(sessionBranch, greaterThan(0));
      expect(shellApp, greaterThan(sessionBranch),
          reason: 'when a session exists the shell MaterialApp is not built');
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        if (rel == 'main.dart') continue;
        expect(
            RegExp(r'(?<![A-Za-z_])MaterialApp\(').hasMatch(code(rel)), isFalse,
            reason: rel);
      }
    });

    test(
        'feature screens are constructed only inside the protected shell '
        '(data-only navigation)', () {
      final String main = code('main.dart');
      final String tail = main.substring(main.indexOf('class _ProtectedShell'));
      for (final String screen in <String>[
        'QuickNoteScreen()',
        'ClipboardScreen()',
        'BookmarksScreen()',
        'IdeaInboxScreen()',
      ]) {
        expect(main.indexOf(screen),
            greaterThan(main.indexOf('class _ProtectedShell')));
        expect(tail, contains(screen));
      }
    });

    test(
        'lifecycle: every non-resumed state calls lockSync; resumed '
        'restores nothing', () {
      final String main = code('main.dart');
      final int i = main.indexOf('void didChangeAppLifecycleState');
      final String body = main.substring(i, main.indexOf('\n  }\n', i));
      for (final String st in <String>[
        'inactive',
        'hidden',
        'paused',
        'detached'
      ]) {
        expect(body, contains('AppLifecycleState.$st:'));
      }
      expect(body, contains('_session.lockSync();'));
      final int resumed = body.indexOf('AppLifecycleState.resumed:');
      expect(body.substring(resumed), contains('break;'));
      expect(body.substring(resumed), isNot(contains('unlock')));
    });

    test(
        'no feature or composition code talks to the screen-security '
        'channel directly', () {
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        if (rel == 'core/screen_security.dart') continue;
        expect(code(rel), isNot(contains('screen_security\')')), reason: rel);
        expect(code(rel), isNot(contains('preventScreenshotOn')), reason: rel);
      }
    });
  });

  group('unlock ordering (static)', () {
    test(
        'seven checkpoints occur in order, each followed by an immediate '
        'freshness check; teardown is registered before derivation; '
        'resources are destroyed before the visual teardown', () {
      final String src = code('core/session_security_manager.dart');
      final int u = src.indexOf('Future<void> unlock(');
      final String unlock =
          src.substring(u, src.indexOf('void _rollbackActivation'));
      final List<String> order = <String>[
        "_authenticateWithPassword(password, transaction)",
        '_activeTeardown = teardownRoot;',
        'transaction.deriveNoteEncryptionKey()',
        'SecurityCheckpoint.afterNekDerivation',
        "checkFreshOrThrow('AFTER_NEK_DERIVATION')",
        'transaction.deriveGithubTokenEncryptionKey()',
        'SecurityCheckpoint.afterTekDerivation',
        "checkFreshOrThrow('AFTER_TEK_DERIVATION')",
        'SecurityCheckpoint.beforeSessionInstall',
        "checkFreshOrThrow('BEFORE_SESSION_INSTALL')",
        '_sessionKeyMaterial._install(transaction)',
        'await activateRoot(capability)',
        'SecurityCheckpoint.beforeActivationCommit',
        "checkFreshOrThrow('BEFORE_ACTIVATION_COMMIT')",
        '_authorization = SessionAuthorizationToken._(_epoch);',
      ];
      int last = -1;
      for (final String needle in order) {
        final int at = unlock.indexOf(needle, last + 1);
        expect(at, greaterThan(last),
            reason: 'out of order or missing: $needle');
        last = at;
      }
      final String lock = src.substring(src.indexOf('void lockSync()'),
          src.indexOf('void _destroySessionResources'));
      expect(lock.indexOf('_activationTransaction?.invalidate();'),
          lessThan(lock.indexOf('_sessionKeyMaterial._destroy();')));
      expect(lock.indexOf('_destroySessionResources();'),
          lessThan(lock.indexOf('teardown();')));
      expect(lock, isNot(contains('await')));
    });

    test(
        'AFTER_MK_UNWRAP is fresh-checked before authority acknowledgement '
        'and the unwrap result is fresh-checked before adoption', () {
      final String src = code('core/session_unlock_service.dart');
      final int returned = src
          .indexOf("StaleActivationTransactionException('MK_UNWRAP_RETURNED')");
      final int adopt = src.indexOf('transaction.adoptCandidateMk(unwrapped);');
      final int fresh = src.indexOf("checkFreshOrThrow('AFTER_MK_UNWRAP')");
      final int ack =
          src.indexOf('acknowledgeRecoveredAuthority(lease: lease);');
      expect(returned, lessThan(adopt));
      expect(adopt, lessThan(fresh));
      expect(fresh, lessThan(ack));
      expect(src.substring(ack - 200, ack),
          contains("checkFreshOrThrow('AUTHORITY_ACKNOWLEDGE')"));
    });

    test('install() itself re-validates after AFTER_SESSION_INSTALL', () {
      final String src = code('core/session_key_material.dart');
      final int cp = src.indexOf('SecurityCheckpoint.afterSessionInstall');
      final String after = src.substring(cp, cp + 400);
      expect(after,
          contains('_generation != generationAtStart || transaction.isStale'));
      expect(after, contains('_destroy();'));
      expect(
          after, contains('throw const StaleActivationTransactionException'));
    });

    test(
        'SessionKeyMaterial.install holds no key buffer in a local across '
        'an await', () {
      final String src = code('core/session_key_material.dart');
      final int i = src.indexOf('Future<void> _install(');
      final String body = src.substring(i, src.indexOf('void _destroy()'));
      expect(body, isNot(contains('SecureBytes ')));
      expect(body, isNot(contains('Uint8List ')));
      expect(body, isNot(contains('DomainKeyDerivation')));
    });
  });

  group(
      'ActivationTransaction is an internal implementation detail, never '
      'used by feature/application code', () {
    test('it is library-private (class and constructor)', () {
      final String src = code('core/activation_transaction.dart');
      expect(src, contains('class _ActivationTransaction {'));
      expect(src, contains('_ActivationTransaction(this._epoch);'));
      expect(src, isNot(contains('class ActivationTransaction')));
    });

    test('no feature/UI/composition-root file references it at all', () {
      for (final File f in dartFiles()) {
        final String rel = f.path.substring(libRoot.path.length + 1).replaceAll('\\', '/');
        if (!rel.contains('features/') &&
            rel != 'main.dart' &&
            rel != 'navbar.dart') {
          continue;
        }
        expect(f.readAsStringSync(), isNot(contains('ActivationTransaction')),
            reason: rel);
      }
    });

    test('only unlock() assigns the manager\'s _activationTransaction field',
        () {
      final String src = code('core/session_security_manager.dart');
      final List<String> nonNull =
          RegExp(r'_activationTransaction\s*=\s*[^;]+;')
              .allMatches(src)
              .map((m) => m.group(0)!)
              .where((m) => !m.contains('= null;'))
              .toList();
      expect(
          nonNull, equals(<String>['_activationTransaction = transaction;']));
      expect(
        src,
        contains('final _ActivationTransaction transaction =\n'
            '        _ActivationTransaction(unlockEpoch);'),
      );
    });

    test(
        'the transaction owns the temporary secrets; the unlock path keeps '
        'no un-owned candidate local', () {
      final String src = code('core/session_security_manager.dart');
      final int u = src.indexOf('Future<void> unlock(');
      final String unlock =
          src.substring(u, src.indexOf('void _rollbackActivation'));
      expect(unlock, isNot(contains('Uint8List')));
      expect(unlock, isNot(contains('candidateMk')));
      final String tx = code('core/activation_transaction.dart');
      expect(tx, isNot(contains('relinquishCandidateMk')));
      expect(tx, isNot(contains('peekCandidateMkForHandoff')));
    });
  });
}
