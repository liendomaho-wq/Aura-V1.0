import 'dart:convert';
import 'dart:typed_data';

import 'package:aura_mobile_defens/crypto/aura_crypto_layer.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuraCryptoLayer model encryption', () {
    const key = 'test-only-model-master-key';
    const plaintext = '{"version":"1.0.0","weights":[]}';

    test('round-trips a JSON model with a deterministic test IV', () {
      final encrypted = AuraCryptoLayer.encryptModel(
        plaintext,
        key,
        iv: IV(Uint8List.fromList(List<int>.generate(16, (index) => index))),
      );

      expect(AuraCryptoLayer.decryptModel(encrypted, key), plaintext);
    });

    test('rejects empty keys when encrypting or decrypting', () {
      expect(
        () => AuraCryptoLayer.encryptModel(plaintext, ''),
        throwsA(isA<AuraCryptoException>()),
      );
      expect(
        () => AuraCryptoLayer.decryptModel('00' * 32, ''),
        throwsA(isA<AuraCryptoException>()),
      );
    });

    test('rejects non-object JSON when encrypting a model', () {
      expect(
        () => AuraCryptoLayer.encryptModel('"not an object"', key),
        throwsA(isA<AuraCryptoException>()),
      );
    });

    test('rejects malformed hex and truncated AES payloads', () {
      expect(
        () => AuraCryptoLayer.decryptModel('not-hex', key),
        throwsA(isA<AuraCryptoException>()),
      );
      expect(
        () => AuraCryptoLayer.decryptModel('001122', key),
        throwsA(isA<AuraCryptoException>()),
      );
    });

    test('HKDF rejects empty input key material and invalid output length', () {
      expect(
        () => AuraCryptoLayer.deriveKeyHKDF(
          ikm: Uint8List(0),
          salt: Uint8List.fromList(utf8.encode('salt')),
          info: Uint8List.fromList(utf8.encode('test')),
        ),
        throwsA(isA<AuraCryptoException>()),
      );
      expect(
        () => AuraCryptoLayer.deriveKeyHKDF(
          ikm: Uint8List.fromList(utf8.encode('key')),
          salt: Uint8List.fromList(utf8.encode('salt')),
          info: Uint8List.fromList(utf8.encode('test')),
          length: 0,
        ),
        throwsA(isA<AuraCryptoException>()),
      );
    });
  });
}
