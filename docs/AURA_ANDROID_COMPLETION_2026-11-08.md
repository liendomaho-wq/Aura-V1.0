# Aura Android: auditoría y cierre verificable — 2026-11-08

## Base y alcance antes de modificar código

- Repositorio oficial: `liendomaho-wq/Aura-V1.0`.
- Base consultada en GitHub y sincronizada mediante fast-forward: `main`, `11d50fbc6944b00496499182b3b61e92c2259a31`.
- Rama de corrección: `arena/6c919530-aura-v1-0`. No se autoriza otra integración en `main`.
- Inventario completo de la base: **712 archivos versionados**, **163 propios** y **549 de HEV y sus dependencias vendorizadas**.
- Auditoría inicial: inventario de todos los archivos; revisión de los límites Dart/Android/JNI, almacenamiento y migración, ciclo VPN/SOCKS/HEV, inferencia/exportación/datasets, agente/herramientas, permisos, servicios, escáner, UX, compilación y CI/distribución; búsqueda transversal de secretos, ejecución de procesos, comunicaciones inseguras y funciones incompletas. Una coincidencia textual no constituye una vulnerabilidad.
- Esta revisión estructural y de rutas críticas **no equivale a una certificación ni a revisar manualmente cada línea de 549 archivos vendorizados**. Quedan pendientes revisión dinámica/fuzzing nativo y aceptación en dispositivo. No se afirma ausencia de otros errores o vulnerabilidades.
- Modelo empaquetado preservado: **3.0.0**, SHA-256 `d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2`. Ninguna promoción de 3.1.0 está autorizada por el mero hecho de caber en almacenamiento.

## Hallazgos iniciales y causas

| ID | Prioridad | Evidencia y causa | Condición de cierre |
|---|---|---|---|
| VPN-01 | Alta | `AuraVpnService.shieldStatus()` combina TUN, hilo y flags. La disponibilidad SOCKS comprueba RFC1929, no respuesta de un destino en la red física. Los contadores TUN también incluyen DNS local. | Separar disponibilidad de forwarding comprobado; no anunciar protección activa sin evidencia de salida; pruebas de tráfico real y recuperación. |
| VAULT-01 | Alta | `MainActivity.authenticateWithBiometrics()` no utiliza `CryptoObject`; las claves actuales del vault no están ligadas a esa autenticación. | Vincular realmente material protegido, conservar acceso a datos antiguos y recuperación, ejecutar pruebas con Android Keystore y credenciales/biometría. Añadir un Cipher sin proteger datos no resuelve el hallazgo. |
| MODEL-01 | Alta para aceptación de IA | `train_mobile_preset()` sólo prueba `(depth=10, min_samples_leaf=512)`, pero al fallar afirma haber probado profundidad 8/poda. El candidato observado supera 4 MiB. | Reintentos reales, acotados y reproducibles; diagnóstico exacto de cada intento; calibración sólo con validación; evaluación final del modelo serializado en test independiente y gates sin relajar. |
| AUTH-01 | Media | La autenticación con credencial comparte `pendingCredentialResult` sin proteger una segunda solicitud y no la completa en `onDestroy()`. | Un único propietario de la solicitud, finalización una sola vez, cancelación/destrucción explícitas y regresiones ejecutadas. No sustituye VAULT-01. |
| JNI-01 | Media | `get_stats()` usa el resultado de `NewLongArray()` sin comprobar `NULL` antes de `SetLongArrayRegion()`. Con OOM, JNI no debe continuar con una referencia nula/excepción pendiente. | Comprobación nativa y compilación Android/JNI. La compilación no demuestra haber reproducido OOM en un teléfono. |
| CI-01 | Bloqueante de evidencia | La migración se detiene antes de arrancar Android si no existe KVM accesible. KVM acelera el emulador, pero no es Android Keystore. | Ejecutar las mismas pruebas originales en Android real, con aceleración sin privilegios si existe o emulación por software; mantener fallos y asserts. Registrar XML y API reales. |
| CI-02 | Media | Los workflows de push nombran la antigua rama `arena/063013fc-aura-v1-0`, no la rama de esta corrección. | Incluir ramas de corrección y ejecutar CI del SHA corregido. |
| DEVICE-01 | Pendiente externo | Sin Redmi Note 15 Pro Plus 5G / Android 16 conectado. El benchmark Flutter existente tiene skip de dispositivo; no hay tiempos físicos medidos. | Pruebas de tráfico TCP/UDP/IPv4/IPv6, pérdidas/handover, consumo, OEM, UI y vault en el teléfono de referencia, con evidencias. |
| RELEASE-01 | Pendiente externo | Las pruebas de firma usan claves efímeras, no una identidad de distribución. No hay compilación Codemagic verificada. | Propietario configura la identidad de firma por canal seguro y ejecuta/verifica APK/AAB de distribución y Codemagic. No pedir claves en chat ni presentar debug como distribución. |

No se detectó un escáner síncrono nuevo que justifique rehacer los executors ya presentes. ADB es informativo, no evidencia de compromiso. No se afirma descifrar ECH/DoH/QUIC ni revocar permisos de otras aplicaciones desde una app normal. Se conserva la identidad visual IA-céntrica, sin un rediseño genérico.

## Línea base ejecutada en esta rama, antes de cambios

```text
/home/user/.cache/aura-completion-venv/bin/python -m pytest -q -rs
127 passed, 8 skipped, 124 subtests passed in 8.73s
```

Las ocho omisiones corresponden a `tool/test_verify_aab.py`: `JDK and OpenSSL are required`. Son omisiones, no aprobaciones de AAB. El JRE descargado con `jdk4py` no demuestra disponer de `javac`, `keytool`, `jarsigner` y `jar`.

CI consultada de `main` (`11d50fb`): Flutter Quality `42487666661` y Release signing integrity `42487666536` terminan en success. En Android `42487666697`, el job de compilación `128752984079` termina en success; migración `128755479614` falla en `Require unprivileged emulator acceleration`, con la anotación real `This runner has no unprivileged KVM access`. Modelo `42487666564`, job `128752983868`, falla entrenando el preset móvil: un único intento depth 10 / leaf 512 / 76.255 hojas / **7.207.922 bytes**, seguido del mensaje incorrecto de profundidad 8. Se consultaron los jobs y anotaciones de estos runs, no sólo los de PR11.

## Reglas de ejecución y preservación

1. Cada cambio se liga a una causa, regresión y resultado real. Los errores de recursos no se convierten en éxito.
2. Las pruebas de migración mantienen UID `.vaultmigrationtest`, namespace aislado, proveedor Keystore del sistema y sus asserts originales. Nunca borrar/reinicializar el vault instalado para aprobar.
3. El candidato ML se guarda fuera de los assets activos; datasets, modelos rechazados e informes voluminosos siguen ignorados. No calibrar ni escoger configuraciones con el test final.
4. Mantener comprobaciones de firma, integridad y presupuestos. Cualquier gate rojo impide anunciar distribución completa.
5. No root, Shizuku, pagos, publicación en Play, ni integración adicional a main.

## Denominador de aceptación y pendientes vivos

El porcentaje de cierre se calculará como **criterios completamente demostrados / 9 × 100**, con peso igual. Un criterio parcial, omitido o pendiente aporta **0**, no medio punto. Esto mide aceptación verificada, **no porcentaje de líneas implementadas ni una estimación de madurez**.

| # | Criterio solicitado | Evidencia exigida | Estado de esta corrección |
|---|---|---|---|
| 1 | Compilación Android/JNI | Compilación del SHA corregido y artefacto identificado | Pendiente |
| 2 | Todas las pruebas automáticas | Flutter/analyze/format/Python/JVM/instrumentación/modelo sin fallos ocultos | Pendiente |
| 3 | Migración ejecutada | v9→v10 y reinicio interrumpido en Android Keystore real | Pendiente |
| 4 | VPN tráfico y recuperación | Flujo real y handover/worker/stop, sin falsos estados | Pendiente |
| 5 | IA integrada y métricas verificables | Modelo serializado evaluado en holdout, límites y gates aprobados | Pendiente |
| 6 | Sin altas/críticas sin resolver | Cerrar hallazgos y verificar regresiones, incluidos VPN-01 y VAULT-01 | Pendiente |
| 7 | Teléfono Android de referencia | Registro de ejecución física; no inferir compatibilidad | Pendiente externo |
| 8 | Firma de distribución | Identidad real, APK/AAB verificado y evidencia Codemagic | Pendiente externo |
| 9 | Documentación actualizada | Informe final coherente con SHA, archivos, pruebas y bloqueos | En curso |

Esta tabla describe la nueva corrección; los éxitos históricos no se transfieren como aprobación automática de cambios nuevos.

## Registro de correcciones y resultados

### CI-01 / CI-02 — ejecución real sin exigir KVM

- Workflows de push incluyen `arena/**`, sin habilitar publicación de releases.
- El job obligatorio de migración selecciona KVM sólo si es accesible sin privilegios. Si no existe, solicita al emulador oficial Android 16 completo ejecución por software. Se mantienen los dos tests originales, su UID, namespace, proveedor y todos sus asserts.
- El timeout de arranque es de 1.800 s; el job tiene 65 min. Un timeout o fallo sigue siendo un fallo, no un skip/éxito.
- Se exige XML no vacío con ambos casos ejecutados exactamente una vez, sin fallos/omisiones/reintentos escondidos; se conservan XML/informes reales como artefactos.
- Regresiones locales: `python -m pytest -q tool/test_secure_storage_instrumentation_policy.py tool/test_verify_android_instrumentation.py`: **23 passed**. Los XML de estas regresiones son fixtures del parser, **no resultados de Android**.
- YAML de workflows parseado y `git diff --check` aprobados. JRE local confirmado sin `javac`, `jarsigner`, `jar` ni headers JNI; no se inventa compilación Android local.
- **Actualización ejecutada:** `42491355979` / `128766339515` arrancó Android 16 completo por software y ejecutó ambos tests originales: 2 ejecutados, 0 omitidos, 1 falló. El bloqueo de ejecución por KVM se superó; la migración NO aprobó. Ver VAULT-02 abajo.

### MODEL-01 — reintentos reales con presupuesto, sin promover el candidato

- Plan fijado antes de evaluar: `(depth, min_samples_leaf) = (10,512), (8,1024), (6,2048), (4,4096)`, exactamente 500 árboles en cada entrenamiento real. Máximo cuatro intentos; ningún gate de calidad se rebaja.
- Se mide el JSON UTF-8 exacto, finito y con terminador reproducible. Los candidatos sobredimensionados se rechazan **antes** de consumir la validación. Tras calibrar únicamente con validación se vuelve a comprobar el tamaño final, estrictamente menor a **4.194.304 bytes** como antes.
- Cada intento real queda registrado inmediatamente, con profundidad, hojas, tamaño, etapa y si consumió validación. Si todos fallan, el mensaje enumera exclusivamente esos intentos; ya no inventa profundidad 8 ni poda.
- El test holdout y su conjunto adversarial no eligen configuraciones. Las métricas se calculan sobre el modelo serializado elegido, guardan SHA del candidato, script, corpus y splits, versiones Python/NumPy/scikit-learn y resultado explícito del gate.
- Nuevas regresiones verifican el plan acotado, el límite original, árbol completo de peor caso para el último fallback, serialización finita, estadísticas del modelo real 3.0.0 y separación de selección/holdout. **No son métricas de entrenamiento del dataset ni un benchmark del teléfono.**
- Suite local tras estos cambios: **155 passed, 8 skipped, 124 subtests passed in 8.79s** (`python -m pytest -q -rs`). `compileall` y `git diff --check` aprobados. Las ocho omisiones AAB locales siguen pendientes.
- **La ejecución real `42491355992` completó los intentos acotados: el candidato depth 8 / leaf 1024 cabe (3.621.963 bytes calibrados), pero su recall adversarial fue 0,0202 < 0,60 y el gate lo RECHAZÓ. No se promueve; el modelo 3.0.0, su digest y firma permanecen intactos.**


## Actualización de implementación y evidencia — código hasta `bbdb6fa`

### VAULT-02 (alta) — fallo real de preservación descubierto al ejecutar Android

- Primera falla real: run `42491355979`, job `128766339515`, `SecureStorageMigrationTest.java:74`: `expected:<v9-real-keystore-secret-preserved> but was:<null>`. Android 16 ejecutó **2/2 casos, 0 skips, 1 failure**; el caso de reinicio interrumpido pasó. Compilar el APK no había detectado esto.
- Causa verificada en el tag upstream **v10.3.4**, commit `692a374a5071c0b60939f624ede58d666b6b645c`: con `migrateWithBackup=true` se aplaza ESP, pero `canSkipMarkerlessMigration()` interpreta la ausencia de claves con prefijo en claro como instalación vacía. ESP cifra los nombres; la ruta puede devolver `null` aunque exista el secreto. Una aplicación que crea claves cuando recibe `null` queda expuesta a usar una clave nueva sobre datos antiguos.
- Corrección `0bdd79b`: runtime fijado localmente mediante `dependency_overrides`, 42 archivos de producción/metadatos con procedencia completa en `third_party/flutter_secure_storage/UPSTREAM.json`; **3 archivos Android con cambios funcionales, 3 cambios sólo de whitespace**. No hay cambios funcionales Dart del proveedor. Licencia original preservada. No se modifica la caché global de paquetes ni se depende de un parche remoto mutable.
- Se detecta ESP antes de la ruta rápida; se autentican datos antes de mutar; una conversión escribe todos los ciphertext destino y elimina sus claves ESP correspondientes en **un solo commit síncrono del mismo archivo**. La clave AES envuelta debe persistirse con commit comprobado antes. Datos corruptos o raíces legacy/current distintas producen error, conservando evidencia; una raíz igual conserva el ciphertext actual exacto. Un fallo ESP no llega a limpiar backups como si hubiera sido éxito.
- El caso puro ESP no intenta desenvolver una clave CBC adivinada. El caso con backups sigue la ruta de recuperación; no se inventan flags de backup interrumpido para hacer pasar el test.
- Los **dos tests originales y todas sus aserciones siguen byte por byte idénticos** a main: SHA-256 `049bcdd4a140d1b2d05e30c0501d9821e55a4ab592fcf9fe5662d7c907b807be`.
- `SecureStorageIntegrityTest` añade cuatro casos con Keystore/proveedor real y UID privado: tag GCM alterado sin reset de otros secretos; ESP corrupto que falla y permite reintentar tras restaurar el ciphertext exacto de prueba; conflicto legacy/current conservando ambos; recuperación con valores iguales sin rekey. **Escritos, todavía pendientes de compilación/ejecución CI de esta corrección.** No se cuentan los fixtures XML como Android.
- La normalización inicial de procedencia detectó cambios de newline innecesarios; se restauraron los bytes upstream de licencia/MasterKey/MasterKeys en vez de aflojar el control. Los hashes actuales y las diferencias exactas quedan en el manifiesto/`AURA_PATCHES.json`.
- Esto NO cierra VAULT-01: las opciones reales de la app todavía no atan sus claves a una autenticación CryptoObject. No se hace una migración irreversible de claves biométricas sin recuperación verificada.

### VPN-01 / JNI-01 — disponibilidad distinta de tráfico observado

- `55f65b8` separa `forwarding_ready` (TUN válido + worker vivo) de `forwarding_active` (además, evidencia bidireccional reciente de sockets upstream protegidos). Abrir SOCKS, aceptar RFC1929, DNS local o contadores TUN no constituye esa evidencia.
- Observación TCP mediante `TCP_INFO` real: payload recibido y ACK de datos; exclusión de loopback/direcciones propias; caducidad monotónica de 60 s. UDP conserva un conjunto acotado de peers enviados/respuestas correlacionadas. Se reinicia la evidencia por worker; no se consulta un destino externo periódico de prueba desde producción.
- Worker perdido: seguimiento cada 2 s, recuperación coalescida usando el executor existente; la ausencia de tráfico por inactividad no provoca reinicios. Notificaciones distinguen preparación, espera de tráfico y salida observada. La confirmación de inicio se correlaciona y se difiere hasta observar salida, en vez de confirmar sólo pthread/SOCKS.
- JNI: se corta al fallar NewLongArray/lookup/ref; no se siguen haciendo lookups con excepción pendiente. Se verifican recursos pthread y se publica el callback VM sólo tras inicialización completa. Generación incrementada sólo tras crear un worker real, usada para probar recuperación.
- Regresiones locales del componente: **19 casos** de C ejecutado/guards JNI; incluyen intercambio TCP real en loopback y en una dirección propia no-loopback, ambos rechazados como salida remota. Los positivos UDP de estado reciben metadatos de unidad; no prueban UDP enrutado.
- Prueba adicional ejecutada: TLS con certificado/hostname verificados a `github.com:443`, HEAD `/robots.txt` respondió 200; el C real detectó ACK/payload y luego caducó tras **60,100169 s**, sin reinicio de proceso. Informe local `tool/reports/completion/native-egress-expiry.json`. **Linux, no Android ni TUN; no cierra el gate VPN.**
- `cdf3d75` añade fixture de peers TCP/UDP IPv4/IPv6 reales y driver que preserva fallos/limpia procesos; siete pruebas de infraestructura host ejecutadas, sin sustituir Gradle. Cuatro casos Android requieren consentimiento real, sockets ligados a la VPN, nonce intacto, contadores TUN, rechazo RFC1929, generación nueva tras terminar worker, aislamiento sin fuga y stop comprobado. **Aún no ejecutados en Android.** El alias IPv6 del host `fec0::2` sigue sin validar en el emulador; su ausencia debe fallar, no omitirse.

### AUTH-01 — un propietario por solicitud, sin confundirlo con CryptoObject

- `ee81808` usa ticket por identidad compartido entre biometría/credencial; rechaza reemplazos concurrentes, callbacks obsoletos y doble finalización. La credencial usa launcher con clave única; destrucción cierra, cancela, desregistra y completa el resultado original como falso.
- Siete casos JVM añadidos, incluida carrera de ocho threads con errores propagados. **Pendientes de ejecución Kotlin/JVM CI.** No se reportan como ya aprobados ni como autorización criptográfica de material del vault.

### CI y modelo: evidencia visible sin convertir fallos en éxito

- `a5ece86` publica métricas reales compactas del candidato incluso si es rechazado y ejecuta benchmark del candidato rechazado sin llamar a eso aceptación ni rendimiento del teléfono. El gate de entrenamiento sigue rojo cuando falla calidad.
- `bbdb6fa` imprime diagnóstico por caso y hashes XML aun si otra clase falla; el verificador estricto se ejecuta igualmente y devuelve fallo. Android 16 exige **10 casos** (2 originales + 4 integridad + 4 VPN), sin skips/reintentos escondidos. API 29 añade los seis de almacenamiento, **no sustituye Android 16 ni demuestra el Redmi**.
- Metadatos APK conservan commit exacto, cuatro ELF por ABI, modelo/digest/firma comparados byte a byte y lock realmente resuelto. Se publica sólo el delta público del lock con SHA, nunca material de firma.
- El último CI completado previo a estos cambios (`f8ed1b8`) tuvo Flutter y los tres jobs de firma/SBOM positivos, APK/JNI positivo, migración 1 fallo y modelo rechazado por recall adversarial. **Esos éxitos NO aprueban código nativo/Kotlin/proveedor modificado después.**

### Pruebas locales de la corrección completa actual

```text
/home/user/.cache/aura-completion-venv/bin/python -m pytest -q -rs
193 passed, 8 skipped, 124 subtests passed in 10.40s
```

`tool/test_vpn_config_template.py`, compilación Python, YAML de workflows y `git diff --check` aprobados. Las ocho omisiones AAB siguen siendo por falta de JDK completo local; no son éxito. No hay Flutter/SDK Android local establecido. Procedencia, guards de fuente y fixtures de parser no se presentan como tests físicos. La nueva CI debe compilar y ejecutar antes de cerrar defectos/regresiones.

### Bloqueos que siguen abiertos

1. Obtener ejecución CI del código corregido (Android/JNI/JVM/Flutter y los 10 casos reales); diagnosticar/corregir el primer error real, no eliminar aserciones. Aprobar repetición normal/interrumpida más integridad antes de cerrar VAULT-02.
2. Atar material real del vault a CryptoObject y verificar acceso antiguo, cancelación, invalidación/enrollment, background y recuperación sin backup descifrable que eluda autenticación. **VAULT-01 alta abierta.**
3. Tráfico/recovery/handover/stop/consumo Android: código y pruebas nuevos todavía sin ejecución Android. Sin aceptación anticipada de IPv6, UDP o Redmi.
4. Modelo candidato rechazado: no promover 3.1.0, no rebajar gates ni reutilizar el test observado para escoger hiperparámetros. Falta revisión FP/FN independiente y calidad aprobada; 3.0.0 sigue activo.
5. Lock restante de dependencias federadas debe reflejar la resolución real de CI; se conserva evidencia reproducible para actualizarlo sin hashes inventados.
6. Dispositivo de referencia no conectado: ninguna función validada físicamente. Propietario debe proporcionar ejecución/registro del Redmi Android 16.
7. Firma de producción y Codemagic pendientes: claves de CI efímeras no son identidad de distribución. Codemagic no ofrece conector utilizable en esta sesión; propietario debe configurar/ejecutar su proyecto por canal seguro, sin claves en chat. No hay publicación ni merge nuevo en main.

Los nueve criterios conservan el denominador original y pesos iguales; ninguno parcial se redondea a completo. El cierre definitivo se actualiza con resultados reales posteriores, no con promesas de esta implementación.

### Inventario de cambios hasta el código registrado

La procedencia de cada archivo vendorizado está en su manifiesto. Lista respecto a main verificado:

```text
.github/workflows/android-debug-build.yml
.github/workflows/flutter-quality.yml
.github/workflows/model-training.yml
.github/workflows/release-signing-integrity.yml
android/app/build.gradle
android/app/src/androidTest/java/com/ciberdefensa/aura/SecureStorageIntegrityTest.java
android/app/src/androidTest/java/com/ciberdefensa/aura/VpnForwardingInstrumentationTest.java
android/app/src/main/cpp/aura_forwarding_health.c
android/app/src/main/cpp/aura_forwarding_health.h
android/app/src/main/cpp/hev-socks5-tunnel/Android.mk
android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5-misc.c
android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5-server.c
android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5-server.h
android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5-udp.c
android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5.c
android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5.h
android/app/src/main/cpp/hev-socks5-tunnel/src/hev-jni.c
android/app/src/main/java/hev/htproxy/TProxyService.java
android/app/src/main/kotlin/com/ciberdefensa/aura/AuraVpnService.kt
android/app/src/main/kotlin/com/ciberdefensa/aura/LocalAuthRequestGate.kt
android/app/src/main/kotlin/com/ciberdefensa/aura/MainActivity.kt
android/app/src/storageMigration/AndroidManifest.xml
android/app/src/storageMigration/java/com/ciberdefensa/aura/VpnInstrumentationActivity.java
android/app/src/test/kotlin/com/ciberdefensa/aura/LocalAuthRequestGateTest.kt
docs/AURA_ANDROID_COMPLETION_2026-11-08.md
pubspec.lock
pubspec.yaml
third_party/flutter_secure_storage/AURA_PATCHES.json
third_party/flutter_secure_storage/AURA_PATCHES.md
third_party/flutter_secure_storage/CHANGELOG.md
third_party/flutter_secure_storage/LICENSE
third_party/flutter_secure_storage/README.md
third_party/flutter_secure_storage/UPSTREAM.json
third_party/flutter_secure_storage/android/.gitignore
third_party/flutter_secure_storage/android/build.gradle
third_party/flutter_secure_storage/android/gradle.properties
third_party/flutter_secure_storage/android/gradle/wrapper/gradle-wrapper.properties
third_party/flutter_secure_storage/android/settings.gradle
third_party/flutter_secure_storage/android/src/main/AndroidManifest.xml
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/FlutterSecureStorage.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/FlutterSecureStorageConfig.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/FlutterSecureStoragePlugin.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/MigrationBackup.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/NamespacedConfigSource.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/SecurePreferencesCallback.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/BiometricNamespaceKeyRecovery.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/KeyCipher.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/KeyCipherAlgorithm.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/KeyCipherFunction.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/KeyCipherImplementationAES23.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/KeyCipherImplementationRSA18.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/KeyCipherImplementationRSAOAEP.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/LegacyNamespaceKeyRecovery.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/StorageCipher.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/StorageCipherAlgorithm.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/StorageCipherFactory.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/StorageCipherFunction.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/StorageCipherImplementationAES18.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/StorageCipherImplementationAES23.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/ciphers/StorageCipherImplementationGCM.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/crypto/EncryptedSharedPreferences.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/crypto/MasterKey.java
third_party/flutter_secure_storage/android/src/main/java/com/it_nomads/fluttersecurestorage/crypto/MasterKeys.java
third_party/flutter_secure_storage/lib/flutter_secure_storage.dart
third_party/flutter_secure_storage/lib/options/android_options.dart
third_party/flutter_secure_storage/lib/options/apple_options.dart
third_party/flutter_secure_storage/lib/options/ios_options.dart
third_party/flutter_secure_storage/lib/options/linux_options.dart
third_party/flutter_secure_storage/lib/options/macos_options.dart
third_party/flutter_secure_storage/lib/options/web_options.dart
third_party/flutter_secure_storage/lib/options/windows_options.dart
third_party/flutter_secure_storage/pubspec.yaml
tool/run_android_vpn_instrumentation.py
tool/test_forwarding_health_native.py
tool/test_mobile_budget.py
tool/test_secure_storage_instrumentation_policy.py
tool/test_secure_storage_vendor.py
tool/test_verify_android_instrumentation.py
tool/test_vpn_config_template.py
tool/test_vpn_echo_fixture.py
tool/test_vpn_instrumentation_driver.py
tool/train_max_aura_brain.py
tool/verify_android_instrumentation.py
tool/vpn_echo_fixture.py
```
