import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class CertPinning {
  static const List<String> _pinnedCertificatesDerBase64 = [
    'MIID7TCCA5OgAwIBAgIQOlN6nJWIL/m3XywQTCqRVzAKBggqhkjOPQQDAjBgMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMTcwNQYDVQQDEy5TZWN0aWdvIFB1YmxpYyBTZXJ2ZXIgQXV0aGVudGljYXRpb24gQ0EgRFYgRTM2MB4XDTI2MDcwMjAwMDAwMFoXDTI2MDkyOTIzNTk1OVowFzEVMBMGA1UEAwwMKi5naXRodWIuY29tMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEmWVtx2zKcewyTkrobjf1VRQhAriZDkABRl8DAstZ5T8fBVTCdFAgSFHQK+HH0gOM829bkSFX/UurVSaOdmL6d6OCAnYwggJyMB8GA1UdIwQYMBaAFBeZqATBb+QtcKgKED0D0+kauCZjMB0GA1UdDgQWBBQx0MSPhwJyFo66tXdJtkyaa9iihDAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDATBJBgNVHSAEQjBAMDQGCysGAQQBsjEBAgIHMCUwIwYIKwYBBQUHAgEWF2h0dHBzOi8vc2VjdGlnby5jb20vQ1BTMAgGBmeBDAECATCBhAYIKwYBBQUHAQEEeDB2ME8GCCsGAQUFBzAChkNodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNTZXJ2ZXJBdXRoZW50aWNhdGlvbkNBRFZFMzYuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTCCAQQGCisGAQQB1nkCBAIEgfUEgfIA8AB3ANdtfRDRp/V3wsfpX9cAv/mCyTNaZeHQswFzF8DIxWl3AAABnyA2FKIAAAQDAEgwRgIhANOUeuD4foVQiaVQ/m8p67eLTz5IyJjHo0W3/zsS2quFAiEApsbSZY/NTsALen+/Ec6Rc2OUYM/eatz2u36ANCtoJT8AdQDIo8R/x7OtuTVrAT9qehJt4zpOQ6XGRvmXrTl1mR3PmgAAAZ8gNhSLAAAEAwBGMEQCIHB4Od7WRbwrpFrpHQv9V87iZeAsSnj0K7+2XD6Z2VOZAiBGRMu30NYdKxAf+kCdh2ltgzvq35mKrAbADLDTO8RgHTAjBgNVHREEHDAaggwqLmdpdGh1Yi5jb22CCmdpdGh1Yi5jb20wCgYIKoZIzj0EAwIDSAAwRQIgSVjslxNraquN0YmBFUddD4zYEPJTdicsjvG3nuF0ulMCIQDx+2/BBTB+hC0XUnE8MDQnwn8oIVWo2I+yt/qV7vPD5A==',
    'PLACEHOLDER_BACKUP_CERT_REPLACE_ME',
  ];
  static final DateTime _pinValidUntil = DateTime.utc(2028, 8, 6);

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
        } catch (_) {}
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
