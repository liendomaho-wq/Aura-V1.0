import 'package:flutter_test/flutter_test.dart';
import 'package:aura_mobile_defens/inference/aura_host_policy.dart';

void main() {
  group('registrableDomain', () {
    test('reduce a eTLD+1 en dominios de dos niveles', () {
      expect(
        AuraHostPolicy.registrableDomain('pubmed.ncbi.nlm.nih.gov'),
        'nih.gov',
      );
      expect(
        AuraHostPolicy.registrableDomain('noticias.caracoltv.com'),
        'caracoltv.com',
      );
      expect(
        AuraHostPolicy.registrableDomain('api.banco.example.co.uk'),
        'example.co.uk',
      );
      expect(AuraHostPolicy.registrableDomain('a.b.com.ar'), 'b.com.ar');
      expect(
        AuraHostPolicy.registrableDomain('presidencia.gob.ve'),
        'presidencia.gob.ve',
      );
      expect(AuraHostPolicy.registrableDomain('example.com.'), 'example.com');
      expect(
        AuraHostPolicy.registrableDomain('WWW.Example.COM'),
        'example.com',
      );
    });

    test('no inventa un dominio cuando el host no es válido', () {
      expect(AuraHostPolicy.registrableDomain('localhost'), isNull);
      expect(AuraHostPolicy.registrableDomain('intranet'), isNull);
      expect(AuraHostPolicy.registrableDomain('192.168.1.1'), isNull);
      expect(AuraHostPolicy.registrableDomain('10.0.0.1'), isNull);
      expect(AuraHostPolicy.registrableDomain('-malo.example'), isNull);
      expect(AuraHostPolicy.registrableDomain('malo-.example'), isNull);
      expect(AuraHostPolicy.registrableDomain(''), isNull);
      expect(AuraHostPolicy.registrableDomain('${'a' * 260}.com'), isNull);
    });

    test('no colapsa sufijos privados como github.io', () {
      // Es mejor puntuar el host completo que atribuir el sitio a github.io.
      expect(
        AuraHostPolicy.registrableDomain('cuenta.github.io'),
        'cuenta.github.io',
      );
    });
  });

  group('band', () {
    test('sin señal solo cuando ambos puntajes son bajos', () {
      expect(
        AuraHostPolicy.band(hostScore: 0.1, registrableScore: 0.2),
        AuraRiskBand.clear,
      );
    });

    test('revisión cuando un solo puntaje supera el piso', () {
      expect(
        AuraHostPolicy.band(hostScore: 1, registrableScore: 0),
        AuraRiskBand.review,
      );
      expect(
        AuraHostPolicy.band(hostScore: 0, registrableScore: 0.4),
        AuraRiskBand.review,
      );
    });

    test('prioridad alta exige host y dominio registrable', () {
      expect(
        AuraHostPolicy.band(hostScore: 0.9, registrableScore: 0.7),
        AuraRiskBand.high,
      );
      expect(
        AuraHostPolicy.band(hostScore: 0.9, registrableScore: 0.64),
        AuraRiskBand.review,
      );
      expect(
        AuraHostPolicy.band(hostScore: 0.64, registrableScore: 0.9),
        AuraRiskBand.review,
      );
    });

    test('rechaza puntajes fuera de rango en lugar de recortarlos', () {
      expect(
        () => AuraHostPolicy.band(hostScore: -0.1, registrableScore: 0),
        throwsArgumentError,
      );
      expect(
        () => AuraHostPolicy.band(hostScore: 0, registrableScore: 1.1),
        throwsArgumentError,
      );
      expect(
        () => AuraHostPolicy.band(hostScore: double.nan, registrableScore: 0),
        throwsArgumentError,
      );
    });

    test('etiqueta legible para la interfaz', () {
      expect(AuraHostPolicy.label(AuraRiskBand.clear), 'sin señal');
      expect(AuraHostPolicy.label(AuraRiskBand.review), 'revisión');
      expect(AuraHostPolicy.label(AuraRiskBand.high), 'prioridad alta');
    });
  });
}
