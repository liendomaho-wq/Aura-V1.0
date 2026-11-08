import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _MemsetNative = Pointer<Void> Function(Pointer<Void>, Int32, Size);
typedef _MemsetDart = Pointer<Void> Function(Pointer<Void>, int, int);

/// Runs synchronous operations on a native copy of sensitive bytes.
///
/// The Dart source buffer is not modified, and Dart/VM copies or immutable
/// strings created by `action` cannot be erased by this class. Keep secrets in
/// byte buffers and do not retain or free `securePtr` outside `action`.
abstract final class AuraSecureMem {
  static late final _MemsetDart _memset;
  static bool _isInitialized = false;

  /// Loads libc's memset once, preferring symbols already loaded in the process.
  static void init() {
    if (_isInitialized) return;

    try {
      final library = DynamicLibrary.process();
      final memset = library
          .lookup<NativeFunction<_MemsetNative>>('memset')
          .asFunction<_MemsetDart>();
      _memset = memset;
      _isInitialized = true;
      return;
    } on Object catch (processError) {
      try {
        final library = DynamicLibrary.open('libc.so');
        final memset = library
            .lookup<NativeFunction<_MemsetNative>>('memset')
            .asFunction<_MemsetDart>();
        _memset = memset;
        _isInitialized = true;
      } on Object catch (libraryError) {
        throw UnsupportedError(
          'No se pudo mapear memset de libc desde el proceso '
          '($processError) ni desde libc.so ($libraryError).',
        );
      }
    }
  }

  /// Calls [action] with a native copy and clears that allocation before
  /// freeing it, whether [action] returns normally or throws.
  ///
  /// [action] must be synchronous and must not retain or free its pointer.
  static T processSecureData<T>({
    required Uint8List rawData,
    required T Function(Pointer<Uint8> securePtr, int length) action,
  }) {
    if (!_isInitialized) init();

    final length = rawData.length;
    // malloc(0) may return nullptr; allocate one byte for an empty payload.
    final allocationLength = length == 0 ? 1 : length;
    final secureBuffer = malloc<Uint8>(allocationLength);
    if (secureBuffer == nullptr) {
      throw StateError('No se pudo asignar el buffer nativo seguro.');
    }

    try {
      for (var index = 0; index < length; index++) {
        secureBuffer[index] = rawData[index];
      }

      final result = action(secureBuffer, length);
      if (result is Future) {
        throw ArgumentError(
          'La operación sobre el buffer nativo debe ser síncrona.',
        );
      }
      return result;
    } finally {
      try {
        _memset(secureBuffer.cast<Void>(), 0, allocationLength);
      } finally {
        malloc.free(secureBuffer);
      }
    }
  }
}
