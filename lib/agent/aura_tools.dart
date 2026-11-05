import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../ai_brain.dart';
import '../providers/aura_state_provider.dart';
import '../secure_vault.dart';
import 'aura_crypto_layer.dart';
import 'agent_execution_guard.dart';

class ToolStep {
  const ToolStep({
    required this.name,
    required this.arguments,
  });

  final String name;
  final Map<String, dynamic> arguments;
}

class ToolResult {
  const ToolResult({
    required this.summary,
    required this.data,
  });

  final String summary;
  final Map<String, dynamic> data;
}

abstract class AuraTools {
  static final Uri _modelUri = Uri.parse(
    'https://yojamm16-boop.github.io/Aura-V1.0/model/aura_brain_model.json',
  );
  static final Uri _modelDigestUri = Uri.parse(
    'https://yojamm16-boop.github.io/Aura-V1.0/model/aura_brain_model.json.sha256',
  );
  static final Uri _modelSignatureUri = Uri.parse(
    'https://yojamm16-boop.github.io/Aura-V1.0/model/aura_brain_model.json.sig',
  );
  static const int _maxModelBytes = 5 * 1024 * 1024;
  static const MethodChannel _engineChannel =
      MethodChannel('com.aura.cyberdefense/engine');
  static const MethodChannel _securityChannel =
      MethodChannel('com.ciberdefensa.aura/security');
    static const MethodChannel _panicChannel =
      MethodChannel('com.aura.cyberdefense/panic');
  static final AuraSecureVault _secureVault = AuraSecureVault();

  static Future<ToolResult> execute(
    ToolStep step, {
    void Function(String message)? onProgress,
    AuraStateProvider? stateProvider,
    AuraToolStartedCallback? onToolStarted,
    AuraToolCompletedCallback? onToolCompleted,
    AgentCancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? AgentCancellationToken();
    final policyError = AuraToolExecutionPolicy.validate(
      step.name,
      step.arguments,
    );
    if (policyError != null) {
      return ToolResult(
        summary: policyError == 'user_confirmation_required'
            ? 'La operación no se ejecutó: requiere confirmación explícita.'
            : 'La operación fue rechazada por la política de ejecución segura.',
        data: <String, dynamic>{
          'ok': false,
          'error': policyError,
          'tool': step.name,
          'security_level': 'warning',
        },
      );
    }

    try {
      token.markExecutionStarted();
    } on AgentOperationCancelled {
      return ToolResult(
        summary: 'Operación cancelada antes de iniciar; no se ejecutó ninguna herramienta.',
        data: <String, dynamic>{
          'ok': false,
          'error': 'operation_cancelled',
          'tool': step.name,
          'side_effect_started': false,
        },
      );
    }

    var timedOut = false;
    try {
      return await _executeTrusted(
        step,
        onProgress: (message) {
          if (!timedOut) onProgress?.call(message);
        },
        stateProvider: stateProvider,
        onToolStarted: (toolName, arguments) {
          if (!timedOut) onToolStarted?.call(toolName, arguments);
        },
        onToolCompleted: (toolName, arguments, result) {
          if (!timedOut) onToolCompleted?.call(toolName, arguments, result);
        },
      ).timeout(
        AuraToolExecutionPolicy.timeoutFor(step.name),
        onTimeout: () {
          timedOut = true;
          return ToolResult(
            summary: 'La operación excedió el tiempo máximo. Su resultado es desconocido; comprueba el estado antes de volver a intentarlo.',
            data: <String, dynamic>{
              'ok': false,
              'error': 'operation_timeout',
              'tool': step.name,
              'outcome': 'unknown',
              'automatic_retry_allowed': false,
              'security_level': 'warning',
            },
          );
        },
      );
    } on Object {
      return ToolResult(
        summary: 'La herramienta no pudo completar la operación. No se confirmó ningún cambio.',
        data: <String, dynamic>{
          'ok': false,
          'error': 'tool_boundary_failure',
          'tool': step.name,
          'security_level': 'warning',
        },
      );
    }
  }

  static Future<ToolResult> _executeTrusted(
    ToolStep step, {
    void Function(String message)? onProgress,
    AuraStateProvider? stateProvider,
    AuraToolStartedCallback? onToolStarted,
    AuraToolCompletedCallback? onToolCompleted,
  }) async {
    try {
      switch (step.name) {
        case 'update_defenses':
          return await _updateDefenses(onProgress);
        case 'audit_device':
          final report = await _securityChannel.invokeMapMethod<String, dynamic>(
            'checkHostileEnvironment',
          );
          if (report == null ||
              report['isEmulator'] is! bool ||
              report['isRooted'] is! bool ||
              report['isInstrumented'] is! bool ||
              report['isScreenOverlayDetected'] is! bool ||
              report['isHostile'] is! bool ||
              report['indicators'] is! List ||
              report['environmentCheckErrors'] is! List ||
              report['untrustedAccessibilityServicePackages'] is! List) {
            return const ToolResult(
              summary: 'Android no devolvió un informe válido de postura del dispositivo.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'invalid_device_audit_report',
                'tool': 'audit_device',
              },
            );
          }
          final indicators = (report['indicators'] as List)
              .whereType<String>()
              .toList(growable: false);
          final errors = (report['environmentCheckErrors'] as List)
              .whereType<String>()
              .toList(growable: false);
          final untrustedAccessibility =
              (report['untrustedAccessibilityServicePackages'] as List)
                  .whereType<String>()
                  .toList(growable: false);
          final hostile = report['isHostile'] as bool;
          final auditStatus = errors.isNotEmpty
              ? 'incomplete'
              : hostile
                  ? 'review_required'
                  : 'no_indicators_observed';
          final summary = errors.isNotEmpty
              ? 'Auditoría de postura incompleta: ' +
                  indicators.length.toString() +
                  ' indicadores observados y ' +
                  errors.length.toString() +
                  ' comprobaciones no disponibles. Revisa el detalle antes de sacar conclusiones.'
              : hostile
                  ? 'Android reportó ' +
                      indicators.length.toString() +
                      ' indicadores del entorno que requieren revisión. Esto no demuestra por sí solo que exista malware.'
                  : 'La auditoría terminó sin indicadores hostiles observados en las comprobaciones disponibles. Esto no certifica que el dispositivo esté libre de amenazas.';
          return ToolResult(
            summary: summary,
            data: <String, dynamic>{
              'ok': true,
              'user_action_required': errors.isNotEmpty || hostile,
              'tool': 'audit_device',
              'audit_status': auditStatus,
              'security_level': errors.isNotEmpty || hostile ? 'warning' : 'safe',
              'is_emulator': report['isEmulator'],
              'is_rooted': report['isRooted'],
              'root_confidence': report['rootConfidence'],
              'is_instrumented': report['isInstrumented'],
              'screen_overlay_detected': report['isScreenOverlayDetected'],
              'is_hostile': hostile,
              'indicators': indicators,
              'check_errors': errors,
              'untrusted_accessibility_packages': untrustedAccessibility,
              'timestamp': report['timestamp'],
              'limitations': <String>[
                'Las señales de root, emulador, instrumentación y overlays son heurísticas; pueden existir falsos positivos y falsos negativos.',
                'Android limita la visibilidad de procesos, paquetes y estados de otras aplicaciones.',
                'Un resultado sin indicadores no garantiza que el dispositivo esté libre de malware.',
              ],
            },
          );
        case 'scan_apps':
          final report = await _securityChannel.invokeMapMethod<String, dynamic>(
            'scanActiveSensitiveServices',
          );
          if (report == null) {
            return const ToolResult(
              summary: 'Android no devolvió un informe del escáner de aplicaciones.',
              data: <String, dynamic>{'ok': false, 'error': 'empty_scan_report'},
            );
          }
          const countToListField = <String, String>{
            'count': 'applications',
            'special_access_count': 'special_access',
            'app_provenance_count': 'app_provenance',
            'suspicious_app_count': 'suspicious_apps',
            'signature_issue_count': 'signature_issues',
            'obfuscated_app_count': 'obfuscated_apps',
          };
          final countsAreValid = countToListField.keys.every((key) {
            final value = report[key];
            return value is int && value >= 0;
          });
          final listsAreValid = countToListField.values.every((key) {
            final value = report[key];
            return value is List && value.every((entry) => entry is Map);
          });
          final timestamp = report['timestamp'];
          final countsMatchLists = countsAreValid &&
              listsAreValid &&
              countToListField.entries.every(
                (entry) =>
                    report[entry.key] ==
                    (report[entry.value] as List).length,
              );
          final activeSpecialAccessCount =
              report['active_special_access_count'];
          final specialAccessCount = report['special_access_count'];
          final confirmedActiveSpecialAccess = listsAreValid
              ? (report['special_access'] as List)
                  .where(
                    (entry) =>
                        (entry as Map)['state'] == 'ACTIVE',
                  )
                  .length
              : -1;
          if (timestamp is! int ||
              timestamp <= 0 ||
              !countsMatchLists ||
              activeSpecialAccessCount is! int ||
              activeSpecialAccessCount < 0 ||
              activeSpecialAccessCount != confirmedActiveSpecialAccess ||
              activeSpecialAccessCount > (specialAccessCount as int)) {
            return const ToolResult(
              summary: 'Auditoría de aplicaciones incompleta: Android devolvió un informe ausente o incoherente. No se interpretará como cero aplicaciones ni cero riesgos.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'invalid_scan_report',
                'scan_status': 'incomplete',
                'security_level': 'warning',
                'tool': 'scan_apps',
              },
            );
          }
          final activeServices = report['count'] as int;
          final suspicious = report['suspicious_app_count'] as int;
          final activeSpecialAccess = activeSpecialAccessCount;
          final signatureIssues = report['signature_issue_count'] as int;
          final obfuscated = report['obfuscated_app_count'] as int;
          return ToolResult(
            summary: 'Escaneo local completado: $activeServices apps con servicios sensibles activos, $activeSpecialAccess accesos especiales confirmados, $suspicious con combinación de permisos de alto riesgo, $signatureIssues incidencias de firma y $obfuscated con indicadores de ofuscación. Son señales para revisar, no prueba de malware.',
            data: <String, dynamic>{
              'ok': true,
              'scan_type': 'installed_app_static_review',
              'timestamp': report['timestamp'],
              'active_service_app_count': activeServices,
              'special_access_count': report['special_access_count'] ?? 0,
              'active_special_access_count': activeSpecialAccess,
              'special_access': report['special_access'] ?? const <dynamic>[],
              'app_provenance_count': report['app_provenance_count'] ?? 0,
              'app_provenance': report['app_provenance'] ?? const <dynamic>[],
              'suspicious_app_count': suspicious,
              'signature_issue_count': signatureIssues,
              'obfuscated_app_count': obfuscated,
              'applications': report['applications'] ?? const <dynamic>[],
              'suspicious_apps': report['suspicious_apps'] ?? const <dynamic>[],
              'signature_issues': report['signature_issues'] ?? const <dynamic>[],
              'obfuscated_apps': report['obfuscated_apps'] ?? const <dynamic>[],
              'limitations': <String>[
                'Los permisos solicitados no demuestran que estén concedidos o abusados.',
                'Los accesos especiales solo se cuentan como activos cuando Android confirma AppOps MODE_ALLOWED; los estados condicionales o desconocidos no se suman.',
                'La procedencia de instalación es contexto y no demuestra legitimidad ni malware.',
                'Una firma distinta o múltiples firmantes no prueban por sí solos una aplicación maliciosa.',
                'La entropía y los identificadores ofuscados son heurísticas y pueden producir falsos positivos.',
                'El análisis no ejecuta ni descompila código y no sustituye Play Protect.',
              ],
            },
          );
        case 'analyze_domain':
          final domain = step.arguments['domain'];
          if (domain is! String ||
              !RegExp(
                r'^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$',
              ).hasMatch(domain) ||
              InternetAddress.tryParse(domain) != null) {
            return const ToolResult(
              summary: 'No se analizó el dominio: el nombre no tiene un formato DNS válido.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'invalid_domain',
                'tool': 'analyze_domain',
              },
            );
          }
          final normalizedDomain = domain.toLowerCase();
          final brain = AuraAIBrain(
            stateProvider: stateProvider,
            onToolStarted: onToolStarted,
            onToolCompleted: onToolCompleted,
          );
          final modelAvailable = await brain.preloadModel();
          if (!modelAvailable) {
            return const ToolResult(
              summary: 'Análisis no disponible: no se pudo cargar el modelo local validado. No se emitió un veredicto.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'verified_model_unavailable',
                'tool': 'analyze_domain',
              },
            );
          }
          final integrity = await brain.verifyModelIntegrity();
          if (!integrity.verified || !integrity.signatureVerified) {
            return ToolResult(
              summary: 'Análisis detenido: la integridad o firma del modelo no pudo verificarse. No se emitió un veredicto.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'model_integrity_unverified',
                'domain': normalizedDomain,
                'model_version': integrity.modelVersion,
                'sha256': integrity.sha256,
                'tool': 'analyze_domain',
              },
            );
          }
          final analysis = await brain.analyzeCyberThreat(
            jsonEncode(<String, String>{'host': normalizedDomain}),
            enforceBlocklistHits: false,
          );
          final completed = analysis.isNotEmpty &&
              !analysis.startsWith('No se pudo completar') &&
              !analysis.contains('no se encontró un dominio válido');
          final threatRequiresReview = analysis.contains('POSIBLE AMENAZA') ||
              analysis.contains('AMENAZA:');
          return ToolResult(
            summary: analysis,
            data: <String, dynamic>{
              'ok': completed,
              'user_action_required': threatRequiresReview,
              if (threatRequiresReview) 'security_level': 'warning',
              'tool': 'analyze_domain',
              'domain': normalizedDomain,
              'analysis_scope': 'local_domain_heuristics',
              'model_version': integrity.modelVersion,
              'model_sha256': integrity.sha256,
              'model_signature_verified': integrity.signatureVerified,
              'automatic_blocking': false,
              'limitations': <String>[
                'El modelo clasifica características del nombre de dominio; no inspecciona contenido web ni certifica la seguridad de un sitio.',
                'Un resultado benigno no garantiza que el sitio sea seguro.',
                'Los hallazgos no modifican el firewall; el bloqueo requiere una orden y confirmación separadas.',
              ],
            },
          );
        case 'toggle_defenses':
          return await _toggleDefenses(step.arguments);
        case 'block_domain':
          if (step.arguments['confirmed_by_user'] != true) {
            return const ToolResult(
              summary: 'Bloqueo no ejecutado: requiere confirmación explícita del usuario.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'user_confirmation_required',
                'action': 'block_domain',
              },
            );
          }
          final domain = step.arguments['domain'];
          if (domain is! String || domain.trim().isEmpty || domain.length > 253) {
            return const ToolResult(
              summary: 'No se ejecutó el bloqueo: el dominio no es válido.',
              data: <String, dynamic>{'ok': false, 'error': 'invalid_domain'},
            );
          }
          final blocked = await _engineChannel.invokeMethod<bool>(
            'addDnsBlockRule',
            {'domain': domain},
          );
          final confirmed = blocked == true;
          return ToolResult(
            summary: confirmed
                ? 'Dominio bloqueado por el motor DNS local.'
                : 'El motor DNS no confirmó el bloqueo del dominio.',
            data: <String, dynamic>{
              'ok': confirmed,
              'domain': domain,
            },
          );
        case 'isolate_app':
          if (step.arguments['confirmed_by_user'] != true) {
            return const ToolResult(
              summary: 'No se abrió la configuración de la aplicación: requiere confirmación explícita.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'user_confirmation_required',
                'action': 'isolate_app',
              },
            );
          }
          final packageName = step.arguments['package_name'];
          if (packageName is! String ||
              !RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')
                  .hasMatch(packageName) ||
              packageName.length > 255) {
            return const ToolResult(
              summary: 'No se abrió la configuración: el identificador de paquete no es válido.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'invalid_package_name',
                'action': 'isolate_app',
              },
            );
          }
          final reason = step.arguments['reason'];
          final nativeResult = await _engineChannel.invokeMapMethod<String, dynamic>(
            'openAppDetails',
            <String, dynamic>{
              'package_name': packageName,
              if (reason is String) 'reason': reason,
            },
          );
          if (nativeResult == null) {
            return const ToolResult(
              summary: 'Android no devolvió el resultado de Ajustes.',
              data: <String, dynamic>{'ok': false},
            );
          }
          return ToolResult(
            summary: (nativeResult['message'] as String?) ??
                (nativeResult['error'] as String?) ??
                'Android devolvió el resultado de la solicitud.',
            data: <String, dynamic>{
              ...nativeResult,
              'action': 'open_app_settings',
              'isolation_performed': false,
              'user_action_required': true,
              'limitations': <String>[
                'Android no permite a una aplicación ordinaria detener o aislar arbitrariamente otra aplicación sin privilegios especiales.',
                'Esta acción solo abre la ficha de configuración; el usuario debe decidir qué permisos o accesos revocar.',
              ],
            },
          );
        case 'panic_isolation':
          if (step.arguments['confirmed_by_user'] != true) {
            return const ToolResult(
              summary: 'Aislamiento no ejecutado: requiere confirmación explícita del usuario.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'user_confirmation_required',
                'action': 'panic_isolation',
              },
            );
          }
          final isolated = await _panicChannel.invokeMethod<bool>(
                'panicIsolation',
              ) ??
              false;
          return ToolResult(
            summary: isolated
                ? 'Forwarding del túnel detenido; la interfaz VPN queda en modo de descarte.'
                : 'No se confirmó el aislamiento: el túnel VPN no estaba activo.',
            data: <String, dynamic>{
              'ok': isolated,
              'isolation_active': isolated,
              'scope': 'active_vpn_tun',
              'security_level': isolated ? 'critical' : 'warning',
            },
          );
        case 'resume_network':
          if (step.arguments['confirmed_by_user'] != true) {
            return const ToolResult(
              summary: 'Reanudación no ejecutada: requiere confirmación explícita del usuario.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'user_confirmation_required',
                'action': 'resume_network',
              },
            );
          }
          final resumed = await _panicChannel.invokeMethod<bool>(
                'resumeTunnel',
              ) ??
              false;
          return ToolResult(
            summary: resumed
                ? 'Forwarding del túnel restablecido.'
                : 'No se pudo restablecer el forwarding del túnel.',
            data: <String, dynamic>{
              'ok': resumed,
              if (!resumed) 'security_level': 'warning',
            },
          );
        case 'cryptographic_purge':
          if (step.arguments['confirmed_by_user'] != true) {
            return const ToolResult(
              summary: 'Purga no ejecutada: requiere una segunda orden de confirmación explícita.',
              data: <String, dynamic>{
                'ok': false,
                'error': 'user_confirmation_required',
                'action': 'cryptographic_purge',
              },
            );
          }
          await AuraAIBrain.purgeAllInMemoryModels();
          final nativeAuditMemoryPurged = await _engineChannel.invokeMethod<bool>(
                'purgeAuditMemory',
              ) ??
              false;
          await _secureVault.purgeSensitiveData();
          final Map<String, dynamic> auditData = {
            'ok': nativeAuditMemoryPurged,
            'model_cache_purged': true,
            'secure_storage_purged': true,
            'native_audit_memory_purged': nativeAuditMemoryPurged,
            'completion': nativeAuditMemoryPurged ? 'complete' : 'partial',
          };
          return ToolResult(
            summary: nativeAuditMemoryPurged
                ? 'Cachés de modelos, datos de SecureVault y memoria de auditoría nativa purgados.'
                : 'Cachés de modelos y datos de SecureVault purgados, pero Android no confirmó la limpieza de la memoria de auditoría nativa. La operación queda marcada como parcial.',
            data: auditData,
          );
        default:
          return ToolResult(
            summary: 'Herramienta no reconocida: ${step.name}.',
            data: <String, dynamic>{'ok': false, 'tool': step.name},
          );
      }
    } on PlatformException catch (error) {
      return ToolResult(
        summary: 'No se pudo completar la operación nativa. No se confirmó ningún cambio.',
        data: <String, dynamic>{
          'ok': false,
          'error': 'operation_failed',
          'error_type': 'PlatformException',
          'code': error.code,
          'tool': step.name,
          'security_level': 'warning',
        },
      );
    } on MissingPluginException {
      return ToolResult(
        summary: 'El canal nativo de Aura no está disponible.',
        data: <String, dynamic>{
          'ok': false,
          'error': 'missing_plugin',
          'tool': step.name,
        },
      );
    } on Object catch (error) {
      // Native, storage, filesystem and network failures must become an
      // explicit unsuccessful result; never let a tool failure look successful
      // or crash the agent command loop. Avoid returning exception text because
      // platform errors can contain paths, hostnames or other sensitive data.
      return ToolResult(
        summary: 'No se pudo completar la operación. No se confirmó ningún cambio; revisa el estado antes de reintentar.',
        data: <String, dynamic>{
          'ok': false,
          'error': 'operation_failed',
          'error_type': error.runtimeType.toString(),
          'tool': step.name,
          'security_level': 'warning',
        },
      );
    }
  }

  static Future<ToolResult> _toggleDefenses(
    Map<String, dynamic> arguments,
  ) async {
    const shieldChannel = MethodChannel('com.ciberdefensa.aura/shield');
    final activate = arguments['activate'] == true;
    if (arguments['confirmed_by_user'] != true) {
      return const ToolResult(
        summary: 'Cambio de defensa no ejecutado: requiere confirmación explícita del usuario.',
        data: <String, dynamic>{
          'ok': false,
          'error': 'user_confirmation_required',
          'action': 'toggle_defenses',
        },
      );
    }
    try {
      final confirmed = await shieldChannel.invokeMethod<bool>(
            activate ? 'startShield' : 'stopShield',
          ) ??
          false;
      return ToolResult(
        summary: confirmed
            ? activate
                ? 'DEFENSA ACTIVADA — túnel en marcha'
                : 'DEFENSA DESACTIVADA — túnel detenido'
            : activate
                ? 'El escudo VPN no se inició: falta el consentimiento de Android o el servicio no respondió.'
                : 'Android no confirmó la detención del escudo VPN.',
        data: <String, dynamic>{
          'ok': confirmed,
          if (confirmed) 'vpn_active': activate,
          if (!confirmed) 'security_level': 'warning',
        },
      );
    } on PlatformException catch (error) {
      return ToolResult(
        summary: 'No pude contactar el motor VPN. Revisa que Aura esté activa.',
        data: <String, dynamic>{
          'ok': false,
          'error': 'operation_failed',
          'error_type': 'PlatformException',
          'code': error.code,
          'tool': 'toggle_defenses',
          'security_level': 'warning',
        },
      );
    } on MissingPluginException {
      return const ToolResult(
        summary: 'No pude contactar el motor VPN. Revisa que Aura esté activa.',
        data: <String, dynamic>{
          'ok': false,
          'error': 'missing_plugin',
          'tool': 'toggle_defenses',
          'security_level': 'warning',
        },
      );
    } on Object catch (error) {
      // Keep unexpected native failures inside the tool boundary and avoid
      // exposing exception messages or device-specific paths to the agent UI.
      return ToolResult(
        summary: 'No pude completar la operación VPN. No se confirmó ningún cambio.',
        data: <String, dynamic>{
          'ok': false,
          'error': 'operation_failed',
          'error_type': error.runtimeType.toString(),
          'tool': 'toggle_defenses',
          'security_level': 'warning',
        },
      );
    }
  }

  static Future<ToolResult> _updateDefenses(
    void Function(String message)? onProgress,
  ) async {
    try {
      onProgress?.call(
        'Conectando por HTTPS al repositorio público de modelos...',
      );
      onProgress?.call(
        'Buscando la firma RSA y el digest SHA-256 publicados...',
      );
      final digestResponse = await http.get(
        _modelDigestUri,
        headers: const <String, String>{},
      ).timeout(const Duration(seconds: 30));
      if (digestResponse.statusCode != HttpStatus.ok ||
          digestResponse.bodyBytes.length > 128) {
        throw const HttpException(
          'No se pudo descargar una verificación SHA-256 válida.',
        );
      }

      final signatureResponse = await http.get(
        _modelSignatureUri,
        headers: const <String, String>{},
      ).timeout(const Duration(seconds: 30));
      if (signatureResponse.statusCode != HttpStatus.ok ||
          signatureResponse.bodyBytes.isEmpty ||
          signatureResponse.bodyBytes.length > 1024) {
        throw const HttpException(
          'No se pudo descargar una firma RSA válida para el modelo.',
        );
      }

      onProgress?.call('Descargando el modelo firmado de 500 árboles... 📥');
      final modelResponse = await http.get(
        _modelUri,
        headers: const <String, String>{},
      ).timeout(const Duration(seconds: 30));
      if (modelResponse.statusCode != HttpStatus.ok ||
          modelResponse.bodyBytes.isEmpty ||
          modelResponse.bodyBytes.length > _maxModelBytes) {
        modelResponse.bodyBytes.fillRange(
          0,
          modelResponse.bodyBytes.length,
          0,
        );
        throw const HttpException(
          'El modelo público está vacío, excede el tamaño permitido o no está disponible.',
        );
      }

      final expectedDigest = utf8.decode(digestResponse.bodyBytes).trim();
      final modelBytes = Uint8List.fromList(modelResponse.bodyBytes);
      final signatureBytes = Uint8List.fromList(signatureResponse.bodyBytes);
      if (!AuraCryptoLayer.verifySignature(modelBytes, signatureBytes)) {
        modelBytes.fillRange(0, modelBytes.length, 0);
        signatureBytes.fillRange(0, signatureBytes.length, 0);
        return await _integrityFailure(
          'ERROR CRÍTICO: la firma RSA/SHA-256 no es válida; se descartó la descarga y se activaron las reglas locales.',
        );
      }
      final actualDigest = sha256.convert(modelBytes).toString();
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(expectedDigest) ||
          actualDigest != expectedDigest.toLowerCase()) {
        modelBytes.fillRange(0, modelBytes.length, 0);
        signatureBytes.fillRange(0, signatureBytes.length, 0);
        return await _integrityFailure(
          'ERROR CRÍTICO: el SHA-256 remoto no coincide; se descartó la descarga y se activaron las reglas locales.',
        );
      }

      onProgress?.call(
        'Validando la estructura, cifrando para este dispositivo e instalando el modelo local... 🧠',
      );
      final supportDirectory = await getApplicationSupportDirectory();
      await AuraAIBrain.installDownloadedModel(
        destination: File(
          '${supportDirectory.path}/aura_brain_model.enc',
        ),
        modelBytes: modelBytes,
        signatureBytes: signatureBytes,
        expectedSha256: expectedDigest,
      );
      return const ToolResult(
        summary:
            'Modelo de 500 árboles verificado, cifrado con la clave del dispositivo e instalado.',
        data: <String, dynamic>{
          'ok': true,
          'model_updated': true,
          'tree_count': 500,
          'sha256_verified': true,
          'security_level': 'safe',
        },
      );
    } on Object {
      await AuraAIBrain.useSafeRuleFallback(
        'No se pudo verificar o instalar el modelo remoto; se activaron las reglas locales.',
        notifyHud: false,
      );
      return ToolResult(
        summary:
            'ERROR CRÍTICO: no se verificó el modelo remoto; se descartó el búfer y se usarán las reglas locales.',
        data: const <String, dynamic>{
          'ok': false,
          'critical_integrity_failure': true,
          'security_level': 'critical',
        },
      );
    }
  }

  static Future<ToolResult> _integrityFailure(String summary) async {
    await AuraAIBrain.useSafeRuleFallback(summary, notifyHud: false);
    return ToolResult(
      summary: summary,
      data: const <String, dynamic>{
        'ok': false,
        'critical_integrity_failure': true,
        'security_level': 'critical',
      },
    );
  }
}
