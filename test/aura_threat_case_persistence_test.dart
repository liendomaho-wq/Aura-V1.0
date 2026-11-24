import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_mobile_defens/secure_vault.dart';
import 'package:aura_mobile_defens/security/aura_finding.dart';
import 'package:aura_mobile_defens/security/aura_threat_case.dart';

AuraThreatCase _case({
  String id = 'network:evil.example:com.example.app',
  int observedAt = 1700000000000,
  int firstSeenAt = 1699999999000,
  int updatedAt = 1700000000000,
  AuraThreatDisposition disposition = AuraThreatDisposition.open,
  String? statusDetail,
}) => AuraThreatCase(
  id: id,
  category: AuraFindingCategory.networkActivity,
  severity: AuraFindingSeverity.high,
  state: AuraThreatCaseState.dnsContained,
  title: 'Navegador intentó conectarse a evil.example',
  summary: 'Se bloquearon 3 conexiones al dominio evil.example.',
  evidence: const <String>[
    'Dominio bloqueado: evil.example',
    'Paquete: com.example.app',
  ],
  limitations: const <String>['El bloqueo DNS no cubre QUIC ni IP directa.'],
  recommendedAction: 'Revisa la app de origen en Ajustes.',
  action: AuraThreatCaseAction.reviewApp,
  observedAt: observedAt,
  firstSeenAt: firstSeenAt,
  domain: 'evil.example',
  packageName: 'com.example.app',
  appName: 'Navegador',
  signalCount: 3,
  disposition: disposition,
  statusDetail: statusDetail,
  updatedAt: updatedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('el tope del modelo coincide con el del almacén cifrado', () {
    expect(
      AuraThreatCaseBuilder.maxStoredCases,
      AuraSecureVault.maxThreatCases,
    );
  });

  test(
    'un caso se serializa y se reconstruye sin perder evidencia ni estado',
    () {
      final original = _case(
        disposition: AuraThreatDisposition.inReview,
        statusDetail: 'Evidencia abierta por el usuario.',
      );
      final restored = AuraThreatCase.fromMap(original.toMap());

      expect(restored, isNotNull);
      expect(restored!.id, original.id);
      expect(restored.title, original.title);
      expect(restored.domain, 'evil.example');
      expect(restored.packageName, 'com.example.app');
      expect(restored.evidence, original.evidence);
      expect(restored.limitations, original.limitations);
      expect(restored.disposition, AuraThreatDisposition.inReview);
      expect(restored.statusDetail, 'Evidencia abierta por el usuario.');
      expect(restored.statusChangedAt, original.statusChangedAt);
      expect(restored.firstSeenAt, original.firstSeenAt);
    },
  );

  test('un registro con esquema o tipos inválidos no se acepta', () {
    final map = _case().toMap();
    expect(
      AuraThreatCase.fromMap(<String, dynamic>{...map, 'schema': 3}),
      isNull,
    );
    expect(
      AuraThreatCase.fromMap(<String, dynamic>{
        ...map,
        'evidence': <Object>[42],
      }),
      isNull,
    );
    expect(
      AuraThreatCase.fromMap(<String, dynamic>{
        ...map,
        'domain': 'no es dominio',
      }),
      isNull,
    );
  });

  test(
    'la fusión conserva la decisión del usuario y la primera observación',
    () {
      final now = 1700000100000;
      final stored = _case(
        observedAt: now - 1000,
        firstSeenAt: 1699999900000,
        updatedAt: now - 1000,
        disposition: AuraThreatDisposition.dismissed,
      );
      final live = _case(
        observedAt: now,
        firstSeenAt: now - 500,
        updatedAt: now,
      );

      final merged = AuraThreatCaseBuilder.merge(
        live: <AuraThreatCase>[live],
        stored: <AuraThreatCase>[stored],
        now: now,
      );

      expect(merged, hasLength(1));
      expect(merged.single.disposition, AuraThreatDisposition.dismissed);
      expect(merged.single.isDismissed, isTrue);
      expect(merged.single.firstSeenAt, stored.firstSeenAt);
      expect(merged.single.updatedAt, now);
    },
  );

  test('la fusión puede conservar más de 40 casos para el almacén', () {
    final now = 1700000100000;
    final stored = <AuraThreatCase>[
      for (var index = 0; index < 60; index++)
        _case(
          id: 'network:caso$index.example:com.example.app',
          observedAt: now - index,
          firstSeenAt: now - index,
          updatedAt: now - index,
        ),
    ];

    expect(
      AuraThreatCaseBuilder.merge(
        live: const <AuraThreatCase>[],
        stored: stored,
        now: now,
      ),
      hasLength(AuraThreatCaseBuilder.maxCases),
    );
    expect(
      AuraThreatCaseBuilder.merge(
        live: const <AuraThreatCase>[],
        stored: stored,
        now: now,
        limit: AuraThreatCaseBuilder.maxStoredCases,
      ),
      hasLength(stored.length),
    );
  });

  test('un caso mitigado vuelve a revisión si aparece actividad nueva', () {
    final now = 1700000100000;
    final stored = _case(
      observedAt: now - 5000,
      updatedAt: now - 5000,
      disposition: AuraThreatDisposition.mitigated,
      statusDetail: 'Bloqueo DNS activo; revisión confirmada por el usuario.',
    );
    final live = _case(observedAt: now, updatedAt: now);

    final merged = AuraThreatCaseBuilder.merge(
      live: <AuraThreatCase>[live],
      stored: <AuraThreatCase>[stored],
      now: now,
    );

    expect(merged.single.disposition, AuraThreatDisposition.inReview);
    expect(merged.single.statusDetail, contains('Nueva actividad'));
    expect(merged.single.statusChangedAt, now);
  });

  test('un registro del esquema 1 se migra sin perder su decisión', () {
    final oldMap = <String, dynamic>{
      ..._case(disposition: AuraThreatDisposition.dismissed).toMap(),
      'schema': 1,
    }..remove('status_changed_at');
    final restored = AuraThreatCase.fromMap(oldMap);

    expect(restored, isNotNull);
    expect(restored!.disposition, AuraThreatDisposition.dismissed);
    expect(restored.statusChangedAt, restored.updatedAt);
    expect(restored.statusDetail, isNull);
  });

  test('el playbook de red usa la contención real y no promete eliminación', () {
    final playbook = _case().playbook;

    expect(playbook, isNotEmpty);
    expect(playbook.first.detail, contains('QUIC'));
    expect(
      playbook.any((step) => step.action == AuraThreatCaseAction.reviewApp),
      isTrue,
    );
    expect(
      playbook.any((step) => step.detail.contains('desinstálala')),
      isTrue,
    );
  });

  test('la fusión descarta casos fuera de la retención', () {
    final now = 1700000100000;
    final expired = _case(
      observedAt: now - const Duration(days: 31).inMilliseconds,
      firstSeenAt: now - const Duration(days: 31).inMilliseconds,
      updatedAt: now - const Duration(days: 31).inMilliseconds,
    );

    final merged = AuraThreatCaseBuilder.merge(
      live: const <AuraThreatCase>[],
      stored: <AuraThreatCase>[expired],
      now: now,
    );

    expect(merged, isEmpty);
  });

  test(
    'el almacén guarda y recupera casos, y rechaza un payload corrupto',
    () async {
      final vault = AuraSecureVault();
      await vault.saveThreatCases(<Map<String, dynamic>>[_case().toMap()]);
      final restored = await vault.getThreatCases();
      expect(restored, hasLength(1));
      expect(restored.single['id'], 'network:evil.example:com.example.app');

      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'aura_threat_cases_v1': '{"no":"es una lista"}',
      });
      await expectLater(
        AuraSecureVault().getThreatCases(),
        throwsFormatException,
      );
    },
  );
}
