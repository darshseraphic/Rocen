import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:smart_dev_pinning_plugin/smart_dev_pinning_plugin.dart';

final class CertPinning {
  CertPinning._();

  static const String githubApiHost = 'api.github.com';
  static const int githubApiPort = 443;
  static const String _primarySpkiPin = String.fromEnvironment(
    'GITHUB_PRIMARY_SPKI_PIN',
    defaultValue: 'S2LUIbq4yUg5w+MYbj5LZOWAZAzaeNGJ9rTTc4GjvBQ=',
  );
  static const String _backupSpkiPin = String.fromEnvironment(
    'GITHUB_BACKUP_SPKI_PIN',
    defaultValue: '',
  );

  static http.Client? _cachedClient;
  static http.Client get client {
    return _cachedClient ??= _createClient();
  }

  static http.Client _createClient() {
    _validatePinConfiguration();

    final SecureClient nativeClient = SecureClient();

    return _PinnedGithubClient(nativeClient);
  }

  static List<String> get _pins {
    _validatePinConfiguration();

    return <String>[
      _primarySpkiPin,
      if (_backupSpkiPin.isNotEmpty) _backupSpkiPin,
    ];
  }

  static void _validatePinConfiguration() {
    if (_primarySpkiPin.isEmpty) {
      throw StateError(
        'GitHub primary SPKI pin is not configured.',
      );
    }

    _validateSpkiPin(
      _primarySpkiPin,
      name: 'primary',
    );
    if (_backupSpkiPin.isNotEmpty) {
      _validateSpkiPin(
        _backupSpkiPin,
        name: 'backup',
      );

      if (_primarySpkiPin == _backupSpkiPin) {
        throw StateError(
          'GitHub primary and backup SPKI pins must be different.',
        );
      }
    }
  }

  static void _validateSpkiPin(
    String pin, {
    required String name,
  }) {
    if (pin.trim() != pin) {
      throw StateError(
        'GitHub $name SPKI pin contains leading or trailing whitespace.',
      );
    }

    if (pin.isEmpty) {
      throw StateError(
        'GitHub $name SPKI pin is empty.',
      );
    }

    late final List<int> decoded;

    try {
      decoded = base64.decode(pin);
    } on FormatException {
      throw StateError(
        'GitHub $name SPKI pin is not valid Base64.',
      );
    }

    if (decoded.length != 32) {
      throw StateError(
        'GitHub $name SPKI pin must decode to exactly 32 bytes.',
      );
    }
  }

  static void resetClient() {
    _cachedClient = null;
  }
}

final class _PinnedGithubClient extends http.BaseClient {
  _PinnedGithubClient(this._nativeClient);

  final SecureClient _nativeClient;

  static const Duration _requestTimeout = Duration(seconds: 30);

  @override
  Future<http.StreamedResponse> send(
    http.BaseRequest request,
  ) async {
    _validateUri(request.url);

    _validateHeaders(request.headers);

    final List<int> requestBytes = await _readRequestBody(
      request,
    );

    String? body;

    if (requestBytes.isNotEmpty) {
      try {
        body = utf8.decode(
          requestBytes,
          allowMalformed: false,
        );
      } on FormatException {
        throw http.ClientException(
          'GitHub request body must be valid UTF-8.',
          request.url,
        );
      }
    }

    final SmartResponse response;

    try {
      response = await _nativeClient.httpRequest(
        method: request.method.toUpperCase(),
        url: request.url.toString(),
        headers: Map<String, String>.from(
          request.headers,
        ),
        body: body,
        encoding: 'raw',
        certificateHashes: CertPinning._pins,
        pinningMethod: PinningMethod.publicKey,
        timeout: _requestTimeout,
      );
    } on ArgumentError {
      throw http.ClientException(
        'Invalid secure GitHub request configuration.',
        request.url,
      );
    } on UnsupportedError {
      throw http.ClientException(
        'Native GitHub SPKI pinning is unavailable on this platform.',
        request.url,
      );
    } on Object catch (e, stackTrace) {
      debugPrint('GITHUB PINNING EXCEPTION: $e');
      debugPrintStack(stackTrace: stackTrace);

      throw http.ClientException(
        'Secure GitHub request failed: $e',
        request.url,
      );
    }

    final int? statusCode = response.statusCode;
    if (statusCode == null) {
      const String message = 'SECURE GITHUB CONNECTION UNAVAILABLE\n'
          'Rocen could not establish a secure connection to GitHub. '
          'Check your internet connection and try again. '
          'If GitHub has changed its server key, update Rocen to restore '
          'secure backup access. '
          'Your local data is unchanged.';

      if (kDebugMode) {
        debugPrint(
          'GITHUB SECURE CONNECTION FAILED (debug detail, not shown in release): '
          '${response.errorType ?? 'unknown error'}'
          '${response.error == null ? '' : ' - ${response.error}'}',
        );
      }

      throw http.ClientException(
        message,
        request.url,
      );
    }

    final Uint8List responseBytes = _responseBytes(response);

    return http.StreamedResponse(
      Stream<List<int>>.value(responseBytes),
      statusCode,
      contentLength: responseBytes.length,
      request: request,
      headers: const <String, String>{},
      isRedirect: statusCode >= 300 && statusCode < 400,
    );
  }

  static void _validateUri(Uri uri) {
    final bool validScheme = uri.scheme.toLowerCase() == 'https';

    final bool validHost = uri.host.toLowerCase() == CertPinning.githubApiHost;

    final bool validPort =
        !uri.hasPort || uri.port == CertPinning.githubApiPort;

    final bool noUserInfo = uri.userInfo.isEmpty;

    final bool noFragment = uri.fragment.isEmpty;

    if (!validScheme ||
        !validHost ||
        !validPort ||
        !noUserInfo ||
        !noFragment) {
      throw http.ClientException(
        'Blocked network request: only '
        'https://${CertPinning.githubApiHost}:'
        '${CertPinning.githubApiPort} is permitted.',
        uri,
      );
    }
  }

  static void _validateHeaders(
    Map<String, String> headers,
  ) {
    const Set<String> forbidden = <String>{
      'host',
      'content-length',
      'transfer-encoding',
      'connection',
      'upgrade',
    };

    for (final String name in headers.keys) {
      if (forbidden.contains(name.toLowerCase())) {
        throw ArgumentError(
          'Forbidden HTTP header: $name',
        );
      }
    }
  }

  static Future<List<int>> _readRequestBody(
    http.BaseRequest request,
  ) async {
    final List<int> bytes = <int>[];

    await for (final List<int> chunk in request.finalize()) {
      bytes.addAll(chunk);
    }

    return bytes;
  }

  static Uint8List _responseBytes(
    SmartResponse response,
  ) {
    if (response.dataBytes != null) {
      return response.dataBytes!;
    }

    if (response.data != null) {
      return Uint8List.fromList(
        utf8.encode(response.data!),
      );
    }

    return Uint8List(0);
  }

  @override
  void close() {}
}
