# Aura Mobile Defens

Aplicación Android de ciberdefensa local con Flutter/Dart, Kotlin y C/JNI.
Funciona como una app normal, **sin root, Shizuku ni Superuser**. «Defens» es la
ortografía intencional del producto.

**En desarrollo; no certificada ni lista para release.** La implementación, una
prueba unitaria y una función verificada en un teléfono son evidencias distintas.
El estado de validación, los SHA, fallos y enlaces de CI pertenecen a
[AURA_FINAL_AUDIT.md](AURA_FINAL_AUDIT.md), no a este README.

La experiencia aprobada conserva el tema oscuro, cian/violeta, consola y avatar
con la IA protagonista. Este trabajo no rediseña la interfaz ni incorpora
publicación, monetización o cambios de distribución.

## Producto y alcance

| Componente | Capacidad implementada | Límites |
|---|---|---|
| Agente local | Parser de intenciones por reglas, herramientas permitidas, confirmaciones, plazos y postcondiciones. | **No es un LLM** ni un agente generativo de propósito general. Un timeout Dart no cancela necesariamente un trabajo nativo. |
| Clasificador ML | Bosque local de dominios, modelo activo **3.0.0**, seis características. | No inspecciona páginas ni archivos; una clasificación no garantiza seguridad. |
| Auditoría Android | Inventario visible, permisos concedidos, servicios habilitados, firma, provenance y estados AppOps accesibles. | Visibilidad y APIs de una app normal; no puede aislar, desinstalar ni vigilar arbitrariamente otras apps. |
| VPN opcional | VpnService → TUN → HEV; rutas IPv4/IPv6, SOCKS5 autenticado y filtros DNS/SNI selectivos. | Arranque local no demuestra tráfico extremo a extremo ni ausencia de fugas. ECH, DoH personalizado y QUIC no se descifran. |
| Privacidad | Telemetría opt-in, HMAC de dominios y almacenamiento protegido. | Seudonimización, no anonimización absoluta; un servidor puede observar la IP de conexión. |

Aura no sustituye un EDR ni garantiza protección universal. Los resultados deben
distinguir **solicitud**, **aceptación por Android/motor**, **evento observado** y
**postcondición verificada**. Una señal heurística no es un incidente confirmado.

## Arquitectura

```text
Consola Flutter / avatar
  ├─ AgentController → AuraIntentParser → AuraTools → MethodChannels
  ├─ AuraStateProvider / explicaciones / bitácora cifrada
  └─ AuraNetworkAuditor → AuraAIBrain → inferencia local en isolate
                                      └─ modelo validado

Android: MainActivity / servicios / inventario / biometría
  └─ AuraVpnService → TUN → cliente HEV → listener HEV SOCKS5 local
                         C/JNI           RFC 1929 + salida física protegida
                           └─ filtros DNS/SNI → EventChannel → Flutter
```

Rutas principales:

- `lib/agent/`: controlador, validación de herramientas y guard de ejecución.
- `lib/infrastructure/agent/aura_intent_parser.dart`: parser por reglas;
  `lib/agent/aura_intent_parser.dart` conserva el acceso de compatibilidad.
- `lib/ai_brain.dart`, `lib/models/aura_ai_brain.dart`, `lib/inference/`:
  carga, integridad, contrato de características e inferencia.
- `lib/providers/aura_state_provider.dart`, `lib/network_auditor.dart` y
  `lib/services/aura_local_telemetry.dart`: estado, eventos y consentimiento.
- `lib/secure_vault.dart`, `lib/crypto/aura_crypto_layer.dart`,
  `lib/secure_memory.dart`: persistencia, formatos criptográficos y buffers.
- `android/app/src/main/kotlin/com/ciberdefensa/aura/`: puente, VPN, escáner,
  `VpnLifecycleGate`, `VpnStartRequestGate` y `VpnRecoveryGate`.
- `android/app/src/main/cpp/`: integración HEV, JNI y filtros de paquetes/SNI.

Conviven namespaces nativos `com.ciberdefensa.aura` y `com.aura.cyberdefense` por
compatibilidad. No renombrarlos sin reconciliar Manifest, JNI y canales Dart.

### Agente, reglas, heurísticas y ML no son lo mismo

El parser reconoce órdenes y el controlador selecciona herramientas conocidas.
Las operaciones que cambian el estado requieren la confirmación prevista, de un
solo uso y con caducidad; las entradas no confiables no deben autorizar acciones.
La bitácora cifra inicio/cierre sin guardar los valores de argumentos. Si no se
puede persistir el inicio, no se despacha la herramienta. Un resultado desconocido
no debe convertirse en éxito ni reintentarse automáticamente como si fuera inocuo.

Las reglas DNS/IP/SNI son políticas concretas; las señales de root, emulación,
instrumentación y riesgo de apps son heurísticas; el bosque de dominios es ML.
Ninguno convierte al parser conversacional en un LLM.

### Modelo activo

- Asset: `assets/model/aura_brain_model.json`, versión **3.0.0**, 500 árboles.
- Características: `length`, `shannon_entropy`, `digit_ratio`, `vowel_ratio`,
  `consonant_sequence_ratio`, `suspicious_tld`.
- SHA-256 del JSON: `d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2`.
- Se conservan digest y firma RSA separados del modelo.

El contrato de 18 características y el candidato **3.1.0** no sustituyen al
modelo móvil activo. No promocionar un candidato sin dataset verificable,
licencias, separación por grupos sin contaminación, evaluación independiente,
métricas reproducibles y revisión de falsos positivos/negativos. Los tests golden,
fixtures y benchmarks no son métricas holdout de producción. Véanse
[Model Card](docs/model_card.md), `tool/dataset/`, `tool/train_max_aura_brain.py` y
`tool/bench_aura_brain.py`.

### Contrato de características del extractor

El orden compartido por Python y Dart es parte del contrato de ingeniería.
**Solo los campos 1–6 alimentan el modelo activo 3.0.0**; los campos 7–18
pertenecen al contrato candidato, no son una promoción del modelo ni causas
adicionales de su predicción actual.

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

Las señales describen el nombre del dominio, no el contenido del sitio. Las doce
últimas solo pueden usarse para inferencia si un modelo evaluado declara el
orden completo de 18 campos. No alterar el vector de 3.0.0 para acomodar al candidato.

### Red y recuperación

El listener Android es `127.0.0.1:18763`. Usa usuario `aura` y contraseña aleatoria
efímera de 256 bits, compartida mediante el YAML privado con el cliente HEV. No
hay una contraseña de producción fija. El listener exige RFC 1929, limita las
sesiones y aplica timeout por espera de E/S del handshake, no un deadline global.
El servicio exige worker nativo vivo y handshake autenticado antes de informar
arranque local; eso **no prueba** que un paquete del TUN alcance Internet.

La pérdida de red debe detener forwarding conservando las rutas completas del
TUN. La recuperación reutiliza una interfaz válida, respeta el aislamiento de
pánico y el cierre de ciclo de vida, y correlaciona el resultado con el requestId.
Un flag Kotlin por sí solo no demuestra un worker vivo. La autenticación y el
reinicio efectivo tras fallo necesitan también la prueba física descrita en
[el protocolo de tráfico real](docs/ANDROID_TRAFFIC_VALIDATION.md).

La inspección SNI observa ClientHello visible; no descifra TLS/ECH. Las reglas de
puertos/resolvedores conocidos no bloquean todo DoH ni inspeccionan QUIC/HTTP3.
La fragmentación y los casos no inspeccionables tienen políticas conservadoras
que pueden afectar compatibilidad. Esta VPN es local, no un servicio de anonimato.

### Datos, integridad y biometría

- SecureVault conserva la migración **v9→v10**, backup de migración y
  `resetOnError=false`; no borrar datos ante corrupción para aparentar recuperación.
  El almacenamiento v10 usa RSA-OAEP para envolver claves y AES-GCM para valores.
- El formato histórico de modelo cifrado **v2** usa **AES-256-CBC + HMAC**, no
  AES-GCM. Se autentica el sobre antes de descifrar, también en la ruta JNI.
  El JSON empaquetado usa SHA-256 y firma RSA; no es ese sobre cifrado.
- Los buffers mutables se limpian donde lo permite el runtime. No se garantiza
  borrado de copias inmutables, cachés del SO o almacenamiento físico.
- `adbEnabled` es informativo y `adbBlocked=false` conserva el contrato con Dart.
  La depuración USB no debe apagar la VPN. Firma, depurador adjunto en release e
  instrumentación son comprobaciones de cliente **esquivables, no un límite de
  seguridad**.
- `BiometricPrompt` no usa `CryptoObject`: actualmente es una puerta de UI, no
  vinculación criptográfica a cada descifrado. No cambiar ese contrato sin diseño
  autorizado y migración que preserve datos.

La aplicación declara inventario amplio (`QUERY_ALL_PACKAGES`), audio,
notificaciones, biometría, red y foreground services. El consentimiento y las
restricciones de Android siguen siendo obligatorios. Denegar un permiso no debe
inventar resultados. Políticas: [privacidad](docs/PRIVACY.md) y
[seguridad](SECURITY.md).

## Ingeniería y compilación

| Herramienta/plataforma | Contrato del proyecto |
|---|---|
| Dart / Flutter | Dart `>=3.12.0 <4.0.0`, Flutter `>=3.44.0`; los workflows seleccionan stable. |
| Java / Gradle / AGP | JDK 17 / Wrapper 8.14.3 / AGP 8.13.0. |
| Kotlin | 2.2.20, JVM target 17. |
| Android | minSdk 24, compileSdk 36, targetSdk 36 (Android 16). |
| NDK | `28.2.13676358`, `ndk-build`; alineación de páginas de 16 KiB configurada. |
| ABIs declaradas | `armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64`. |

Son requisitos/configuración, **no una certificación de todos los teléfonos**.
La referencia física es Redmi Note 15 Pro Plus 5G, 8 GB, Android 16. Compatibilidad
real depende del OEM, permisos, ABI, red y pruebas en cada versión relevante.

En una estación con la toolchain completa, sin secretos de producción:

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze --no-pub
flutter test --no-pub
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r tool/requirements-train.txt
python -m pytest -q -rs
# Exige Java, javac y OpenSSL; no aceptar ocho pruebas omitidas en CI:
python tool/test_verify_aab.py
(cd android && AURA_ALLOW_DEBUG_SIGNING=true ./gradlew :app:testDebugUnitTest --no-daemon)
AURA_ALLOW_DEBUG_SIGNING=true flutter build apk --debug
sha256sum build/app/outputs/flutter-apk/app-debug.apk
```

`AURA_ALLOW_DEBUG_SIGNING=true` se limita a comandos de prueba: Gradle configura
el tipo release incluso para tests/debug. **No autoriza distribuir con esa firma.**
Para producción, `tool/compile_aura.sh` requiere la configuración estricta de
firma y validación del modelo; las claves solo se configuran en el almacén seguro
del proveedor, nunca en chat, Git ni logs. Consultar la
[guía de release y dispositivo](docs/RELEASE_AND_DEVICE_VALIDATION.md).

### CI/CD y evidencias

- **Aura Flutter Quality**: dependencias, formato, guards, suite Python con JDK
  para AAB, análisis y tests Flutter. Conserva el código de salida real.
- **Aura Android Debug Build**: SDK/NDK declarados, tests JVM, compilación APK
  Kotlin/C/JNI; publica APK y metadatos de SHA/digest solo si el build termina.
- Ambos tienen `workflow_dispatch`, PRs hacia `main`/`principal` y push en las ramas
  configuradas; validan el SHA head, no un commit de merge sintético.
- `codemagic.yaml`, workflow **`android-build`**: JDK 17, Flutter stable, runner
  `mac_mini_m2`. Los patrones `main`/`principal` tienen `source: false` para PRs a
  esas ramas. Por defecto genera un artefacto **DEBUG de prueba, no distribuible**
  (`AURA_REQUIRE_RELEASE_SIGNING=false`). Configuración no equivale a build real.
- El pipeline ML genera candidatos e informes, no promociona automáticamente el
  modelo activo. No relajar sus umbrales para obtener verde.

Mantener SDK, caches, datasets, secretos y artefactos grandes fuera de Git;
`tool/reports/` está ignorado para informes locales. La evidencia física sigue
[ANDROID_TRAFFIC_VALIDATION.md](docs/ANDROID_TRAFFIC_VALIDATION.md). Los resultados
exactos y bloqueos están en [la auditoría interna](AURA_FINAL_AUDIT.md).

## Licencia y contribuciones

Código propietario; consultar [LICENSE](LICENSE) y respetar las atribuciones de
componentes de terceros. Los cambios deben preservar datos y formatos, aportar
pruebas sin debilitar aserciones y no atribuir funciones o métricas no verificadas.
No integrar una segunda implementación de proxy sin reconciliar autenticación,
framing, recursos, JNI y rutas del túnel existente.
