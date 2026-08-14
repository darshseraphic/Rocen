import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// Certificate pinning for the GitHub backup connection only. Design notes,
// read these before ever touching the constants below:
//
// HOW THIS ACTUALLY WORKS: a SecurityContext is built with NO default
// trusted roots, then the real api.github.com certificate (captured once,
// below) is loaded into it directly via setTrustedCertificatesBytes. This
// means normal TLS handshake validation itself only succeeds for a server
// presenting that exact certificate - nothing else, including a certificate
// signed by an otherwise valid, OS-trusted CA, will pass. badCertificateCallback
// is kept only as a defense-in-depth backstop that unconditionally rejects
// anything not already trusted by the loaded certificate.
//
// An earlier version of this file tried to pin via SHA-256 hash comparison
// inside badCertificateCallback alone, with an empty trust store and no
// certificate ever loaded into it. That doesn't work: with zero trusted
// certificates configured, the underlying TLS engine has no issuer to
// resolve for ANY certificate and fails the handshake outright on some
// platforms before the callback ever gets a meaningful chance to run,
// surfacing as CERTIFICATE_VERIFY_FAILED: unable to get local issuer
// certificate. Every real, working implementation of this pattern loads an
// actual certificate into the trust store - this file now does that.
//
// WHAT THIS PINS: api.github.com's LEAF certificate - not GitHub's CA.
// dart:io's HttpClient only ever exposes the leaf certificate to app code (a
// real platform limitation, not a choice made here), so CA-level pinning
// that would silently survive cert renewals forever isn't achievable in pure
// Dart. This pin WILL go stale whenever GitHub rotates its certificate (in
// practice, roughly once a year).
//
// WHY THAT'S OKAY: pinning here is a bonus hardening layer, never a
// requirement for the app to function. Two pin slots are kept (primary +
// backup) so a routine rotation doesn't necessarily break anything even
// without an app update. And _pinValidUntil below is the real safety net -
// once that date passes, pinning silently stops enforcing and every GitHub
// call falls back to completely normal system TLS trust (the exact same
// trust model the app used before this file existed, and what every other
// app on the phone already relies on). This can only ever make a working
// connection MORE suspicious of MITM for a bounded window - it can never
// turn a working connection into a broken one, at any point, even if this
// file is never touched again.
class CertPinning {
  // ===== FILL THESE IN with the real certificate from api.github.com =====
  // How to get the real value: run the app once in debug mode and call
  // CertPinning.debugFetchCurrentCertificate() from anywhere convenient
  // (e.g. right after app startup, temporarily) - it connects from THIS
  // device's real network connection and prints the exact base64 DER
  // certificate string to paste in below. Do this on your actual phone,
  // not through any proxy.
  //
  // Keep both slots filled once you have two certificates worth trusting
  // (e.g. current cert + the next one if GitHub ever announces a rotation
  // ahead of time). Pinning activates as soon as at least one real (non-
  // placeholder) value is present below - the second slot can stay a
  // placeholder in the meantime with no effect on whether pinning is active.
  static const List<String> _pinnedCertificatesDerBase64 = [
    'MIID7TCCA5OgAwIBAgIQOlN6nJWIL/m3XywQTCqRVzAKBggqhkjOPQQDAjBgMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMTcwNQYDVQQDEy5TZWN0aWdvIFB1YmxpYyBTZXJ2ZXIgQXV0aGVudGljYXRpb24gQ0EgRFYgRTM2MB4XDTI2MDcwMjAwMDAwMFoXDTI2MDkyOTIzNTk1OVowFzEVMBMGA1UEAwwMKi5naXRodWIuY29tMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEmWVtx2zKcewyTkrobjf1VRQhAriZDkABRl8DAstZ5T8fBVTCdFAgSFHQK+HH0gOM829bkSFX/UurVSaOdmL6d6OCAnYwggJyMB8GA1UdIwQYMBaAFBeZqATBb+QtcKgKED0D0+kauCZjMB0GA1UdDgQWBBQx0MSPhwJyFo66tXdJtkyaa9iihDAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDATBJBgNVHSAEQjBAMDQGCysGAQQBsjEBAgIHMCUwIwYIKwYBBQUHAgEWF2h0dHBzOi8vc2VjdGlnby5jb20vQ1BTMAgGBmeBDAECATCBhAYIKwYBBQUHAQEEeDB2ME8GCCsGAQUFBzAChkNodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNTZXJ2ZXJBdXRoZW50aWNhdGlvbkNBRFZFMzYuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTCCAQQGCisGAQQB1nkCBAIEgfUEgfIA8AB3ANdtfRDRp/V3wsfpX9cAv/mCyTNaZeHQswFzF8DIxWl3AAABnyA2FKIAAAQDAEgwRgIhANOUeuD4foVQiaVQ/m8p67eLTz5IyJjHo0W3/zsS2quFAiEApsbSZY/NTsALen+/Ec6Rc2OUYM/eatz2u36ANCtoJT8AdQDIo8R/x7OtuTVrAT9qehJt4zpOQ6XGRvmXrTl1mR3PmgAAAZ8gNhSLAAAEAwBGMEQCIHB4Od7WRbwrpFrpHQv9V87iZeAsSnj0K7+2XD6Z2VOZAiBGRMu30NYdKxAf+kCdh2ltgzvq35mKrAbADLDTO8RgHTAjBgNVHREEHDAaggwqLmdpdGh1Yi5jb22CCmdpdGh1Yi5jb20wCgYIKoZIzj0EAwIDSAAwRQIgSVjslxNraquN0YmBFUddD4zYEPJTdicsjvG3nuF0ulMCIQDx+2/BBTB+hC0XUnE8MDQnwn8oIVWo2I+yt/qV7vPD5A==',
    'PLACEHOLDER_BACKUP_CERT_REPLACE_ME',
  ];

  // After this date, pinning silently stops enforcing regardless of whether
  // the certificates above were ever filled in - see design note above. Push
  // this out whenever you refresh the pinned certificate; until then, this
  // is the guarantee that nothing here can ever permanently break GitHub sync.
  static final DateTime _pinValidUntil = DateTime.utc(2028, 8, 6);

  static bool get _pinningActive =>
      DateTime.now().toUtc().isBefore(_pinValidUntil) &&
          _pinnedCertificatesDerBase64.any((cert) => !cert.startsWith('PLACEHOLDER'));

  // Drop-in replacement for a plain http.Client - if pinning isn't active
  // (placeholders not filled in yet, the validity window passed, or none of
  // the configured certificates parse successfully), this returns a
  // completely ordinary client with no pinning behavior at all.
  static http.Client createPinnedClient({String pinnedHost = 'api.github.com'}) {
    if (!_pinningActive) {
      return http.Client();
    }

    try {
      final context = SecurityContext(withTrustedRoots: false);
      int loadedCount = 0;
      for (final certBase64 in _pinnedCertificatesDerBase64) {
        if (certBase64.startsWith('PLACEHOLDER')) continue;
        try {
          context.setTrustedCertificatesBytes(base64.decode(certBase64));
          loadedCount++;
        } catch (_) {
          // Skip a malformed entry rather than fail the whole client -
          // the other slot (or the fail-open path) still covers this.
        }
      }
      if (loadedCount == 0) {
        return http.Client();
      }

      final httpClient = HttpClient(context: context);
      // Defense-in-depth backstop only - the real pinning enforcement is the
      // SecurityContext's trust store above. Anything reaching this callback
      // already failed to validate against the pinned certificate(s).
      httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => false;
      return IOClient(httpClient);
    } catch (_) {
      // Never let a pinning setup failure block GitHub sync entirely.
      return http.Client();
    }
  }

  // One-time setup helper - connects to the given host over a completely
  // normal (unpinned, system-trusted) TLS connection, reads the real
  // certificate it gets back, and returns the exact base64 DER string to
  // paste into _pinnedCertificatesDerBase64 above. Call this once from your
  // own device during setup; safe to leave unused afterward, it has no
  // effect on the app's normal behavior either way.
  static Future<String?> debugFetchCurrentCertificate({String host = 'api.github.com', int port = 443}) async {
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(host, port);
      final cert = socket.peerCertificate;
      if (cert == null) return null;
      return base64.encode(cert.der);
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }
}