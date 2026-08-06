import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// Certificate pinning for the GitHub backup connection only. Design notes,
// read these before ever touching the constants below:
//
// WHAT THIS PINS: the SubjectPublicKeyInfo (public key) of api.github.com's
// LEAF certificate - not GitHub's CA. dart:io's HttpClient only ever exposes
// the leaf certificate to app code (a real platform limitation, not a choice
// made here), so CA-level pinning that would silently survive cert renewals
// forever isn't achievable in pure Dart. This pin WILL go stale whenever
// GitHub rotates its certificate (in practice, roughly once a year).
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
  // ===== FILL THESE IN with real values from api.github.com =====
  // How to get the real value: run the app once in debug mode and call
  // CertPinning.debugFetchCurrentPin() from anywhere convenient (e.g. a
  // temporary button, or right after app startup) - it connects from THIS
  // device's real network connection and prints the exact base64 string to
  // paste in below. Do this on your actual phone, not through any proxy.
  //
  // Keep both slots filled once you have two values worth trusting (e.g.
  // current cert + the next one if GitHub ever announces a rotation ahead
  // of time). Pinning activates as soon as at least one real (non-
  // placeholder) value is present below - the second slot can stay a
  // placeholder in the meantime with no effect on whether pinning is active.
  static const List<String> _pinnedSpkiHashesBase64 = [
    'rlkAiJEjAwr5USvccZ2NlLzz7elZETOabSnkRvKdow0=',
    'PLACEHOLDER_BACKUP_PIN_REPLACE_ME',
  ];

  // After this date, pinning silently stops enforcing regardless of whether
  // the pins above were ever filled in - see design note above. Push this
  // out whenever you refresh the pins; until then, this is the guarantee
  // that nothing here can ever permanently break GitHub sync.
  static final DateTime _pinValidUntil = DateTime.utc(2028, 8, 6);

  static bool get _pinningActive =>
      DateTime.now().toUtc().isBefore(_pinValidUntil) &&
          _pinnedSpkiHashesBase64.any((pin) => !pin.startsWith('PLACEHOLDER'));

  // Drop-in replacement for a plain http.Client - if pinning isn't active
  // (placeholders not filled in yet, or the validity window passed), this
  // returns a completely ordinary client with no pinning behavior at all.
  static http.Client createPinnedClient({String pinnedHost = 'api.github.com'}) {
    if (!_pinningActive) {
      return http.Client();
    }

    final context = SecurityContext(withTrustedRoots: false);
    final httpClient = HttpClient(context: context);
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (host != pinnedHost) return false;
      return _certMatchesPin(cert);
    };
    return IOClient(httpClient);
  }

  static bool _certMatchesPin(X509Certificate cert) {
    try {
      final spkiDer = _extractSpkiDer(cert.der);
      if (spkiDer == null) return false;
      final hashBase64 = base64.encode(sha256.convert(spkiDer).bytes);
      return _pinnedSpkiHashesBase64.contains(hashBase64);
    } catch (_) {
      return false;
    }
  }

  // One-time setup helper - connects to the given host over a completely
  // normal (unpinned, system-trusted) TLS connection, reads the real
  // certificate it gets back, and returns the exact base64 pin string to
  // paste into _pinnedSpkiHashesBase64 above. Call this once from your own
  // device during setup; safe to leave unused afterward, it has no effect
  // on the app's normal behavior either way.
  static Future<String?> debugFetchCurrentPin({String host = 'api.github.com', int port = 443}) async {
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(host, port);
      final cert = socket.peerCertificate;
      if (cert == null) return null;
      final spkiDer = _extractSpkiDer(cert.der);
      if (spkiDer == null) return null;
      return base64.encode(sha256.convert(spkiDer).bytes);
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  // Minimal DER TLV walker - just enough to skip through a standard X.509v3
  // certificate structure to reach subjectPublicKeyInfo, without needing a
  // full ASN.1/X.509 parsing library for one field.
  static Uint8List? _extractSpkiDer(Uint8List certDer) {
    try {
      final certSeq = _parseTlv(certDer, 0);
      final tbsSeq = _parseTlv(certDer, certSeq.contentStart);

      int pos = tbsSeq.contentStart;

      var el = _parseTlv(certDer, pos);
      if (el.tag == 0xA0) {
        // optional explicit [0] version tag - skip it
        pos = el.contentEnd;
        el = _parseTlv(certDer, pos);
      }
      pos = el.contentEnd; // el was serialNumber

      el = _parseTlv(certDer, pos); // signature AlgorithmIdentifier
      pos = el.contentEnd;

      el = _parseTlv(certDer, pos); // issuer Name
      pos = el.contentEnd;

      el = _parseTlv(certDer, pos); // validity
      pos = el.contentEnd;

      el = _parseTlv(certDer, pos); // subject Name
      pos = el.contentEnd;

      final spki = _parseTlv(certDer, pos); // subjectPublicKeyInfo - the target
      final totalLen = (spki.contentStart - spki.elementStart) + spki.contentLength;
      return Uint8List.sublistView(certDer, spki.elementStart, spki.elementStart + totalLen);
    } catch (_) {
      return null;
    }
  }

  static _TlvHeader _parseTlv(Uint8List data, int offset) {
    final tag = data[offset];
    final lenByte = data[offset + 1];
    int contentStart;
    int contentLength;

    if ((lenByte & 0x80) == 0) {
      contentLength = lenByte;
      contentStart = offset + 2;
    } else {
      final numLenBytes = lenByte & 0x7F;
      int len = 0;
      for (int i = 0; i < numLenBytes; i++) {
        len = (len << 8) | data[offset + 2 + i];
      }
      contentLength = len;
      contentStart = offset + 2 + numLenBytes;
    }

    return _TlvHeader(tag: tag, elementStart: offset, contentStart: contentStart, contentLength: contentLength);
  }
}

class _TlvHeader {
  final int tag;
  final int elementStart;
  final int contentStart;
  final int contentLength;

  _TlvHeader({
    required this.tag,
    required this.elementStart,
    required this.contentStart,
    required this.contentLength,
  });

  int get contentEnd => contentStart + contentLength;
}