import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Rocen/core/crypto_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel =
      MethodChannel('com.darshseraphic.rocen/device_integrity');

  // NOTE: CryptoEngine._cachedRootStatus is a private static field with no
  // reset hook exposed. Because isDeviceRooted() short-circuits on a cached
  // non-null value (see source: `if (_cachedRootStatus != null) return
  // _cachedRootStatus!;`), only the FIRST call to isDeviceRooted() in this
  // test binary's lifetime will actually reach the native channel - every
  // call after that returns the cached value regardless of what the channel
  // mock does. This is why both assertions below live in a single test
  // case, in a fixed order, rather than as separate test() blocks: splitting
  // them would make the second test's outcome depend on the first, since
  // there is no way to reset the cache from outside the class between
  // Dart-level tests without adding a reset method to CryptoEngine itself
  // (out of scope for this change, since it means widening the class's API
  // surface purely for testability - not requested and not done here).
  test(
    'isDeviceRooted() fails closed on channel error, and the failure is cached as true',
    () async {
      // Arrange: make the native channel throw on every call, simulating a
      // platform-channel failure (e.g. the native isRooted() implementation
      // throwing, or the channel being unavailable).
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        throw PlatformException(
          code: 'FORCED_TEST_FAILURE',
          message: 'Simulated native channel failure for regression test',
        );
      });

      // Act: first call - this is the one that actually reaches the
      // (mocked, throwing) channel and exercises the catch block.
      final bool firstResult = await CryptoEngine.isDeviceRooted();

      // Assert: fails closed - assumes rooted, not "not rooted".
      expect(firstResult, isTrue,
          reason: 'On a channel failure, isDeviceRooted() must fail closed and '
              'assume the device IS rooted, so the hardened KDF tier is '
              'selected rather than the weaker standard tier.');

      // Now make the channel succeed and return false ("not rooted"), to
      // prove the SECOND call still returns true - because the cache from
      // the first (failed) call should be sticky for the rest of the
      // process, not silently cleared or re-queried.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        return false;
      });

      final bool secondResult = await CryptoEngine.isDeviceRooted();

      expect(secondResult, isTrue,
          reason: 'isDeviceRooted() caches its result after the first call '
              '(_cachedRootStatus). A cached "true" from a prior failure '
              'must persist for the rest of the session, even if the '
              'underlying channel would now succeed and report false - '
              'this proves the fail-closed cache is sticky, not just the '
              'single failing call.');
    },
  );
}
