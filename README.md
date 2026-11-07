# Aura Mobile Defens — documentación técnica y guía de continuidad

> **Documento de traspaso para una IA o desarrollador que continúe el proyecto.**  
> Última revisión documental: **2026-11-06**. Rama objetivo: `main`.
> «Defens» es la ortografía intencional del producto; no corregir. Reporta vulnerabilidades según [SECURITY.md](SECURITY.md).

## 1. Resumen ejecutivo y estado real

Aura Mobile Defens es una aplicación Android de ciberdefensa local, desarrollada con Flutter/Dart y componentes nativos Kotlin, C/JNI. Está diseñada para funcionar **sin root**. La interfaz gira alrededor de un agente local y un avatar; el producto no debe convertirse en un dashboard genérico con escudos o radares.

**Estado del producto: EN DESARROLLO — no declarar terminado ni certificado.** El repositorio contiene capacidades reales de análisis del dispositivo, inventario limitado de aplicaciones, clasificación local de dominios, auditoría de eventos de red y un servicio VPN Android opcional. Sin embargo, la cobertura de red es parcial, el agente conversacional es determinista y heurístico (no un LLM generativo completo), y aún se necesitan pruebas en dispositivos físicos y validación del pipeline en el commit de entrega.

La app no garantiza protección integral, no sustituye Play Protect ni un producto EDR, y no puede inspeccionar libremente otras aplicaciones debido al sandbox y las restricciones de Android. Toda respuesta de seguridad debe diferenciar entre **acción solicitada**, **acción aceptada por Android/motor**, **evento observado** y **resultado verificado**.

### Estado resumido

| Área | Lo que existe en el código | Lo que NO debe afirmarse |
|---|---|---|
| Interfaz | Flutter, consola conversacional, avatar Aura, estados visuales y accesibilidad/reducción de movimiento. | No afirmar que la experiencia visual final está validada en todos los tamaños/dispositivos. |
| Agente IA | `AgentController`, parser de intenciones, respuestas locales, `AuraTools`, timeouts por herramienta, postcondiciones y bitácora cifrada. | No es un LLM generativo ni razona libremente como ChatGPT; algunas llamadas nativas no se pueden cancelar al vencer el timeout. |
| Modelo de dominios | Bosque de decisión local; modelo JSON 3.0.0, 500 árboles, seis características históricas; verificación SHA-256/firma antes de instalar modelo. | No analiza contenido de páginas, archivos ni comportamiento completo del sitio. Una clasificación no garantiza que un dominio sea seguro o malicioso. |
| Seguridad Android | Auditorías heurísticas de root/emulador/instrumentación/overlays; escáner de apps, permisos, servicios, firmas y señales de ofuscación. | No detecta todo malware, no puede ver todos los paquetes/estados y no aísla arbitrariamente otras apps. |
| Red/VPN | `VpnService`, túnel TUN/HEV, rutas IPv4/IPv6, filtros DNS selectivos y parser SNI conectado al flujo TCP del TUN con reensamblado del ClientHello. | No es un firewall universal. SNI/ECH/QUIC, DoH y el comportamiento en hardware real aún requieren validación exhaustiva; ECH no se descifra. |
| Privacidad | Telemetría local opt-in; telemetría remota opcional con consentimiento y endpoint HTTPS; los dominios se representan con HMAC-SHA-256 usando una clave de SecureVault. Revocar consentimiento elimina colas locales/remotas. | Los HMAC son seudónimos, no anonimización absoluta: el servidor ve la IP de conexión y los datos correlacionables siguen siendo sensibles. |
| Release | Script de compilación/verificación y workflow Codemagic con `apksigner` en modo estricto. El workflow actual configura fallback DEBUG con advertencia visible para pruebas. | Con `AURA_REQUIRE_RELEASE_SIGNING=false`, el artefacto es DEBUG y no debe distribuirse. La firma de producción real sigue pendiente. |
| Calidad | Pruebas Flutter/Dart, pruebas Python y workflows GitHub Actions/Codemagic definidos. | No afirmar que todos los tests/builds pasan en el estado actual sin un run verde del commit exacto. |

## 2. Arquitectura y flujo de datos

```text
Android / Kotlin
  MainActivity + MethodChannels
    ├─ biometría, notificaciones, estado de seguridad y auditoría del dispositivo
    ├─ AuraAppGenomeScanner / AuraBlocklistService / AuraTelemetryService
    └─ AuraVpnService (VpnService) → TUN → HEV SOCKS5 tunnel (C/JNI)
                                      └─ filtro selectivo DNS / eventos de red
                                                │ EventChannel
                                                ▼
Flutter / Dart
  AuraCoreScreen → AuraNetworkAuditor → AuraAIBrain → AuraAIInference (isolate)
        │                 │                  └─ modelo JSON local validado
        │                 └─ AuraStateProvider / bitácora local
        └─ AgentController → AuraIntentParser → AuraTools → canales nativos
```

Componentes principales:

- `lib/main.dart`: punto de entrada Flutter.
- `lib/screens/aura_core_screen.dart`: consola principal, avatar, estados, auditoría, explicaciones y controles.
- `lib/screens/splash_screen.dart`: splash y autenticación.
- `lib/agent/agent_controller.dart`: controlador de conversación, intenciones, historial y coordinación de acciones.
- `lib/agent/aura_intent_parser.dart`: parser determinista de órdenes.
- `lib/agent/aura_tools.dart`: herramientas/acciones locales; valida argumentos y comunica resultados.
- `lib/ai_brain.dart`, `lib/services/ai_brain.dart`, `lib/models/aura_ai_brain.dart`: núcleo de carga/modelo (hay namespaces/implementaciones heredadas; revisar referencias antes de refactorizar).
- `lib/inference/aura_ai_inference.dart`: extracción de características e inferencia del bosque.
- `lib/network_auditor.dart`: recepción y coordinación de eventos de red.
- `lib/providers/aura_state_provider.dart`: estado observable, telemetría y explicaciones.
- `lib/services/aura_local_telemetry.dart`: persistencia/consentimiento de telemetría.
- `lib/voice_engine.dart`: voz/TTS.
- `lib/theme/aura_tokens.dart`: tokens visuales.
- `android/app/src/main/kotlin/com/ciberdefensa/aura/MainActivity.kt`: puente Android/Flutter y funciones nativas.
- `android/app/src/main/kotlin/com/ciberdefensa/aura/AuraVpnService.kt`: servicio VPN.
- `android/app/src/main/kotlin/com/ciberdefensa/aura/AuraAppGenomeScanner.kt`: inventario y análisis heurístico de apps.
- `android/app/src/main/kotlin/com/ciberdefensa/aura/AuraHostileEnvironment.kt`: señales del entorno hostil.
- `android/app/src/main/kotlin/com/ciberdefensa/aura/AuraBlocklistService.kt`: feeds/blocklist.
- `android/app/src/main/kotlin/com/ciberdefensa/aura/AuraNetworkStream.kt`: eventos nativos de red.
- `android/app/src/main/kotlin/com/ciberdefensa/aura/AuraTelemetryService.kt`: telemetría.
- `android/app/src/main/cpp/aura_sni_firewall.c/.h`: parser SNI conectado al flujo de sesiones TCP del túnel; requiere validación exhaustiva en dispositivos.
- `android/app/src/main/cpp/hev-socks5-tunnel/`: motor de túnel C de terceros.
- `assets/model/aura_brain_model.json`, `.sha256`, `.sig`: modelo móvil y material de integridad.

Conviven dos namespaces Kotlin por legado: `com.aura.cyberdefense` y `com.ciberdefensa.aura`. No unificarlos sin revisar Manifest, JNI, nombres de canales y llamadas Dart.

## 3. IA: capacidades, límites y trabajo pendiente

La IA actual es un **agente local basado en reglas + herramientas + clasificador ML**. `AgentController` contiene respuestas deterministas para intenciones como saludo, identidad, capacidades y seguridad. `AuraIntentParser` reconoce órdenes predefinidas. `AuraTools` ejecuta operaciones específicas mediante Dart y canales nativos. El bosque de decisión clasifica nombres de dominio; no es el cerebro conversacional generativo.

La arquitectura de ejecución ya aplica límites de tiempo por herramienta, comprobación de postcondiciones antes de declarar éxito y una bitácora cifrada de inicio/cierre en SecureVault. La bitácora no guarda valores de argumentos y una falla al persistir el inicio impide despachar la herramienta. El timeout no detiene necesariamente una llamada nativa que ya comenzó; en ese caso el resultado se informa como desconocido y requiere comprobar el estado.

Acciones/herramientas presentes en el código (la disponibilidad real depende de permisos, estado y respuesta nativa):

- `audit_device`: consulta señales de root, emulador, instrumentación, overlay y accesibilidad expuestas por Android. Los errores deben dar estado incompleto.
- `scan_apps`: consulta apps/servicios/accesos especiales, firmas y heurísticas. El inventario depende de visibilidad Android.
- `analyze_domain`: valida el host y ejecuta el modelo local si está disponible e íntegro.
- `update_defenses`: solicita actualización de defensas/feeds según configuración.
- Revisión de app: abre Ajustes Android para revisión humana; no desinstala ni deshabilita apps.
- Bloqueo DNS: solicita una regla local; el flujo conversacional requiere confirmación explícita.
- Aislamiento de emergencia/purga/activar o desactivar defensas: requieren confirmación explícita en segundo paso.

**Pendiente real de IA:** el LLM generativo sigue pendiente. La allowlist de herramientas, los límites de argumentos, las confirmaciones, los timeouts, las postcondiciones y el Audit Log ya forman parte del agente. Aún falta completar cancelación cooperativa y progreso granular para escaneos nativos largos, además de evaluar si un LLM local o remoto es viable. Cualquier modelo futuro debe permanecer separado de las herramientas privilegiadas: nunca ejecutar comandos arbitrarios, código, shell ni operaciones no registradas. No simular respuestas de IA ni mostrar “acción completada” si solo se envió una solicitud.

## 4. Modelo ML y datos

- Asset activo documentado: modelo `3.0.0`, bosque de 500 árboles y seis características históricas.
- SHA-256 documentado del JSON 3.0.0: `d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2`.
- El cliente descarga JSON, sidecar SHA-256 y firma; valida antes de instalar/cifrar el modelo. Ante fallo de integridad no debe aceptar el modelo nuevo.
- Existe un contrato de vector mejorado de 18 características sincronizado entre Python y Dart para el **candidato 3.1.0**, pero el modelo móvil 3.0.0 usa únicamente las seis primeras. No cambiar el vector del modelo activo sin entrenar, evaluar y versionar un modelo compatible.
- Las características auxiliares que no pertenecen al vector de seis campos no deben presentarse como causa de la predicción.

Contrato de extracción compartido por `tool/train_max_aura_brain.py` y `AuraAIInference`:

| # | Característica | Alcance |
|---:|---|---|
| 1 | `length` | Longitud total del host normalizado. |
| 2 | `shannon_entropy` | Entropía de Shannon de los caracteres del host. |
| 3 | `digit_ratio` | Proporción de dígitos ASCII. |
| 4 | `vowel_ratio` | Proporción de vocales sobre letras ASCII. |
| 5 | `consonant_sequence_ratio` | Proporción de letras en secuencias de tres o más consonantes. |
| 6 | `suspicious_tld` | Indicador de TLD incluido en la lista léxica de sospecha. |
| 7 | `min_normalized_levenshtein` | Distancia de edición mínima normalizada frente a dominios comunes. |
| 8 | `bigram_repeat_ratio` | Proporción de bigramas repetidos. |
| 9 | `trigram_repeat_ratio` | Proporción de trigramas repetidos. |
| 10 | `subdomain_depth` | Profundidad de subdominios normalizada. |
| 11 | `tld_length_ratio` | Longitud del TLD normalizada. |
| 12 | `idn_homograph_indicator` | Señal acotada de caracteres cirílicos confundibles. |
| 13 | `non_ascii_ratio` | Proporción de caracteres no ASCII. |
| 14 | `consecutive_digits_indicator` | Indicador de dígitos consecutivos. |
| 15 | `conditional_entropy` | Entropía ponderada de etiquetas normalizada. |
| 16 | `rare_character_ratio` | Proporción de letras poco frecuentes definidas por el extractor. |
| 17 | `longest_label_length_ratio` | Longitud de la etiqueta más larga normalizada. |
| 18 | `suspicious_keyword_indicator` | Indicador de palabras clave léxicas de sospecha. |

Estas señales describen el nombre de dominio, no el contenido del sitio. Las doce últimas solo se usan en inferencia cuando el modelo declara exactamente el orden completo de 18 campos.
- El pipeline de datos está en `tool/dataset/`; entrenador en `tool/train_max_aura_brain.py`; benchmark en `tool/bench_aura_brain.py`; pruebas en `tool/test_aura_brain.py`.
- Las fuentes, licencias, splits y métricas deben ser reproducibles y versionados como artefactos apropiados. No usar datasets sintéticos/seed-only para afirmar métricas holdout.
- Model Card: [docs/model_card.md](docs/model_card.md). Modelo y documentación pública: [GitHub Pages](https://yojamm16-boop.github.io/Aura-V1.0/model-card.md) (comprobar que la publicación corresponde al commit actual).

El README anterior registraba para el modelo 3.0.0 un test holdout de 72,703 filas y una matriz `[[13381, 1606], [13916, 43800]]`; esas cifras son históricas/documentales y deben comprobarse contra el artefacto y el pipeline vigente antes de reutilizarlas en material de producto.

## 5. Protección de red: alcance exacto y advertencias

La VPN es parte de `main` actualmente. Android solicita consentimiento del sistema para el `VpnService`; el servicio crea TUN y coordina el motor HEV. El parser SNI ya está conectado al callback de recepción TCP de las sesiones TUN: acumula los segmentos hasta completar el ClientHello y puede abortar la conexión cuando una regla SNI activa bloquea el host. Esto demuestra integración de código y pruebas nativas/unitarias, no validación exhaustiva de tráfico en equipos reales. El filtrado de ingreso descrito en el README anterior descarta TCP/853, UDP/853 y UDP/443 solo cuando el destino coincide con una lista fija de resolutores DoH conocidos.

Limitaciones confirmadas en el código/documentación revisados:

1. DoH sobre TCP/443 no queda bloqueado de forma general; la lista de resolutores es selectiva.
2. UDP/443 no equivale a bloquear todo QUIC/HTTP3: el filtrado descrito depende del destino conocido.
3. El parser SNI está conectado al flujo TUN para TCP y reensambla el ClientHello; una regla bloqueada aborta la sesión y reporta el evento. Falta validación exhaustiva en hardware real, especialmente IPv6, fragmentación/reordenamiento, QUIC y ECH. ECH solo se reconoce como contenido cifrado: no se descifra ni se conoce el hostname oculto. No anunciar inspección SNI dentro de QUIC ni bloqueo general de ECH.
4. La detección de IP directa tampoco está demostrada como conectada al camino de paquetes.
5. El firewall es userspace/TUN; no usa iptables/ip6tables y no tiene privilegios de sistema para hacerlo.
6. Cambios de red, revocación de permiso VPN, fugas IPv4/IPv6, DNS, fragmentación, suspensión, batería, reconexión y compatibilidad OEM requieren pruebas en dispositivos reales.
7. Los contadores/eventos solo significan lo que confirme el motor. No presentar un contador como paquetes descartados si no hay confirmación del motor.

**Decisión de continuidad:** no borrar ni fusionar código VPN a ciegas. El usuario ha expresado frustración con esta parte y pidió eliminar restos que no sean útiles, pero la rama principal aún depende de ella en servicios, UI, herramientas, manifest, tests y scripts. Antes de retirarla, hacer inventario de dependencias y decidir formalmente si Aura conservará VPN opcional o pasará a una arquitectura sin VPN. Si se conserva, corregir y probar el ciclo de vida del túnel; si se elimina, retirar de forma coherente todos los consumidores y actualizar documentación/pruebas. No ocultar el botón dejando servicios huérfanos.

### PR de reconstrucción VPN

Existe una PR abierta de reconstrucción: [PR #4](https://github.com/liendomaho-wq/Aura-V1.0/pull/4), cuya rama de trabajo es `rebuild/vpn-from-zero`. **No está aprobada para merge.** En revisión se encontró que `AuraLocalSocks5Proxy.stop()` apagaba el executor sin recrearlo, lo que rompía un ciclo stop/start sobre la misma instancia. Se corrigió en la rama de la PR mediante recreación del pool al reiniciar y manejo de `RejectedExecutionException` al competir el cierre con una aceptación de socket (commit [a0a6e26](https://github.com/liendomaho-wq/Aura-V1.0/commit/a0a6e265a63fc7defb136b8dfbd96237243930e0)). **La corrección aún no está integrada en `main` ni tiene CI verde verificado.** La rama de la PR está divergida respecto de `main` (22 commits por delante y 237 por detrás en la última comparación); no fusionarla directamente. Reconciliar los cambios sobre el `main` actual y ejecutar pruebas antes de cualquier merge.

## 6. Seguridad Android, permisos y privacidad

Manifest observado incluye, entre otros: `INTERNET`, `ACCESS_NETWORK_STATE`, `QUERY_ALL_PACKAGES`, `RECORD_AUDIO`, `POST_NOTIFICATIONS`, `USE_BIOMETRIC`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, y declara `AuraVpnService` con `BIND_VPN_SERVICE`.

- `QUERY_ALL_PACKAGES` tiene restricciones de Google Play. Mantenerlo solo con justificación válida y evaluar una alternativa de visibilidad limitada.
- El reconocimiento de voz usa el proveedor disponible en Android; el repositorio no demuestra que el audio permanezca local. No prometer procesamiento de voz 100% offline.
- El escáner de apps ofrece señales heurísticas, no análisis dinámico ni descompilación completa.
- Los indicadores root/emulador/Frida/debugger/overlay pueden tener falsos positivos y falsos negativos.
- `allowBackup=false` y `usesCleartextTraffic=false` están configurados en el Manifest revisado.
- Telemetría local opt-in. El modo remoto exige endpoint HTTPS y consentimiento; los dominios se representan con HMAC-SHA-256 con clave protegida. Son identificadores seudónimos, no anonimización irreversible.
- Mantener secretos fuera del repositorio, logs, APK y README. Las claves públicas pueden estar versionadas; keystores, contraseñas y claves privadas nunca.

Documentos de entrega:

- [Política de privacidad basada en el comportamiento del código](docs/PRIVACY.md).
- [Guía de release, firma y validación en dispositivo](docs/RELEASE_AND_DEVICE_VALIDATION.md).

## 7. Build, versiones y CI/CD

Configuración observada en `pubspec.yaml`:

- Paquete Dart: `aura_mobile_defens`.
- Versión: `1.0.2+3`.
- SDK Dart: `>=3.12.0 <4.0.0`; Flutter declarado `>=3.44.0`.
- Android applicationId documentado: `com.ciberdefensa.aura`.
- El README previo documentaba compile/target SDK 36 y NDK `28.2.13676358`; verificar Gradle antes de actualizar versiones.
- Codemagic: workflow `android-build`, Flutter stable, Java 17, cachés Pub/Gradle, `flutter pub get`, `flutter analyze --no-pub`, pruebas Python de configuración VPN y firewall SNI, `flutter test --reporter expanded`, `bash tool/compile_aura.sh` y `bash tool/compile_aura.sh --verify-artifact`.
- Artefactos esperados: `build/app/outputs/flutter-apk/*.apk`, `build/app/outputs/bundle/release/*.aab`, `pubspec.lock`.

Comandos locales:

```bash
flutter --version
flutter pub get
flutter analyze
python3 tool/test_vpn_config_template.py
python3 tool/test_aura_sni_firewall.py
flutter test --reporter expanded
bash tool/compile_aura.sh
bash tool/compile_aura.sh --verify-artifact
```

Con `AURA_REQUIRE_RELEASE_SIGNING=true`, Codemagic invoca `tool/compile_aura.sh --verify-artifact`: para APK utiliza `apksigner`, rechaza firmantes múltiples o DEBUG y exige que el certificado coincida con el keystore configurado. Para AAB verifica la firma JAR de cada entrada de contenido contra el certificado de carga; falta validarlo con un bundle Android real. El workflow configura por defecto `AURA_REQUIRE_RELEASE_SIGNING=false`, fuerza el fallback DEBUG y omite la verificación estricta de producción; ese artefacto es solo para pruebas y no debe distribuirse. Para release real se debe activar explícitamente el modo de producción en el workflow y configurar `AURA_KEYSTORE_PATH` o `AURA_KEYSTORE_BASE64`, `AURA_STORE_PASSWORD`, `AURA_KEY_ALIAS`, `AURA_KEY_PASSWORD` y la clave pública que valida el modelo incluido. La firma de producción real sigue pendiente de validación.

### Estado de pruebas conocido

- En el estado local del 2026-11-06, `flutter test --reporter expanded` pasó con 172 tests y 1 omitido por requerir dispositivo. Es un resultado local, no evidencia de CI ni de validación física.
- Se añadieron tests Robolectric de migración v9→v10 con ESP legacy real y recuperación de backup interrumpido, pero no se pudieron ejecutar en este contenedor: falta Android SDK y Gradle falla al resolver `dev.flutter.flutter-plugin-loader` con el valor `25.0.4.1`.
- El usuario informó en conversaciones recientes que CodeMagic volvió a compilar con éxito. Ese resultado es un reporte del usuario; para certificarlo se necesita el enlace/log del run y su commit SHA.
- En un log anterior (30-10-2026) se informó un timeout al descargar Flutter stable 3.47.9 para macOS ARM64: curl error 28 tras 300 segundos, descarga parcial de ~961 MB de ~2.26 GB.
- En el run de CodeMagic compartido el **2026-11-05**, el paso `Run Aura security regression checks and Flutter tests` terminó con código 1. La prueba fallida identificada al final del log fue `test/aura_transparency_ui_test.dart` — `muestra explicación, marca localmente y abre auditoría`. El log muestra una advertencia de hit-test al buscar el texto `Reportar falso positivo` y, en el fallo final, una aserción `Expected: true / Actual: <false>` en la línea 175: el estado de reporte local no quedó activado durante la prueba.
- Para hacer la interacción determinista, en `lib/screens/aura_core_screen.dart` se añadió la clave estable `report-false-positive-${explanation.id}` al botón; la prueba ahora localiza el botón por `ValueKey('report-false-positive-verdict-1')`, lo hace visible y lo pulsa directamente. Cambio guardado en `main` mediante commit [`f0e6c32`](https://github.com/liendomaho-wq/Aura-V1.0/commit/f0e6c32cae1d8df2aa9c1d02c44ed4b990401c16), precedido por [`a2613af`](https://github.com/liendomaho-wq/Aura-V1.0/commit/a2613afa17d49d7ccc8806fbc458767b9b01fb93).
- **Estado de esa corrección: pendiente de verificación.** Aún no hay evidencia de un run verde de CodeMagic sobre `f0e6c32`; no afirmar que la prueba está corregida hasta ejecutar el workflow de nuevo. El log mostrado también lista muchas pruebas repetidas de `aura_core_screen_test.dart`, pero no las identifica como fallidas en el resumen final de ese run. En logs previos también se mencionaron pruebas de splash/auth. Ejecutar la suite completa en el commit actual.
- `test/aura_core_screen_test.dart` todavía prueba el canal `com.ciberdefensa.aura/shield`, el toggle VPN y la revocación del túnel. La prueba de transparencia usa canales mockeados y datos sintéticos para validar UI/estado local; no demuestra que la inspección de red real funcione.
- Los tests de benchmark de dispositivo están omitidos por defecto; las métricas de runner Linux no representan rendimiento Android.
- No hay porcentaje de cobertura medido y publicado.

GitHub Actions incluye workflows de calidad Flutter, build Android debug, integridad/firma, entrenamiento de modelo y despliegue de model pages. Revisar `.github/workflows/` y el estado de Actions en el SHA exacto; un workflow existente no es evidencia de éxito.

### Actualización de interfaz y prueba de transparencia — 2026-11-05

- Se añadió una `ValueKey` estable al botón de reporte de falso positivo para evitar que la prueba dependa de localizar el texto interior del botón.
- La prueba de transparencia ahora pulsa el control identificado por clave y conserva la comprobación del estado local.
- Commits en `main`: [`a2613af`](https://github.com/liendomaho-wq/Aura-V1.0/commit/a2613afa17d49d7ccc8806fbc458767b9b01fb93) y [`f0e6c32`](https://github.com/liendomaho-wq/Aura-V1.0/commit/f0e6c32cae1d8df2aa9c1d02c44ed4b990401c16).
- **No validado todavía:** falta repetir CodeMagic en este HEAD y confirmar que `muestra explicación, marca localmente y abre auditoría` pasa. Si vuelve a fallar, inspeccionar el callback/proveedor que persiste `reportedFalsePositive`; no debilitar la aserción ni convertir el fallo en un éxito simulado.

## 8. Prioridades para la IA/desarrollador que continúe

Trabajar en este orden y **no marcar una fase como terminada sin evidencia reproducible**:

1. **Auditoría de estado:** clonar `main`, leer este README, `SECURITY.md`, `pubspec.yaml`, `codemagic.yaml`, Gradle, Manifest, workflows y tests. Obtener SHA actual, branches, PRs y runs. No basarse en documentación vieja o una conversación aislada.
2. **Estabilización:** ejecutar análisis, suite completa, pruebas Python y build. Reproducir fallos con logs; arreglar la causa, no silenciar tests ni reducir aserciones.
3. **Red/VPN:** la integración del parser SNI con el flujo TCP del TUN y el reensamblado del ClientHello están implementados. Avanzar con validación exhaustiva IPv4/IPv6, fragmentación, RST, ECH, QUIC y DoH en hardware real; decidir formalmente si mantener la VPN opcional. Resolver PR #4 solo si corresponde y después de pruebas de ciclo de vida, fugas, reconexión y revocación. No mezclar refactor grande con cambios visuales.
4. **Auditoría Android:** comprobar permisos/runtime API, notificaciones, biometría, accesibilidad, inventario de apps, lifecycle y comportamiento sin permisos. Reportar límites por API/OEM.
5. **IA agéntica:** allowlist, límites de argumentos, autorización/confirmación, timeouts, postcondiciones y Audit Log están implementados. Completar cancelación cooperativa/progreso de trabajo nativo y validar los límites en dispositivos. El LLM generativo sigue pendiente; si se añade, mantenerlo separado de herramientas privilegiadas y sin ejecución arbitraria.
6. **UI/avatar:** completar coherencia visual y accesibilidad sin convertir la app en dashboard/radar/escudo. Medir rendimiento y respetar reduced motion.
7. **Release:** el control `apksigner` rechaza certificados DEBUG cuando `AURA_REQUIRE_RELEASE_SIGNING=true`. Codemagic está temporalmente en fallback DEBUG con advertencia; recuperar credenciales, activar el modo estricto y verificar firma de producción, build reproducible, SBOM/provenance y APK/AAB antes de distribuir. Nunca distribuir DEBUG.
8. **Prueba física:** registrar modelo del teléfono, versión Android/API, versión APK, SHA-256 APK, signer fingerprint, permisos concedidos, estado VPN y pasos/resultados de cada caso. La validación en dispositivo real debe cerrar los riesgos que CI no puede probar.

### Matriz mínima de pruebas físicas

- Instalación limpia, actualización desde versión anterior y desinstalación.
- Primer inicio, biometría disponible/no disponible, credencial del dispositivo y dispositivo sin bloqueo seguro.
- Permisos concedidos, denegados y revocados (micrófono, notificaciones, VPN).
- Activar/detener VPN, revocar consentimiento desde Ajustes, reiniciar app/teléfono y cambiar Wi-Fi ↔ datos móviles.
- DNS normal, DoT/853, DoQ/853, DoH por UDP/443 hacia resolutor conocido y DoH por TCP/443; registrar qué se bloquea realmente.
- IPv4 e IPv6, QUIC/HTTP3, ECH y conexión directa por IP; verificar con capturas/servidores de prueba controlados, no inferir a partir de la UI.
- Pérdida de red, reconexión, suspensión/reanudación, batería y estabilidad del servicio.
- Auditoría de dispositivo y escáner de apps con permisos/visibilidad limitados.
- Análisis de dominio benigno, malicioso de laboratorio y dominio no disponible; verificar explicación y que no haya falsos mensajes de éxito.
- Telemetría local y remota: opt-in/opt-out, cola, cancelación, ausencia de endpoint y revisión de datos transmitidos.
- Rendimiento, temperatura, memoria, consumo de batería, TalkBack, tamaños de fuente y reduced motion.

## Fase 2 del agente ejecutor — avance 2026-11-05

- El parser rechaza órdenes ejecutables concatenadas o incrustadas en texto separado por delimitadores habituales de feeds/citas; el comportamiento es fail-closed.
- Se añadieron pruebas de regresión para prompt injection en texto de indicadores y confirmaciones incrustadas.
- Los límites de ejecución por herramienta, resultados desconocidos al vencer el timeout, postcondiciones y bitácora cifrada ya están implementados. La Fase 2 sigue abierta: falta cancelar cooperativamente el escaneo APK/DEX desde Android, emitir progreso nativo granular y completar el planificador con checkpoints/recuperación. El timeout Dart no detiene por sí solo un escaneo Kotlin ya iniciado.
- No declarar esta fase cerrada hasta ejecutar flutter analyze, flutter test y build Android en CodeMagic sobre el commit actual.

## Endurecimiento del agente inteligente — 2026-11-05

Se inició la Fase 1 del endurecimiento del agente en la rama `main`.

### Controles implementados en código

- Política central de allowlist: solo se despachan los diez nombres de herramientas definidos por Aura.
- Validación estricta de argumentos por herramienta, límites de profundidad/tamaño, validación DNS y validación de identificadores de paquetes.
- Confirmación explícita obligatoria para operaciones que cambian el estado del dispositivo o la red.
- Confirmación en dos pasos, de un solo uso y con caducidad de 60 segundos: `CONFIRMO` repite exactamente la orden pendiente; cualquier otra instrucción invalida la autorización pendiente.
- Límite de entrada de 2.048 caracteres y rechazo de órdenes simultáneas.
- Token de cancelación con una frontera explícita: se permite cancelar antes de iniciar una herramienta; no se finge abortar una llamada nativa ya iniciada.
- Plazos máximos por herramienta. Si vence el plazo, el resultado se marca como desconocido y no se reintenta automáticamente, porque la operación subyacente podría seguir ejecutándose.
- Postcondición obligatoria: cada herramienta debe devolver `ok` booleano; la ausencia de un resultado verificable nunca se marca como éxito.
- Correlación de operaciones mediante identificador local y reducción de datos de argumentos registrados en eventos.
- Bitácora de operaciones cifrada en SecureVault: el registro de inicio se persiste antes de despachar una herramienta; si falla, la operación no comienza. El cierre registra éxito/error y no guarda valores de argumentos. La purga criptográfica elimina también esta bitácora.
- Errores del límite de ejecución con códigos estables, evitando exponer mensajes internos o rutas del dispositivo.

### Estado de validación

El endurecimiento de herramientas está avanzado e incluye timeout, postcondiciones y Audit Log. La validación debe corresponder al SHA actual y completarse en CI. Los límites de tiempo de Dart no detienen por sí solos una llamada nativa ya iniciada; en ese caso Aura informa que el resultado es desconocido y exige comprobar el estado.

## Privacidad y almacenamiento — avance 2026-11-06

- SecureVault conserva `resetOnError=false` y la migración v9→v10 con AES-GCM/backup. Se añadió una prueba Robolectric que siembra preferencias ESP v9 y las lee con el plugin v10, incluida la recuperación desde backup iniciado; su ejecución queda pendiente de resolver el entorno Android/Gradle.
- Las claves usadas por las rutas de cifrado se exponen como buffers temporales y se ponen a cero en `finally`; las claves derivadas/ciphertext también se limpian donde corresponde. Las cadenas inmutables de Dart no pueden sobrescribirse explícitamente en memoria.
- La telemetría local y remota usa HMAC-SHA-256 con una clave protegida en SecureVault; los registros históricos locales con dominios en claro se transforman al cargarse. Revocar consentimiento limpia colas y evita nuevos envíos/registros.
- Los logs auditados ya no imprimen dominios bloqueados, destinos SOCKS ni credenciales SOCKS. Las pruebas Flutter cubren revocación, HMAC local, migración de logs heredados y zeroing de buffers.

## 9. Reglas de trabajo para otra IA

- El usuario es titular o cuenta con autorización para desarrollar este repositorio. Rama de destino requerida: **`main`**, porque Codemagic compila desde ella.
- Hacer cambios concretos y pequeños, con commits descriptivos y pruebas. Antes de escribir, comprobar SHA y contenido actual; nunca sobrescribir cambios nuevos.
- No fusionar ramas/PR antiguas sin comparar base, head, commits, archivos y CI.
- No borrar VPN ni sus dependencias solo para hacer pasar una prueba. Si se decide retirarla, actualizar conjuntamente Kotlin, Java, C/JNI, Manifest, Gradle, Dart, AgentController, UI, canales, scripts, tests y documentación.
- No reemplazar pruebas fallidas por tests más débiles ni usar mocks como evidencia de integración física.
- No declarar que la IA es generativa, que SNI inspecciona tráfico, que QUIC/DoH está bloqueado globalmente o que el dispositivo está protegido al 100%.
- No afirmar “compiló”, “está corregido”, “commit realizado” o “APK generado” sin el resultado correspondiente.
- Mantener cambios en español cuando sean textos de UI/documentación orientados al usuario; nombres de código en inglés según convenciones existentes.
- Respetar la licencia propietaria del repositorio y sus atribuciones de terceros.

## 10. Entrega y criterios de cierre de Aura

Aura solo puede marcarse como lista cuando: (a) alcance funcional y límites estén definidos; (b) no existan herramientas/UI que prometan acciones inexistentes; (c) análisis estático, tests, scripts de seguridad y build estén verdes en el SHA de entrega; (d) APK esté firmado con el certificado de producción si se distribuirá; (e) la matriz de pruebas físicas se haya ejecutado y los fallos críticos resueltos; (f) documentación, Model Card y permisos reflejen el comportamiento real.

**No se promete “máxima protección” ni “100% de seguridad”:** el objetivo responsable es la mejor protección técnicamente alcanzable dentro de las APIs públicas de Android, con límites visibles, comportamiento verificable y consentimiento del usuario. Aún faltan pruebas en dispositivos físicos del flujo TUN/SNI (incluidos IPv6, QUIC y ECH) y verificar la aplicación con la firma de producción real antes de cualquier distribución.

---

## Referencias del repositorio

- Código: [liendomaho-wq/Aura-V1.0](https://github.com/liendomaho-wq/Aura-V1.0)
- Rama principal: [main](https://github.com/liendomaho-wq/Aura-V1.0/tree/main)
- Pipeline Codemagic: [codemagic.yaml](codemagic.yaml)
- Modelo: [assets/model](assets/model/)
- Model Card: [docs/model_card.md](docs/model_card.md)
- Seguridad: [SECURITY.md](SECURITY.md)
- PR de reconstrucción VPN pendiente de revisión: [#4](https://github.com/liendomaho-wq/Aura-V1.0/pull/4)
