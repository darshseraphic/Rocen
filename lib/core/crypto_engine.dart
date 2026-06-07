import 'dart:convert';

class CryptoEngine {
  /// Transforms text payloads using an element-wise cryptographic XOR shifting mask.
  ///
  /// Because XOR operations are strictly symmetrical, passing an encrypted string
  /// back into this matrix using the exact same PIN buffer seamlessly decrypts it.
  static String xorProcess(String input, String pin) {
    if (input.isEmpty || pin.isEmpty) return input;

    // Convert both strings to UTF-8 code-unit arrays to process characters accurately
    final List<int> inputBytes = utf8.encode(input);
    final List<int> pinBytes = utf8.encode(pin);
    final List<int> resultBytes = List<int>.filled(inputBytes.length, 0);

    // Dynamic state modifier to increase structural confusion across recurring characters
    int pinSumShift = 0;
    for (int byte in pinBytes) {
      pinSumShift += byte;
    }

    for (int i = 0; i < inputBytes.length; i++) {
      // Pick the corresponding key byte from the repeating PIN sequence
      final int basePinByte = pinBytes[i % pinBytes.length];

      // Calculate a shifting offset based on the character position index
      final int positionalMask = (basePinByte + pinSumShift + i) & 0xFF;

      // Execute the XOR transform process
      resultBytes[i] = inputBytes[i] ^ positionalMask;
    }

    // Convert the mutated binary blocks into standard cross-platform Base64 strings
    // when encrypting, or reverse back to readable string formats on decryption.
    try {
      // If the incoming text is already a clean Base64 string, attempt to decode and decrypt it
      final String trimmedInput = input.trim();
      final List<int> possibleBase64Bytes = base64.decode(trimmedInput);

      // Recalculate mirror transform matrix for decryption phase
      final List<int> decryptedBytes = List<int>.filled(possibleBase64Bytes.length, 0);
      for (int i = 0; i < possibleBase64Bytes.length; i++) {
        final int basePinByte = pinBytes[i % pinBytes.length];
        final int positionalMask = (basePinByte + pinSumShift + i) & 0xFF;
        decryptedBytes[i] = possibleBase64Bytes[i] ^ positionalMask;
      }

      return utf8.decode(decryptedBytes);
    } catch (_) {
      // If input cannot be parsed as Base64 data, it means we are performing an initial encryption.
      // We return the encrypted byte array packed inside a secure Base64 transmission block.
      return base64.encode(resultBytes);
    }
  }
}