import 'package:flutter/foundation.dart';

// Debug-only logging. Plain debugPrint is NOT release-gated despite the
// name - it writes to the system log (logcat) unconditionally in every
// build, including release, and is retrievable by anyone with USB
// debugging access to the device - a meaningfully lower bar than root.
// Several call sites across this app logged repo paths and note titles
// this way. Use secureDebugLog everywhere instead: identical call
// signature, but it only ever prints in a debug build.
void secureDebugLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}