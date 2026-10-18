import 'package:flutter_test/flutter_test.dart';
import 'package:rocen/core/screen_security.dart';

/// Default policy denies activation without an affirmative platform result.
/// `enabled` remains only MethodChannel acknowledgement; native enforcement is
/// UNVERIFIED until native source and target-platform evidence are reviewed.
void main() {
  test('only enabled status satisfies the default protected-session policy',
      () {
    expect(
        ScreenSecurity.satisfiesPolicy(ScreenSecurityStatus.enabled), isTrue);
    expect(
        ScreenSecurity.satisfiesPolicy(
            ScreenSecurityStatus.unsupportedPlatform),
        isFalse);
    expect(ScreenSecurity.satisfiesPolicy(ScreenSecurityStatus.unavailable),
        isFalse);
  });

  test(
      'on the test host (not Android) acquire reports unsupportedPlatform, '
      'which is not evidence of any protection', () async {
    final ScreenSecurityStatus status = await ScreenSecurity.acquire();
    expect(status, ScreenSecurityStatus.unsupportedPlatform);
    ScreenSecurity.release();
  });
}
