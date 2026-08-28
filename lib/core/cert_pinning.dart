import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class CertPinning {
  // Primary pin: leaf certificate (*.github.com), rotates roughly every
  // ~90 days per Sectigo's short-lived cert cycle — expect to update this
  // periodically. Backup pin: the issuing intermediate CA
  // (Sectigo Public Server Authentication CA DV E36, valid until
  // 2036-03-21), which survives routine leaf rotation without needing an
  // app update. Deliberately NOT pinning the root — the intermediate is
  // specific enough to meaningfully restrict trust while still being
  // durable; the root is unnecessarily broad and would validate far more
  // than just this one issuing chain if ever misused.
  static const List<String> _pinnedCertificatesDerBase64 = [
    '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',
  ];
  // NOTE: this must be kept in sync with the actual notAfter date of the
  // leaf certificate above (currently 2026-09-29 23:59:59 UTC). Set a few
  // days *before* that real expiry, not after it and not exactly on it —
  // if this date is later than the certificate's real expiry, pinning
  // continues to enforce a dead certificate and blocks all GitHub
  // connectivity until this constant is updated and shipped.
  static final DateTime _pinValidUntil = DateTime.utc(2026, 9, 25);

  static bool get _pinningActive =>
      DateTime.now().toUtc().isBefore(_pinValidUntil) &&
      _pinnedCertificatesDerBase64
          .any((cert) => !cert.startsWith('PLACEHOLDER'));
  static http.Client createPinnedClient(
      {String pinnedHost = 'api.github.com'}) {
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
        } catch (e) {
          assert(() {
            developer.log(
              'cert_pinning: a pinned certificate failed to parse/load and was skipped — this is unexpected for a non-placeholder entry and should be investigated: $e',
              name: 'CertPinning',
              level: 900,
            );
            return true;
          }());
        }
      }
      if (loadedCount == 0) {
        return http.Client();
      }

      final httpClient = HttpClient(context: context);
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => false;
      return IOClient(httpClient);
    } catch (_) {
      return http.Client();
    }
  }

  static Future<String?> debugFetchCurrentCertificate(
      {String host = 'api.github.com', int port = 443}) async {
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
