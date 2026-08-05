import 'dart:typed_data';
import 'ram_lock.dart';

// Same public surface as before (bytes / length / zero()), so every existing
// call site keeps working unchanged. Internally now backed by RamLockedBytes:
// zero() zeroes AND unlocks/frees the native allocation in one call, matching
// how every call site already uses it inside a try/finally.
class SecureBytes {
  final RamLockedBytes _locked;
  bool _released = false;

  SecureBytes(List<int> initialData) : _locked = RamLockedBytes(initialData.length) {
    _locked.copyFrom(initialData);
  }

  Uint8List get bytes {
    if (_released) {
      throw StateError('SecureBytes was already zeroed - this buffer is no longer usable.');
    }
    return _locked.bytes;
  }

  int get length => _locked.length;

  // Best-effort - true only if the OS actually honored the RAM-pin request.
  bool get isRamLocked => _locked.isLocked;

  void zero() {
    if (_released) return;
    _locked.release();
    _released = true;
  }
}

void zeroBytes(Uint8List data) {
  for (int i = 0; i < data.length; i++) {
    data[i] = 0;
  }
}