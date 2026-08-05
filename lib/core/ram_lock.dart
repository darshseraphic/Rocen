import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef _MlockNative = Int32 Function(Pointer<Void> addr, IntPtr len);
typedef _MlockDart = int Function(Pointer<Void> addr, int len);

class _Libc {
  static final DynamicLibrary _lib = DynamicLibrary.process();

  static final _MlockDart mlock = _lib.lookupFunction<_MlockNative, _MlockDart>('mlock');
  static final _MlockDart munlock = _lib.lookupFunction<_MlockNative, _MlockDart>('munlock');
}

// A byte buffer allocated on the native heap (outside Dart's GC, so it can
// never be copied/moved by a GC pass) and best-effort locked into physical
// RAM via mlock() so the OS can't page it to disk/swap while it's held.
//
// Lifecycle is always allocate -> use -> zero -> unlock -> free, all within
// a single function call via release(). Nothing is ever kept pinned at rest.
//
// mlock() can legitimately fail on real devices (RLIMIT_MEMLOCK caps on
// stock ROMs, OEM restrictions). That is never treated as an error: the
// buffer is still allocated and usable, isLocked just reports false, and
// zero()/release() still run unconditionally. Crypto correctness never
// depends on the lock having succeeded.
class RamLockedBytes {
  final Pointer<Uint8> _pointer;
  final Uint8List bytes;
  final int length;
  bool _locked = false;
  bool _freed = false;

  RamLockedBytes._(this._pointer, this.bytes, this.length);

  factory RamLockedBytes(int length) {
    final Pointer<Uint8> ptr = malloc.allocate<Uint8>(length);
    final buffer = RamLockedBytes._(ptr, ptr.asTypedList(length), length);
    buffer._tryLock();
    return buffer;
  }

  void _tryLock() {
    try {
      final int result = _Libc.mlock(_pointer.cast<Void>(), length);
      _locked = result == 0;
      if (!_locked) {
        print('[ram_lock] mlock unavailable on this device - continuing without RAM pinning');
      }
    } catch (e) {
      _locked = false;
      print('[ram_lock] mlock call failed - continuing without RAM pinning: $e');
    }
  }

  bool get isLocked => _locked;

  void copyFrom(List<int> source) {
    bytes.setAll(0, source);
  }

  void zero() {
    if (_freed) return;
    for (int i = 0; i < length; i++) {
      bytes[i] = 0;
    }
  }

  // Zeroes, unlocks (best-effort), and frees the native allocation. Safe to
  // call more than once. Always call this in a finally block.
  void release() {
    if (_freed) return;
    zero();
    if (_locked) {
      try {
        _Libc.munlock(_pointer.cast<Void>(), length);
      } catch (_) {
        // Nothing further to do - memory is about to be freed regardless.
      }
    }
    malloc.free(_pointer);
    _freed = true;
  }
}