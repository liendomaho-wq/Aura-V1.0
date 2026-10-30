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

    test('uses an authenticated v2 envelope and rejects tag tampering', () {
      final encrypted = AuraCryptoLayer.encryptModel(
        plaintext,
        key,
        iv: IV(Uint8List.fromList(List<int>.generate(16, (index) => index))),
      );
      expect(encrypted, startsWith('aura2:'));
      expect(AuraCryptoLayer.decryptModel(encrypted, key), plaintext);

      final lastNibble = encrypted.substring(encrypted.length - 1);
      final tampered = encrypted.substring(0, encrypted.length - 1) +
          (lastNibble == '0' ? '1' : '0');
      expect(
        () => AuraCryptoLayer.decryptModel(tampered, key),
        throwsA(isA<AuraCryptoException>()),
      );
    });

    test('rejects empty keys when encrypting or decrypting', () {
      expect(
        () => AuraCryptoLayer.encryptModel(plaintext, ''),
        throwsA(isA<AuraCryptoException>()),
      );
      expect(
        () => AuraCryptoLayer.decryptModel(
          List<String>.filled(32, '00').join(),
          '',
        ),
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
  group('AuraCryptoLayer signature verification', () {
    test('rejects empty, truncated, and out-of-range RSA signatures', () {
      final model = Uint8List.fromList(utf8.encode('{"version":"1.0.0"}'));

      expect(
        AuraCryptoLayer.verifyModelSignature(
          modelBytes: model,
          signatureBytes: Uint8List(0),
        ),
        isFalse,
      );
      expect(
        AuraCryptoLayer.verifyModelSignature(
          modelBytes: model,
          signatureBytes: Uint8List(32),
        ),
        isFalse,
      );
      expect(
        AuraCryptoLayer.verifyModelSignature(
          modelBytes: model,
          signatureBytes: Uint8List.fromList(List<int>.filled(256, 0xff)),
        ),
        isFalse,
      );
    });

    test('fails closed when the model bytes are empty', () {
      expect(
        AuraCryptoLayer.verifySignature(
          Uint8List(0),
          Uint8List(256),
        ),
        isFalse,
      );
    });
  });

}
