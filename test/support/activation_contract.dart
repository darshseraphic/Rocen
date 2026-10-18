import 'package:rocen/core/session_security_manager.dart';
import 'package:rocen/core/protected_session_resources.dart';
import 'package:rocen/core/screen_security.dart';

/// An activator that satisfies the REAL activation contract that
/// `SessionSecurityManager.unlock()` enforces: it registers a privileged
/// session resource with the live [ActivationCapability] and reports the
/// protected root ready. It does not bypass or relax anything - the manager
/// still applies the screen-capture policy itself and refuses to commit an
/// activation that does not meet the contract (a plain no-op activator no
/// longer unlocks; see `activation_contract_test.dart`).
Future<void> satisfyActivationContract(ActivationCapability capability) async {
  final SessionSecurityManager ssm = SessionSecurityManager.instance;
  final ProtectedSessionResources resources = ProtectedSessionResources();
  ssm.registerSessionResource(capability, resources);
  resources.markReady();
  ssm.reportProtectedRootReady(capability);
}

/// Simulates only an affirmative Dart channel acknowledgement so tests of
/// post-policy activation can run on unsupported hosts. It does not claim OS
/// enforcement. The production default is untouched, and ScreenSecurity
/// rejects this control unless the compile-time security-test define is on.
void enableSimulatedScreenAcknowledgementForTest() {
  ScreenSecurity.useTestAcknowledgement();
}
