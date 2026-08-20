import 'package:flutter/foundation.dart';

void secureDebugLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
