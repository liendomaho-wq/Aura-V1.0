import '../services/aura_threat_correlator.dart';
import 'aura_finding.dart';

class AuraFindingsEngine {
  AuraFindingsEngine({int Function()? clock}) : _clock = clock ?? _systemNow;

  final int Function() _clock;

  static int _systemNow() => DateTime.now().millisecondsSinceEpoch;

  static const List<String> _deviceLimitations = <String>[
    'Las señales nativas son heurísticas y pueden producir falsos positivos y falsos negativos.',
    'Android limita la visibilidad de procesos, paquetes y estados de otras aplicaciones.',
    'Un resultado sin indicadores no certifica que el dispositivo esté libre de amenazas.',
  ];

  static const List<String> _appLimitations = <String>[
    'El análisis es estático: no ejecuta, descompila ni vigila otras aplicaciones.',
    'Los permisos concedidos y accesos especiales indican capacidad, no abuso demostrado.',
    'La ofuscación, la procedencia y una firma no verificable no demuestran malware por sí solas.',
    'El inventario depende de lo que Android y los permisos de consulta exponen a esta app.',
    'No sustituye Play Protect ni una revisión manual del usuario.',
  ];

  static const List<String> _networkLimitations = <String>[
    'La correlación se basa en eventos del túnel local y umbrales deterministas; no demuestra intención maliciosa.',
    'La cobertura depende de que la VPN esté activa y de que el tráfico sea observable.',
    'QUIC, ECH y DNS cifrado personalizado pueden reducir la visibilidad de la sesión.',
  ];

  AuraFindingsReport evaluate({
    Map<String, dynamic>? deviceAudit,
    Map<String, dynamic>? appScan,
    List<AuraThreatAlert> threatAlerts = const <AuraThreatAlert>[],
  }) {
    final now = _clock();
    final findings = <AuraFinding>[
      ..._deviceFindings(deviceAudit, now),
      ..._appFindings(appScan, now),
      ..._networkFindings(threatAlerts, now),
    ];
    findings.sort(_compareFindings);
    return AuraFindingsReport(
      findings: List<AuraFinding>.unmodifiable(findings),
      deviceCoverage: _deviceCoverage(deviceAudit),
      appCoverage: _appCoverage(appScan),
      networkAlertCount: threatAlerts.length,
      generatedAt: now,
    );
  }

  int _compareFindings(AuraFinding left, AuraFinding right) {
    final severity = right.severity.index.compareTo(left.severity.index);
    if (severity != 0) return severity;
    final confidence = right.confidence.index.compareTo(left.confidence.index);
    if (confidence != 0) return confidence;
    final observed = right.observedAt.compareTo(left.observedAt);
    if (observed != 0) return observed;
    return left.id.compareTo(right.id);
  }

  AuraFindingCoverage _deviceCoverage(Map<String, dynamic>? audit) {
    if (audit == null) return AuraFindingCoverage.notScanned;
    if (!_isValidDeviceAudit(audit)) {
      return AuraFindingCoverage.incomplete;
    }
    final errors = _strings(
      audit['check_errors'] ?? audit['environmentCheckErrors'],
    );
    return errors.isEmpty
        ? AuraFindingCoverage.complete
        : AuraFindingCoverage.partial;
  }

  AuraFindingCoverage _appCoverage(Map<String, dynamic>? scan) {
    if (scan == null) return AuraFindingCoverage.notScanned;
    return _isValidAppScan(scan)
        ? AuraFindingCoverage.complete
        : AuraFindingCoverage.incomplete;
  }

  bool _isValidAppScan(Map<String, dynamic> scan) {
    if (scan['ok'] != true) return false;
    for (final key in const <String>[
      'applications',
      'special_access',
      'suspicious_apps',
      'signature_issues',
      'obfuscated_apps',
    ]) {
      if (scan[key] is! List) return false;
    }
    return true;
  }

  bool _isValidDeviceAudit(Map<String, dynamic> audit) {
    return audit['ok'] == true &&
        audit['is_rooted'] is bool &&
        audit['is_emulator'] is bool &&
        audit['is_instrumented'] is bool &&
        audit['is_debugger_connected'] is bool &&
        audit['screen_overlay_detected'] is bool &&
        audit['untrusted_accessibility_packages'] is List;
  }

  List<AuraFinding> _deviceFindings(Map<String, dynamic>? audit, int now) {
    if (audit == null) return const <AuraFinding>[];
    final observedAt = _observedAt(audit['timestamp'], now);
    if (!_isValidDeviceAudit(audit)) {
      return <AuraFinding>[
        _incompleteAuditFinding(
          observedAt: observedAt,
          error: audit['error'] is String
              ? audit['error'] as String
              : 'invalid_device_audit_report',
        ),
      ];
    }

    final findings = <AuraFinding>[];
    final indicators = _strings(audit['indicators']);
    final errors = _strings(
      audit['check_errors'] ?? audit['environmentCheckErrors'],
    );
    final rootIndicators = _withFallback(
      _strings(audit['root_indicators']),
      _filterPrefixes(indicators, const <String>[
        'su_binary',
        'magisk_path',
        'kernelsu_path',
        'root_manager_package',
        'build_tags_test_keys',
        'su_command_available',
      ]),
    );
    final emulatorIndicators = _withFallback(
      _strings(audit['emulator_indicators']),
      _filterPrefixes(indicators, const <String>['emulator_']),
    );
    final instrumentationIndicators = _withFallback(
      _strings(audit['instrumentation_indicators']),
      _filterPrefixes(indicators, const <String>[
        'library:',
        'frida_port:',
        'package:',
        'process:',
      ]),
    );
    final overlayIndicators = _withFallback(
      _strings(audit['screen_overlay_indicators']),
      _filterPrefixes(indicators, const <String>[
        'obscured_touch_event',
        'overlay_permission_granted:',
      ]),
    );
    final rooted = audit['is_rooted'] == true;
    final rootConfidence = _positiveNumber(audit['root_confidence']);

    if (rooted || rootIndicators.isNotEmpty) {
      final confidence = _rootConfidence(rootConfidence, rootIndicators);
      findings.add(
        AuraFinding(
          id: 'device-root-indicators',
          category: AuraFindingCategory.devicePosture,
          severity: rooted ? AuraFindingSeverity.high : AuraFindingSeverity.low,
          confidence: confidence,
          status: AuraFindingStatus.observed,
          observedAt: observedAt,
          title: rooted
              ? 'Indicadores de root o superusuario'
              : 'Señal débil de entorno modificado',
          summary: rooted
              ? 'Android observó indicadores de root o superusuario. Es una señal de postura que requiere revisión; no demuestra por sí sola que una aplicación sea maliciosa.'
              : 'Android observó una señal débil relacionada con privilegios o build del sistema. Puede ser legítima según la ROM; requiere contexto.',
          subject: 'Dispositivo Android',
          scope:
              'Rutas su, Magisk/KernelSU, paquetes gestores, Build.TAGS y ejecución de su visibles para la app.',
          evidence: <String>[
            if (rootIndicators.isNotEmpty)
              'Indicadores: ${rootIndicators.join(', ')}',
            if (rootConfidence != null)
              'Confianza heurística de root: ${rootConfidence.toStringAsFixed(0)}/100',
            if (rootIndicators.isEmpty)
              'Android marcó isRooted=$rooted sin una lista específica de indicadores.',
          ],
          limitations: <String>[
            ..._deviceLimitations,
            'Root o Shizuku puede ocultarse a las comprobaciones de una app normal.',
            'Tener root no implica malware; modifica el modelo de confianza del dispositivo.',
          ],
          recommendedAction:
              'Revisa si reconoces el root o el gestor instalado. Si no lo instalaste, investiga el origen y considera restaurar el sistema. Aura no puede desrootear ni modificar el sistema automáticamente.',
        ),
      );
    }

    if (audit['is_emulator'] == true) {
      final emulatorConfidence = _positiveNumber(audit['emulator_confidence']);
      findings.add(
        AuraFinding(
          id: 'device-emulator',
          category: AuraFindingCategory.devicePosture,
          severity: AuraFindingSeverity.medium,
          confidence: AuraFindingConfidence.medium,
          status: AuraFindingStatus.observed,
          observedAt: observedAt,
          title: 'Entorno Android emulado',
          summary:
              'Las comprobaciones de la app apuntan a un emulador o a un entorno de virtualización. Puede ser un uso legítimo, pero cambia las garantías del análisis.',
          subject: 'Dispositivo Android',
          scope:
              'Huella, modelo, fabricante, hardware, board y ABI del sistema.',
          evidence: <String>[
            if (emulatorIndicators.isNotEmpty)
              'Indicadores: ${emulatorIndicators.join(', ')}',
            if (emulatorConfidence != null)
              'Confianza heurística de emulación: ${emulatorConfidence.toStringAsFixed(0)}/100',
          ],
          limitations: <String>[
            ..._deviceLimitations,
            'Un emulador puede ser intencional para pruebas o desarrollo.',
          ],
          recommendedAction:
              'Si no esperabas un emulador, revisa el dispositivo o la ROM. No ejecutes operaciones sensibles en un entorno que no controlas.',
        ),
      );
    }

    if (audit['is_instrumented'] == true ||
        instrumentationIndicators.isNotEmpty) {
      findings.add(
        AuraFinding(
          id: 'device-instrumentation',
          category: AuraFindingCategory.devicePosture,
          severity: AuraFindingSeverity.high,
          confidence: _instrumentationConfidence(instrumentationIndicators),
          status: AuraFindingStatus.observed,
          observedAt: observedAt,
          title: 'Posible instrumentación o hooking',
          summary:
              'Android o la app observaron bibliotecas, puertos o procesos asociados con instrumentación dinámica. Es una señal de alto riesgo para el entorno de la app; no identifica por sí sola al responsable.',
          subject: 'Dispositivo Android',
          scope:
              'Bibliotecas cargadas, puertos locales, paquetes y procesos visibles para la app.',
          evidence: <String>[
            if (instrumentationIndicators.isNotEmpty)
              'Indicadores: ${instrumentationIndicators.join(', ')}',
            if (instrumentationIndicators.isEmpty)
              'Android marcó isInstrumented=true sin una lista específica de indicadores.',
          ],
          limitations: <String>[
            ..._deviceLimitations,
            'Herramientas de desarrollo o pruebas pueden activar señales similares.',
          ],
          recommendedAction:
              'Si no estás depurando la app, reinicia el dispositivo y revisa si hay herramientas de instrumentación instaladas o activas. Aura no elimina procesos ni paquetes automáticamente.',
        ),
      );
    }

    if (audit['is_debugger_connected'] == true) {
      findings.add(
        AuraFinding(
          id: 'device-debugger',
          category: AuraFindingCategory.devicePosture,
          severity: AuraFindingSeverity.high,
          confidence: AuraFindingConfidence.high,
          status: AuraFindingStatus.observed,
          observedAt: observedAt,
          title: 'Depurador conectado',
          summary:
              'Android reportó un depurador adjunto al proceso. Esto permite inspeccionar o modificar la ejecución y reduce las garantías de integridad.',
          subject: 'Proceso de Aura',
          scope:
              'Estado de depuración expuesto por Android en el proceso actual.',
          evidence: const <String>[
            'Debug.isDebuggerConnected() devolvió true.',
          ],
          limitations: <String>[
            ..._deviceLimitations,
            'Una build de depuración puede conectarse a un depurador de forma intencional.',
          ],
          recommendedAction:
              'Desconecta el depurador y usa una build de producción firmada para operaciones sensibles. Aura no puede expulsar al depurador.',
        ),
      );
    }

    if (audit['screen_overlay_detected'] == true ||
        overlayIndicators.isNotEmpty) {
      findings.add(
        AuraFinding(
          id: 'device-screen-overlay',
          category: AuraFindingCategory.devicePosture,
          severity: AuraFindingSeverity.medium,
          confidence: AuraFindingConfidence.medium,
          status: AuraFindingStatus.observed,
          observedAt: observedAt,
          title: 'Superposición de pantalla detectada',
          summary:
              'Se observaron indicadores de overlays o eventos de toque oscurecidos. Una superposición puede interferir con la interfaz; también puede ser una función legítima.',
          subject: 'Pantalla del dispositivo',
          scope:
              'Permisos de overlay accesibles y eventos de toque oscurecidos reportados por Android.',
          evidence: <String>[
            if (overlayIndicators.isNotEmpty)
              'Indicadores: ${overlayIndicators.join(', ')}',
            if (overlayIndicators.isEmpty)
              'Android marcó isScreenOverlayDetected=true.',
          ],
          limitations: <String>[
            ..._deviceLimitations,
            'Los overlays son heurísticos y pueden pertenecer a apps de accesibilidad, burbujas o grabación.',
          ],
          recommendedAction:
              'Revisa Ajustes > Aplicaciones > Acceso especial > Superponerse a otras apps y desactiva lo que no reconozcas. Aura no cambia ese permiso.',
        ),
      );
    }

    final accessibility = _strings(audit['untrusted_accessibility_packages']);
    if (accessibility.isNotEmpty) {
      findings.add(
        AuraFinding(
          id: 'device-accessibility-services',
          category: AuraFindingCategory.devicePosture,
          severity: AuraFindingSeverity.medium,
          confidence: AuraFindingConfidence.high,
          status: AuraFindingStatus.observed,
          observedAt: observedAt,
          title: 'Servicios de accesibilidad no reconocidos',
          summary:
              'Hay servicios de accesibilidad habilitados que no están en la allowlist local. Pueden leer la pantalla y realizar acciones; no son prueba de abuso.',
          subject: 'Servicios de accesibilidad de Android',
          scope:
              'Servicios de accesibilidad habilitados expuestos por AccessibilityManager.',
          evidence: <String>['Paquetes: ${accessibility.join(', ')}'],
          limitations: <String>[
            ..._deviceLimitations,
            'La allowlist local es limitada; una app legítima puede no estar incluida.',
          ],
          recommendedAction:
              'Revisa Ajustes > Accesibilidad y desactiva los servicios que no reconozcas. Aura no modifica la configuración de accesibilidad.',
        ),
      );
    }

    if (errors.isNotEmpty) {
      findings.add(
        AuraFinding(
          id: 'device-audit-partial',
          category: AuraFindingCategory.devicePosture,
          severity: AuraFindingSeverity.low,
          confidence: AuraFindingConfidence.high,
          status: AuraFindingStatus.unresolved,
          observedAt: observedAt,
          title: 'Auditoría de postura incompleta',
          summary:
              'Algunas comprobaciones nativas no pudieron completarse. Los resultados disponibles no cubren toda la superficie declarada.',
          subject: 'Dispositivo Android',
          scope: 'Comprobaciones de postura ejecutadas por la app.',
          evidence: errors,
          limitations: const <String>[
            'Los datos ausentes no equivalen a ausencia de riesgo.',
            'No interpretes una auditoría parcial como dispositivo limpio.',
          ],
          recommendedAction:
              'Repite la auditoría y revisa los permisos de la app. Si el error persiste, contrasta el estado con Ajustes de Android y una herramienta independiente.',
        ),
      );
    }

    return findings;
  }

  AuraFinding _incompleteAuditFinding({
    required int observedAt,
    required String error,
  }) {
    return AuraFinding(
      id: 'device-audit-incomplete',
      category: AuraFindingCategory.devicePosture,
      severity: AuraFindingSeverity.low,
      confidence: AuraFindingConfidence.high,
      status: AuraFindingStatus.unresolved,
      observedAt: observedAt,
      title: 'Auditoría de postura no verificable',
      summary:
          'Android no devolvió un informe de postura válido. No se interpretará como un dispositivo limpio ni como una amenaza confirmada.',
      subject: 'Dispositivo Android',
      scope:
          'Auditoría de root, emulación, instrumentación, overlays y accesibilidad.',
      evidence: <String>['Código de error: $error'],
      limitations: const <String>[
        'La ausencia de un informe válido impide concluir sobre la postura.',
        'Esto no demuestra que exista malware ni que el dispositivo esté libre de él.',
      ],
      recommendedAction:
          'Reintenta la auditoría. Si vuelve a fallar, revisa la instalación y los permisos de Aura; no asumas que el dispositivo está limpio.',
    );
  }

  List<AuraFinding> _appFindings(Map<String, dynamic>? scan, int now) {
    if (scan == null) return const <AuraFinding>[];
    final observedAt = _observedAt(scan['timestamp'], now);
    if (!_isValidAppScan(scan)) {
      return <AuraFinding>[
        AuraFinding(
          id: 'app-scan-incomplete',
          category: AuraFindingCategory.installedApps,
          severity: AuraFindingSeverity.low,
          confidence: AuraFindingConfidence.high,
          status: AuraFindingStatus.unresolved,
          observedAt: observedAt,
          title: 'Escaneo de aplicaciones no verificable',
          summary:
              'Android no devolvió un informe de aplicaciones válido o coherente. No se interpretará como cero aplicaciones ni cero riesgos.',
          subject: 'Inventario de aplicaciones',
          scope:
              'Servicios sensibles, permisos, firmas, procedencia y AppOps accesibles.',
          evidence: <String>[
            'Código de error: ${scan['error'] is String ? scan['error'] : 'invalid_scan_report'}',
          ],
          limitations: const <String>[
            'Un informe inválido no permite evaluar el inventario.',
            'Esto no demuestra que exista malware ni que el dispositivo esté libre de él.',
          ],
          recommendedAction:
              'Reintenta el escaneo. Si vuelve a fallar, revisa la instalación y los permisos de Aura; no asumas que no hay riesgos.',
        ),
      ];
    }

    final findings = <AuraFinding>[];
    final apps = <String, _AppSignals>{};

    for (final app in _maps(scan['suspicious_apps'])) {
      final permissions = _strings(app['high_risk_permissions']);
      final mediumPermissions = _strings(app['medium_risk_permissions']);
      _addAppSignal(
        apps,
        packageName: app['package_name'],
        appName: app['app_name'],
        severity: AuraFindingSeverity.medium,
        confidence: AuraFindingConfidence.medium,
        evidence: <String>[
          if (permissions.isNotEmpty)
            'Permisos de alto riesgo concedidos: ${permissions.join(', ')}',
          if (mediumPermissions.isNotEmpty)
            'Permisos de riesgo medio solicitados: ${mediumPermissions.join(', ')}',
          if (app['target_sdk'] is num) 'Target SDK: ${app['target_sdk']}',
          if (permissions.isEmpty && mediumPermissions.isEmpty)
            'Combinación de permisos de alto riesgo reportada por el escáner.',
        ],
        limitations: const <String>[
          'Una combinación de permisos concede capacidad; no demuestra que se hayan usado para abusar.',
        ],
      );
    }

    for (final app in _maps(scan['signature_issues'])) {
      final problems = _strings(app['problems']);
      _addAppSignal(
        apps,
        packageName: app['package_name'],
        appName: app['app_name'],
        severity: AuraFindingSeverity.low,
        confidence: AuraFindingConfidence.high,
        evidence: <String>[
          if (problems.isNotEmpty)
            'Firma no verificable: ${problems.join(', ')}',
          if (app['signature_count'] is num)
            'Firmantes observados: ${app['signature_count']}',
          if (problems.isEmpty) 'Metadatos de firma no verificables.',
        ],
        limitations: const <String>[
          'La ausencia de metadatos de firma impide verificar la identidad criptográfica de la app; no prueba que sea maliciosa.',
        ],
      );
    }

    for (final app in _maps(scan['obfuscated_apps'])) {
      final reasons = _strings(app['reasons']);
      _addAppSignal(
        apps,
        packageName: app['package_name'],
        appName: app['app_name'],
        severity: AuraFindingSeverity.low,
        confidence: AuraFindingConfidence.low,
        evidence: <String>[
          if (app['dex_entropy'] is num)
            'Entropía DEX máxima: ${(app['dex_entropy'] as num).toStringAsFixed(2)}',
          if (app['obfuscated_identifier_ratio'] is num)
            'Proporción de identificadores ofuscados: ${(app['obfuscated_identifier_ratio'] as num).toStringAsFixed(2)}',
          if (app['analyzed_dex_files'] is num)
            'Archivos DEX analizados: ${app['analyzed_dex_files']}',
          if (reasons.isNotEmpty) 'Motivos: ${reasons.join(', ')}',
          if (app['dex_entropy'] is! num &&
              app['obfuscated_identifier_ratio'] is! num &&
              reasons.isEmpty)
            'Indicadores de ofuscación reportados por el escáner.',
        ],
        limitations: const <String>[
          'La ofuscación es habitual en apps comerciales y puede producir falsos positivos.',
        ],
      );
    }

    for (final access in _maps(scan['special_access'])) {
      if (access['state'] != 'ACTIVE') continue;
      final accessName = access['access'];
      _addAppSignal(
        apps,
        packageName: access['package_name'],
        appName: access['app_name'],
        severity: AuraFindingSeverity.medium,
        confidence: AuraFindingConfidence.high,
        evidence: <String>[
          'Acceso especial activo: ${accessName is String ? accessName : 'desconocido'}'
              '${access['mode'] is num ? ' (modo ${access['mode']})' : ''}',
        ],
        limitations: const <String>[
          'AppOps MODE_ALLOWED confirma el acceso, no el uso indebido.',
        ],
      );
    }

    for (final app in apps.values) {
      if (app.signalCount == 0) continue;
      final severity =
          AuraFindingSeverity.values[app.severityRank
              .clamp(0, AuraFindingSeverity.values.length - 1)
              .toInt()];
      final confidence =
          AuraFindingConfidence.values[app.confidenceRank
              .clamp(0, AuraFindingConfidence.values.length - 1)
              .toInt()];
      findings.add(
        AuraFinding(
          id: 'app-${app.packageName}',
          category: AuraFindingCategory.installedApps,
          severity: severity,
          confidence: confidence,
          status: AuraFindingStatus.observed,
          observedAt: observedAt,
          title: 'Aplicación con señales para revisar',
          summary:
              'Se observaron ${app.signalCount} señales en ${app.displayName}. Son indicios que requieren contexto; no prueban que la app sea malware.',
          subject: app.displayName,
          scope:
              'Permisos concedidos, servicios sensibles, firma, ofuscación y AppOps visibles para Android.',
          evidence: List<String>.unmodifiable(app.evidence),
          limitations: <String>[..._appLimitations, ...app.limitations],
          recommendedAction:
              'Revisa la app en Ajustes > Aplicaciones, comprueba si reconoces su origen y permisos, y considera desinstalarla manualmente si no la reconoces. Aura no modificó la app.',
        ),
      );
    }

    final activeServices = _maps(scan['applications']);
    if (activeServices.isNotEmpty) {
      final evidence = <String>[];
      for (final app in activeServices.take(8)) {
        final packageName = _packageName(app['package_name']);
        if (packageName == null) continue;
        final name = _appName(app['app_name'], packageName);
        final types = <String>{
          for (final service in _maps(app['active_services']))
            if (service['type'] is String) service['type'] as String,
        };
        evidence.add(
          '$name ($packageName): ${types.isEmpty ? 'servicio sensible' : types.join(', ')}',
        );
      }
      if (activeServices.length > 8) {
        evidence.add('Y ${activeServices.length - 8} aplicaciones más.');
      }
      if (evidence.isNotEmpty) {
        findings.add(
          AuraFinding(
            id: 'apps-active-sensitive-services',
            category: AuraFindingCategory.installedApps,
            severity: AuraFindingSeverity.info,
            confidence: AuraFindingConfidence.high,
            status: AuraFindingStatus.observed,
            observedAt: observedAt,
            title: 'Servicios sensibles activos',
            summary:
                '${activeServices.length} aplicaciones tienen servicios de accesibilidad o escucha de notificaciones habilitados. Es contexto operativo, no una acusación.',
            subject: 'Inventario de servicios sensibles',
            scope:
                'Servicios de accesibilidad y notificación habilitados que Android expone a la app.',
            evidence: List<String>.unmodifiable(evidence),
            limitations: const <String>[
              ..._appLimitations,
              'Servicios del sistema o de accesibilidad legítimos también aparecen en esta lista.',
            ],
            recommendedAction:
                'Revisa Ajustes > Accesibilidad y Acceso a notificaciones; desactiva lo que no reconozcas. Aura no cambia esos permisos.',
          ),
        );
      }
    }

    return findings;
  }

  void _addAppSignal(
    Map<String, _AppSignals> apps, {
    required Object? packageName,
    required Object? appName,
    required AuraFindingSeverity severity,
    required AuraFindingConfidence confidence,
    required List<String> evidence,
    required List<String> limitations,
  }) {
    final package = _packageName(packageName);
    if (package == null) return;
    final signals = apps.putIfAbsent(
      package,
      () => _AppSignals(packageName: package),
    );
    signals.appName ??= _appName(appName, package);
    signals.signalCount++;
    if (severity.index > signals.severityRank) {
      signals.severityRank = severity.index;
    }
    if (confidence.index > signals.confidenceRank) {
      signals.confidenceRank = confidence.index;
    }
    for (final line in evidence) {
      if (line.trim().isNotEmpty && !signals.evidence.contains(line)) {
        signals.evidence.add(line);
      }
    }
    for (final line in limitations) {
      if (line.trim().isNotEmpty && !signals.limitations.contains(line)) {
        signals.limitations.add(line);
      }
    }
  }

  List<AuraFinding> _networkFindings(List<AuraThreatAlert> alerts, int now) {
    return <AuraFinding>[
      for (final alert in alerts) _networkFinding(alert, now),
    ];
  }

  AuraFinding _networkFinding(AuraThreatAlert alert, int now) {
    final app = alert.sourceAppName ?? alert.sourceAppPackage;
    final domain = alert.domain;
    final title = domain != null
        ? 'Conexiones bloqueadas a $domain'
        : 'Conexiones bloqueadas desde ${app ?? 'app no identificada'}';
    final severity = switch (alert.severity) {
      AuraThreatSeverity.low => AuraFindingSeverity.low,
      AuraThreatSeverity.medium => AuraFindingSeverity.medium,
      AuraThreatSeverity.high => AuraFindingSeverity.high,
    };
    return AuraFinding(
      id: 'network-${domain ?? alert.sourceAppPackage ?? 'unknown'}-${alert.firstSeenTimestamp}',
      category: AuraFindingCategory.networkActivity,
      severity: severity,
      confidence: AuraFindingConfidence.medium,
      status: AuraFindingStatus.observed,
      observedAt: alert.lastSeenTimestamp > 0 ? alert.lastSeenTimestamp : now,
      title: title,
      summary: alert.summary,
      subject: app ?? domain ?? 'Actividad de red',
      scope:
          'Eventos DNS/red observados por el túnel local y atribución de app cuando Android la permite.',
      evidence: <String>[
        '${alert.blockedConnectionCount} conexiones bloqueadas en la ventana de correlación.',
        if (domain != null) 'Dominio: $domain',
        if (alert.domains.length > 1) 'Dominios: ${alert.domains.join(', ')}',
        if (app != null) 'App de origen: $app',
        if (alert.sourceAppPackage != null)
          'Paquete: ${alert.sourceAppPackage}',
        ...alert.appScanIndicators.map(
          (indicator) => 'Contexto del escaneo: $indicator',
        ),
      ],
      limitations: _networkLimitations,
      recommendedAction:
          'Revisa la app de origen y el dominio. El bloqueo ya fue aplicado por el motor local; Aura no aisló ni desinstaló la app.',
    );
  }

  AuraFindingConfidence _rootConfidence(
    double? rootConfidence,
    List<String> indicators,
  ) {
    final strong = indicators.any(
      (indicator) =>
          indicator.startsWith('su_binary') ||
          indicator.startsWith('su_command_available') ||
          indicator.startsWith('magisk_path') ||
          indicator.startsWith('kernelsu_path') ||
          indicator.startsWith('root_manager_package'),
    );
    if (strong || (rootConfidence != null && rootConfidence >= 70)) {
      return AuraFindingConfidence.high;
    }
    if (rootConfidence != null && rootConfidence >= 40) {
      return AuraFindingConfidence.medium;
    }
    return AuraFindingConfidence.low;
  }

  AuraFindingConfidence _instrumentationConfidence(List<String> indicators) {
    final strong = indicators.any(
      (indicator) =>
          indicator.startsWith('frida_port:') ||
          indicator.startsWith('library:') ||
          indicator.startsWith('process:'),
    );
    return strong ? AuraFindingConfidence.high : AuraFindingConfidence.medium;
  }

  List<String> _withFallback(List<String> primary, List<String> fallback) {
    return primary.isNotEmpty ? primary : fallback;
  }

  List<String> _filterPrefixes(List<String> values, List<String> prefixes) {
    return <String>[
      for (final value in values)
        if (prefixes.any(value.startsWith)) value,
    ];
  }

  int _observedAt(Object? raw, int now) {
    if (raw is int && raw > 0) return raw;
    if (raw is num && raw > 0) return raw.toInt();
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return now;
  }

  double? _positiveNumber(Object? value) {
    if (value is num && value >= 0) return value.toDouble();
    return null;
  }

  String? _packageName(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 255) return null;
    if (!RegExp(
      r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
    ).hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  String _appName(Object? value, String packageName) {
    if (value is String && value.trim().isNotEmpty) {
      final normalized = value.trim();
      return normalized.length > 120
          ? normalized.substring(0, 120)
          : normalized;
    }
    return packageName;
  }

  List<String> _strings(Object? value) {
    if (value is! List) return const <String>[];
    final output = <String>[];
    for (final entry in value) {
      if (entry is String && entry.trim().isNotEmpty) {
        final normalized = entry.trim();
        if (!output.contains(normalized)) output.add(normalized);
      }
    }
    return List<String>.unmodifiable(output);
  }

  List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    final output = <Map<String, dynamic>>[];
    for (final entry in value) {
      if (entry is Map) {
        output.add(
          entry.map<String, dynamic>(
            (key, mapValue) => MapEntry(key.toString(), mapValue),
          ),
        );
      }
    }
    return List<Map<String, dynamic>>.unmodifiable(output);
  }
}

class _AppSignals {
  _AppSignals({required this.packageName});

  final String packageName;
  String? appName;
  int severityRank = 0;
  int confidenceRank = 0;
  int signalCount = 0;
  final List<String> evidence = <String>[];
  final List<String> limitations = <String>[];

  String get displayName => appName ?? packageName;
}
