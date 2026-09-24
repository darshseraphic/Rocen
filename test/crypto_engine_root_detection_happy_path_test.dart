import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/crypto_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel('com.darshseraphic.rocen/device_integrity');

  // This lives in its own file (not alongside the failure-path test) so it
  // runs in a fresh isolate with CryptoEngine's static _cachedRootStatus
  // starting unset - if this were in the same file as the failure test, the
  // failure test's cached `true` would leak into this one and this test
  // could pass for the wrong reason (the stale cache) rather than because
  // the success path genuinely still works.
  test(
    'isDeviceRooted() still returns the real channel value on success (fix did not touch the happy path)',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        return false; // channel genuinely reports "not rooted"
      });

      final bool result = await CryptoEngine.isDeviceRooted();

      expect(result, isFalse,
          reason: 'When the native channel succeeds and reports false, '
              'isDeviceRooted() must still return false - the fail-closed '
              'change only affects the catch block, never the success path.');
    },
  );
}
