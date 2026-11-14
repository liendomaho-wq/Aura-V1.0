# Matriz de estado — Aura

**Fecha de la auditoría:** 2026-11-14  
**HEAD de la primera auditoría:** `5089d35b9764d27075ec5d67ea25cf7dcb9da4a5`  
**Corrección QA:** este documento se actualiza en el commit que quita la API privada.  
**Especificación vinculante:** [AURA_MASTER_PROMPT.md](AURA_MASTER_PROMPT.md)  
**Alcance:** Parte 1 y los módulos nombrados en las Partes 2–6. La Parte 7 (visual, robot, voz) queda diferida.

`5089d35` y `6318277` **no compilaban** Android. «Aura Android Debug Build» falló en ambos:

- [`5089d35`, run 43636981696](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43636981696)
- [`6318277`, run 43645598876](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43645598876)

El fallo es `:app:compileDebugKotlin`: `AuraUnderlyingNetwork.kt` llamaba a `NetworkCapabilities.underlyingNetworks`, que no está en el SDK público (`Unresolved reference`). El job «Real Android Keystore migration» quedó skipped. El último build Android en verde antes de esa rotura es `e5cf2fe`. «Aura Flutter Quality» sí pasó, porque no compila Kotlin.

Los tests `tool/test_*.py` que leen el fuente **no cuentan como prueba de comportamiento** y no bastan para una A. Una interfaz o un nombre de clase tampoco.

## Criterios

| Categoría | Significado |
|---|---|
| A | Implementado y verificado con una prueba que ejecuta el comportamiento, o con una observación real citada. Un test que solo lee el fuente no basta. |
| B | Hay código conectado, pero falta una parte del contrato o la prueba que lo cerraría. |
| C | No está implementado. |
| D | No se puede cumplir con las APIs públicas de una app sin root, o afirmarlo sería falso. |

## Resumen

| Categoría | Filas |
|---|---|
| A | 8 |
| B | 56 |
| C | 17 |
| D | 6 |
| **Total** | **87** |

## Instantánea de Git y CI

- Rama de trabajo: `main`. Hay decenas de ramas remotas (`arena/*`, `fix/*`, `rebuild/*`). No son el producto actual.
- Pull requests abiertos: **11**. Cuatro no son borrador y su base es `main`: `#1`, `#8`, `#28` y `#30`. Los borradores son `#4`, `#12`, `#13`, `#14`, `#16`, `#17` y `#19`. `#17` tiene base `arena/c5f6f7b0-aura-v1-0` y cabeza `arena/deepseek-local-llm`; no apunta a `main`. Ninguno describe el comportamiento actual.
- GitHub Actions: `flutter-quality.yml`, `android-debug-build.yml`, `android-release.yml`, `release-signing-integrity.yml`, `aura-llama-android-build.yml`, `model-training.yml`, `deploy-model-pages.yml`.
- CodeMagic (`codemagic.yaml`): `android-debug` (APK de prueba) y `android-build` (pipeline en `mac_mini_m2`, Flutter `3.47.9`, JDK 17). El release lleva `AURA_REQUIRE_RELEASE_SIGNING=false`. `tool/compile_aura.sh` borra entonces las variables de firma y usa la clave de debug. El artefacto se sigue llamando `app-release.apk`; el aviso «NO DISTRIBUIR» solo está en el log. El paso de migración Keystore de ese YAML imprime `[NOT RUN]`.
- Si `~/.android/debug.keystore` no existe, `tool/compile_aura.sh` lo genera en esa máquina. En un runner efímero el certificado puede cambiar de build a build. Instalar encima fallaría con `INSTALL_FAILED_UPDATE_INCOMPATIBLE` y desinstalar **borra** SecureVault y el resto de datos. No se compararon dos artefactos en esta corrección. No se mete un keystore en Git. Hace falta un keystore de prueba fijo en un grupo secreto de CodeMagic, o aceptar que cada APK de prueba obliga a desinstalar.
- Toolchain fijada en `android/app/build.gradle`: minSdk 24, compileSdk/targetSdk 36, NDK `28.2.13676358`, ABI `armeabi-v7a`, `arm64-v8a`, `x86_64`.
- Dispositivo objetivo confirmado por el dueño el 2026-11-14: **TECNO POVA 5, 8 GB de RAM, Android 14 (API 34)**. El Redmi Note 15 Pro+ 5G (Android 16) sigue en la spec como segunda referencia, no como sustituto. Un emulador Android 16 **no cuenta** como prueba del POVA 5. Toda fila que pida validación en el aparato sigue en B hasta verse en API 34.
- El dueño confirmó el **arranque** de la VPN en ese TECNO, en un SHA anterior a `5089d35`. Ese SHA compilaba (`e5cf2fe` es el último Android Debug Build en verde). `5089d35` no produjo APK: la parada y la etiqueta de red no se pudieron instalar.

## Parte 1 — Áreas de la auditoría

| Área | Estado | Evidencia o hueco |
|---|---|---|
| Flutter/Dart | B | App en `lib/` con consola, splash, agente y tests (`flutter test` local previo: 316 pasaron, 1 omitida). No cubre firewall por modos, memoria de conversación ni respuesta a incidentes. |
| Kotlin y servicios | B | `AuraVpnService`, escáner, LLM, telemetría y `AuraUpdateWorker` existen. Desde `5089d35` `compileDebugKotlin` estaba roto por `underlyingNetworks` (API no pública). Este arreglo lo quita. Siguen faltando los servicios de las Partes 4 y 6. |
| C++/JNI | B | `hev-jni.c` (puente en hilo propio), `aura_sni_firewall.c`, `libaura_llm`. `tool/test_jni_bridge.py` comprueba el fuente y omite el harness si falta `jni.h`. El dueño vio la VPN estable tras el arreglo de crash; no hay matriz JNI de fugas. |
| Gradle | A | La política del wrapper y del NDK pasa, y además `eef52b0` compiló: [Aura Android Debug Build 43646707387](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43646707387) incluye `compileDebugKotlin`, el APK debug y las pruebas JVM. La A anterior, apoyada solo en tests de política mientras el build estaba rojo, no valía. |
| llama.cpp | B | Backend nombrado en `AuraLlmContract.kt` y empaquetado como `libaura_llm.so` (lo comprueba el script de CodeMagic). Sin generación observada en un teléfono. |
| Motor de IA (clasificador) | A | Bosque 3.0.0 en `assets/model/aura_brain_model.json`, `lib/inference/aura_ai_inference.dart`, `test/aura_ai_inference_test.dart`. No inspecciona páginas. |
| Agente | B | `lib/agent/agent_controller.dart`, parser por reglas, confirmación `CONFIRMO`, `test/agent_controller_test.dart`. No planifica tareas persistentes. |
| Registro de herramientas | B | `lib/agent/aura_tools.dart` y `lib/agent/agent_execution_guard.dart` (allowlist, confirmación, plazos). No es el registro completo de la Parte 2 para acciones futuras. |
| VPN | B | Un solo `VpnService`. Arranque confirmado por el dueño en el POVA 5 (Android 14) en un SHA que sí compilaba. La parada, **Detener** y la etiqueta de red están en el código, pero `5089d35` no generó APK. Siguen en B hasta probarse en API 34. Fugas, IPv6 y batería no medidos. |
| Motor de hallazgos | B | `lib/security/aura_findings_engine.dart`, UI `findings-center`, `test/aura_findings_ui_test.dart`. Solo lectura: no hay resolver, reabrir ni búsqueda. |
| Seguridad de red | B | Firewall SNI nativo, eventos DNS y descarte de DNS cifrado conocido. No hay motor de reglas con modos. |
| SecureVault | B | `lib/secure_vault.dart` pide migración con backup y `resetOnError=false`. `SecureStorageMigrationTest` pasó en el emulador **Android 16** (API 36) del run [43631402912](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43631402912) sobre `e5cf2fe`. En `5089d35` y `6318277` ese job quedó skipped. El emulador 16 no equivale al POVA 5 (API 34): en el teléfono sigue en B. |
| Criptografía | B | HMAC de dominios, firma RSA del modelo, sobre histórico AES-256-CBC + HMAC (`lib/crypto/aura_crypto_layer.dart`, `test/aura_crypto_layer_test.dart`). No es AES-GCM en todos los sobres. |
| Almacenamiento | B | `AuraStoragePlugin` y `test/aura_storage_test.dart` (espacio y memoria). Sin exportación protegida ni política de retención de la Parte 6. |
| Permisos | B | Manifest y escáner (`AuraAppGenomeScanner.kt`, `test/aura_core_test.dart`). No guía la revocación ni la desinstalación oficial. |
| Interfaz | B | Splash, consola, hallazgos, hoja del modelo y etiqueta de red. La Parte 7 está diferida. No hay pantalla de firewall. |
| Navegación | B | Splash hacia una consola. No hay rutas separadas para reglas, historial o incidentes. |
| CI de GitHub | B | Android Debug Build estuvo en rojo en [43636981696](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43636981696) (`5089d35`) y [43645598876](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43645598876) (`6318277`). En `eef52b0` volvió a verde: [43646707387](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43646707387) (APK debug, pruebas JVM y migración Keystore en emulador Android 16) y [Flutter Quality 43646707382](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43646707382). Sigue en B porque Flutter Quality no compila Kotlin y CodeMagic no se observó. |
| CodeMagic | B | Dos workflows operativos en el YAML. El release de prueba puede firmar con debug. La migración Keystore no corre ahí. |
| Pruebas | B | Suites Flutter, Python y JVM de la VPN. Falta el protocolo físico y casi toda la Parte 4 y 6. |
| Documentación | B | README y `docs/` abundantes. Faltan los nombres que pide la Parte 8: `AURA_ARCHITECTURE.md`, `AURA_SECURITY.md`, `AURA_FIREWALL.md`, `AURA_VPN.md`, `AURA_AI.md`, `AURA_TESTING.md`. |

## Parte 2 — Cerebro e IA local

| Módulo | Estado | Evidencia o hueco |
|---|---|---|
| Pin del GGUF | A | `lib/llm/aura_llm_model_source.dart` y `docs/LOCAL_AI_MODEL.md`: DeepSeek-R1-Distill-Qwen-1.5B Q4_K_M, revisión `3cb4d155…`, SHA-256 `f3bdf9cf…`, tamaño `1117321312`. El pin no se calcula del archivo descargado. `test/aura_llm_model_source_test.dart`. |
| Gestor de descarga | B | `lib/llm/aura_llm_model_manager.dart`: HTTPS, tamaño, `Range`, temporal, rename, un vuelo, espacio, borrado si el runtime está libre. Tests de instalador. No hay descarga extremo a extremo desde la app en un teléfono. |
| Inferencia llama.cpp | B | `AuraLlmPlugin.kt` falla cerrado si falta la biblioteca o el modelo. `test/local_llm_planner_test.dart` y `tool/test_llm_native_integration.py`. El GGUF de 1,1 GB cabe en los 8 GB del POVA 5 solo como archivo; la carga y el primer token no se han visto en API 34. |
| Política de contexto | B | `lib/llm/aura_llm_context_policy.dart`: techo 65536, base 8192, suelo 2048, según memoria libre. `test/aura_llm_context_policy_test.dart`. El POVA 5 tiene 8 GB y Android 14; el techo que elija en ese aparato no está medido. Un emulador Android 16 no cuenta. |
| Medición 8K/16K/32K/64K en hardware | C | `docs/LOCAL_AI_MODEL.md` y `docs/AI_CONTEXT_AND_MEMORY_64K.md`. No hay tokens/s, temperatura ni batería. Hay que medirlas en el POVA 5 (8 GB, Android 14), no en el Redmi ni en un emulador 16. |
| Memory Manager persistente | C | No hay almacén de preferencias, tareas y decisiones de la conversación, editable y borrable. |
| Intent Analyzer | B | El parser determinista es `lib/agent/aura_intent_parser.dart` (`test/aura_intent_parser_test.dart`). `lib/infrastructure/agent/aura_intent_parser.dart` es un adaptador con el mismo nombre de clase y otro enum. No es una copia. El LLM solo entra si la orden no se reconoce. |
| Task Planner | B | `lib/llm/local_llm_planner.dart`: una propuesta de solo lectura o un turno. No ejecuta herramientas. |
| Tool Registry | B | Allowlist y guard de ejecución. Falta el registro tipado de todas las acciones de la Parte 6. |
| Security Policy Engine | B | `lib/agent/agent_execution_guard.dart` rechaza herramientas desconocidas y exige confirmación. No cubre automatizaciones. |
| Response Generator | B | Respuesta acotada de un turno. No hay calidad ni alucinación medidas. |
| Conversation Controller | C | No hay continuidad de varios turnos ni separación temporal/persistente. |
| Personalidad | B | Textos en español, sin alarmismo en varios mensajes. No es un módulo con pruebas de “no afirma lo que no ejecutó” más allá del agente actual. |
| Modo híbrido externo | C | No hay interruptor de modelo externo, aviso de transmisión ni apagado total de esa vía. Lo local es el único camino. |
| Uso de herramientas por el modelo | B | `lib/agent/llm_tool_proposal.dart` propone; el controlador no deja que el texto del modelo ejecute solo. |

## Parte 3 — Motor de ciberdefensa

| Módulo de la spec | Estado | Evidencia o hueco |
|---|---|---|
| AuraSecurityEngine | B | `lib/security_engine.dart` consulta integridad y entorno hostil. No es el orquestador de todos los módulos de la Parte 3. |
| AuraDeviceAuditor | B | Herramienta `audit_device` y postura en Kotlin. Una auditoría vacía no se trata como dispositivo limpio (`lib/services/aura_core.dart`, `test/aura_core_test.dart`). Sigue sin ser “integral”. |
| AuraApplicationAnalyzer | B | Escaneo de apps visibles, firma y provenance. No inspecciona el código de terceros. |
| AuraPermissionAnalyzer | B | Permisos y AppOps dentro del mismo escaneo. Un permiso sensible no se etiqueta como malware por sí solo (tests de hallazgos). |
| AuraNetworkAnalyzer | B | `lib/network_auditor.dart` y `lib/services/aura_threat_correlator.dart`. Solo ve lo que el túnel y el sistema entregan. |
| AuraThreatIntelligence | B | Feed Feodo en `AuraVpnService` y `AuraUpdateWorker` / `AuraBlocklistService`. Falta ficha de procedencia, licencia, vigencia y varias fuentes. Sin red el túnel arranca igual; la reputación queda en lo ya guardado. |
| AuraPhishingDetector | B | Homógrafos, TLD y distancia en el clasificador (`test/aura_ai_inference_test.dart`). No hay motor de URL con redirecciones y certificado. |
| AuraFindingsEngine | B | Genera hallazgos deterministas de solo lectura. No deduplica un historial ni actualiza un caso ya guardado. |
| AuraRiskEvaluator | B | Gravedad y confianza separadas en `lib/security/aura_finding.dart`. No hay porcentajes inventados. Falta la metodología escrita de la spec. |
| AuraRemediationManager | C | No hay módulo que registre acción, autorización, resultado y reversión. |
| AuraSecurityHistory | C | Hay bitácora cifrada del agente y telemetría de sesión. No hay historial de hallazgos con reabrir. |
| Centro de hallazgos (resolver, buscar, filtrar) | C | La UI enseña evidencia. No resuelve, reabre ni busca. |
| Inspección del código de otras apps | D | Sin root, Android no deja leer el código ni los datos privados de otras apps. Alternativa: metadatos, permisos y origen de instalación. |
| Conducta continua de otras apps fuera de la VPN | D | Sin un servicio privilegiado no hay telemetría de red de terceros. Lo observable es el túnel mientras está activo, y aun así la atribución UID no siempre existe. |
| Revocar permisos o desinstalar sin el flujo de Android | D | Una app normal no puede revocar permisos ajenos ni desinstalar en silencio. Alternativa: abrir Ajustes o el desinstalador del sistema, y no declarar éxito antes de comprobar el estado. |

## Parte 4 — Firewall

| Módulo de la spec | Estado | Evidencia o hueco |
|---|---|---|
| Una sola VPN, sin segunda pila | A | Solo `AuraVpnService`. El README y el código rechazan otro proxy paralelo. |
| AuraFirewallEngine | C | No existe esa clase. El filtro real está repartido en SNI nativo y en el túnel. |
| AuraFirewallRulesRepository | C | No hay reglas persistentes con id, prioridad, caducidad y migración. |
| Modos Desactivado, Equilibrado, Estricto, Personalizado | C | No hay modos con reglas consultables. |
| AuraPacketFilter | B | Descarte de DNS cifrado conocido y fragmentos en `hev-socks5-tunnel.c`. Tests Python `tool/test_tun_packet_filter.py` y `tool/test_lwip_fragment_policy.py`. |
| AuraDnsFilter | B | `mapdns` y bloqueo de dominio con confirmación (`addDnsBlockRule`). Una regla no debe tragarse un sufijo ajeno: hace falta conservarlo al diseñar el motor. Hoy no hay listas personales en UI. |
| AuraDomainReputation | B | Clasificador local más feed de IPs. No es reputación multi-fuente con vigencia. |
| AuraConnectionTracker | B | Eventos de DNS/SNI por `AuraNetworkStream`. No hay tabla de flujos TCP/UDP con estado. |
| AuraFirewallLogger | B | Eventos de sesión y notificación. No hay historial de firewall resistente a reinicios. |
| AuraFirewallStatistics | B | Contadores de sesión en la consola. No salen de un motor de reglas. |
| AuraFirewallController | C | No existe. |
| Bloqueo por app entendido como “sin internet” | D | `addDisallowedApplication` solo saca a esa app del túnel; no la deja sin red. Hoy se usa para la propia app. No debe ofrecerse como firewall por app. |
| Bloquear todo DoH/DoT/ECH | D | El túnel ve el ClientHello en claro y resolutores conocidos. No ve el nombre si el cliente usa DoH propio, ECH o QUIC cifrado. Hay que documentar el límite, no prometer el bloqueo. |
| Interfaz de firewall | C | No hay pantalla de reglas, excepciones y contadores del motor. |

## Parte 5 — VPN, privacidad, SecureVault

| Tema | Estado | Evidencia o hueco |
|---|---|---|
| Arranque de la VPN | B | Código de consentimiento, integridad y establecimiento con reintento IPv4. El dueño confirmó arranque y uso en el TECNO POVA 5 el 2026-11-14, sobre commits previos a la parada de `5089d35`. |
| Parada manual y notificación Detener | B | `ACTION_STOP`, cierre de HEV, TUN, `stopForeground(STOP_FOREGROUND_REMOVE)`, `stopSelf()` y `userRequestedStop` en `AuraVpnService.kt`. En Android 14 hace falta el permiso de notificaciones y el tipo de servicio en primer plano. Sigue en B hasta verse en el POVA 5 (API 34). El APK de `5089d35` no existió. |
| Cambio Wi‑Fi/datos | B | El túnel y la etiqueta usan `UnderlyingNetworkKind.choosePhysical` sobre las redes que entrega el `NetworkCallback` (`INTERNET` + `NOT_VPN`). No se usa `allNetworks` ni `getUnderlyingNetworks`. Con el túnel activo, la etiqueta es la red pasada a `setUnderlyingNetworks`. Sin prueba en API 34. |
| Tráfico TCP, UDP, DNS, IPv4, IPv6 y fugas | C | El protocolo está escrito en `docs/ANDROID_TRAFFIC_VALIDATION.md` y sigue pendiente en ambos teléfonos. |
| Declarar cero fugas | D | Una VPN local no puede declararse libre de fugas sin medición en ese aparato y esa red. Además hay caminos de OEM (always-on, app excluida) que no son “cero” universal. |
| Telemetría apagada por defecto | A | `lib/services/aura_local_telemetry.dart`, `docs/PRIVACY.md`, `test/aura_local_telemetry_test.dart`. Si alguien configura un endpoint remoto, eso ya no es el modo por defecto. |
| No interceptar HTTPS ni instalar CA raíz | A | El túnel reenvía por SOCKS5 local. No hay instalación de certificado de usuario ni descifrado TLS en el código de la app. |
| Migración SecureVault | B | Opciones en `lib/secure_vault.dart`. `SecureStorageMigrationTest` pasó en emulador Android 16, run [43631402912](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43631402912), SHA `e5cf2fe`. Ese job se saltó cuando Kotlin no compilaba. No cuenta como prueba del POVA 5 (API 34). |
| Sobre de modelo | B | AES-256-CBC + HMAC, autenticado antes de descifrar. No es el AES-GCM que pide la spec para todo secreto. |
| Secretos fuera del repo | A | Firma por variables de entorno; `tool/test_release_signing_policy.py` y `tool/test_release_signing_runtime.py`. No hay un barrido forense de toda la historia de Git en esta auditoría. |
| Firma de prueba estable | B | Sin un keystore fijo, cada runner puede crear otro `debug.keystore` y el APK nuevo no actualiza al anterior: hay que desinstalar y se borra SecureVault. `com.ciberdefensa.aura` no cambia. Si existen `AURA_DEBUG_KEYSTORE_BASE64` y las contraseñas, GitHub Actions y CodeMagic los usan; si no, sigue el comportamiento anterior. Pasos: `docs/FASE_2_PRUEBAS_POVA5.md`. |

## Parte 6 — Acciones e incidentes

| Módulo de la spec | Estado | Evidencia o hueco |
|---|---|---|
| AuraActionEngine y compañeros (Registry, Permission, Authorization, Execution, History, Rollback, Validator) | C | No existen con ese diseño. |
| Niveles 1–3 y confirmación | B | Nivel 1 y 2 parciales: el agente explica y `CONFIRMO` caduca (`lib/agent/agent_controller.dart`). No hay automatización acotada de nivel 3. |
| Aura Incident Response | C | No hay procedimientos ejecutables para phishing, app, permiso, VPN caída o error de firewall. |
| Acciones reales ya conectadas | B | Activar/detener VPN, bloquear dominio con confirmación, auditar, abrir algunos ajustes. No hay “pedir desinstalación” ni cambio de modo de firewall. `isolate_app` solo abre Ajustes y declara `isolation_performed: false` (`lib/agent/aura_tools.dart`). |
| Aislamiento de pánico y reanudar red | B | `panic_isolation` y `resume_network` en `lib/agent/aura_tools.dart`. Exigen `confirmed_by_user` (`lib/agent/agent_execution_guard.dart`). Paran o reponen el forwarding y dejan el TUN. Tests: `test/aura_tools_test.dart`, `test/aura_intent_parser_test.dart`. Falta ver que **Detener** no deje la red cortada. Sigue en B en API 34. |
| Purga criptográfica | B | `cryptographic_purge` borra caché de modelos, SecureVault y la memoria de auditoría nativa. Exige confirmación. Tests de parser y de herramienta. Es destructiva y no tiene pantalla propia. |
| WorkManager | B | `AuraBlocklistService` y `AuraTelemetryService` programan trabajo. No cubre la lista de la spec (reglas, recordatorios, configuración). |
| Historial de acciones | B | La bitácora cifrada del agente guarda fases sin volcar argumentos secretos. No es el historial de la Parte 6. |
| Informes locales y exportación | C | El diagnóstico de crash se puede copiar. No hay informe de incidente exportable. |
| RollbackManager | C | No hay deshacer de reglas o de acciones. |
| Pagos | A | No hay SDK de facturación. Free / Premium / Advanced no están activados. La spec pide dejarlos apagados. |

## Duplicados, dependencias y rendimiento

| Par | Veredicto |
|---|---|
| `lib/agent/aura_intent_parser.dart` y `lib/infrastructure/agent/aura_intent_parser.dart` | El de `lib/agent/` es el parser (cientos de líneas, con test). El de `infrastructure/` es un adaptador con la misma clase y otro enum. No es una copia. El nombre repetido estorba. |
| `lib/ai_brain.dart` y `lib/services/ai_brain.dart` | El segundo es un envoltorio de una docena de líneas sobre `AuraAIBrain`. No duplica el modelo. |
| `com.ciberdefensa.aura` y `com.aura.cyberdefense` | Conviven a propósito (`AuraCryptoSecure`, `AuraNotificationService`). El README ya dice que no se renombran sin reconciliar Manifest, JNI y canales. |
| Dependencias | Flutter 3.47.9, JDK 17, AGP 8.13, Kotlin 2.2.20, NDK 28.2. No se vio un conflicto que impida resolver `pub get`. El fallo de compilación era una API fuera del SDK, no una dependencia incompatible. |
| Rendimiento | No hay medición de CPU, batería ni temperatura en el POVA 5. La política de contexto estima RAM; no la ha medido en API 34. |

## Issues críticos (orden de daño si se ignoran)

1. Desde `5089d35`, `main` no compilaba Kotlin (`underlyingNetworks`, fuera del SDK público). Los runs [43636981696](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43636981696) y [43645598876](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43645598876) están en rojo. `eef52b0` lo quita y el build volvió a verde en [43646707387](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43646707387). La parada y la etiqueta de red ya se pueden instalar; en el POVA 5 siguen sin probarse.
2. La parada, **Detener** y el cambio Wi‑Fi/datos siguen sin confirmarse en el TECNO POVA 5 (8 GB, Android 14, API 34). El arranque sí, en un build anterior que compilaba.
3. No hay medición de tráfico, fugas, IPv6 ni batería. Afirmar cero fugas es falso.
4. La IA local no ha generado un token en el POVA 5. 8 GB no demuestran que el GGUF cargue.
5. La Parte 4 no existe como producto. Solo hay filtro SNI/DNS parcial.
6. Los hallazgos no se persisten ni se remedian.
7. Once pull requests abiertos pueden pisar `main` si se mezclan sin rebasar.
8. CodeMagic puede firmar con debug y, si el keystore de debug es nuevo en cada runner, instalar el APK obliga a desinstalar y pierde el vault.
9. La migración SecureVault pasó en un emulador Android 16 (`e5cf2fe`) y no en el POVA 5. En los SHA que no compilaban, ese job ni siquiera arrancó.

## Qué no se debe marcar como terminado

- Firewall por app, bloqueo total de DoH/ECH/QUIC, inspección de código ajeno, desinstalación silenciosa, contexto 64K “operativo”, inferencia real, cero fugas, antivirus certificado, publicación en Play Store.
