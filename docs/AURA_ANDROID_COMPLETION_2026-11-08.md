# Aura Android: auditoría y cierre verificable — 2026-11-08

## Resumen al corte — guardas de alias `6511cc8`; último APK aprobado `6310f96`

**Aura no está terminada ni autorizada para distribución.** La implementación real de CryptoObject del vault continúa técnicamente pendiente; no es sólo una falta de teléfono. El candidato IA sigue rechazado. Todavía no hay tráfico TUN Android aprobado.

- Código publicado sólo en `arena/6c919530-aura-v1-0`; main verificado `11d50fbc6944b00496499182b3b61e92c2259a31`. **779 archivos versionados / 90 distintos respecto a main**; inventario completo abajo. Modelo activo 3.0.0 y los dos tests originales conservan sus bytes exactos.
- Último CI Flutter completado, `6310f96` / [42501520041](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42501520041): **SUCCESS**, **228 Python + 124 subtests, sin skips**; **194 Flutter / 1 skip de dispositivo**; analyze limpio; **67 archivos / 0 cambios** en formato. Incluye los ocho AAB reales, que localmente siguen omitidos por falta de JDK completo. La nueva revisión de código `6511cc8` tiene CI en curso [42503076338](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42503076338); no hereda aprobación de código modificado.
- Último build Android completado, `6310f96` / [42501520072](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42501520072), job `128795093082`: **SUCCESS**, **26 JVM / 0 fallos/errores/skips**, APK cuatro ABI e instrumentación compilados, lock sin delta y modelo/digest/firma idénticos al checkout. APK debug SHA-256 **`e2ae757ec7206131f0cf60b5dfc1f74c8aede255527ffa62e2695666beb43fa9`**. Artefacto `13626355547`, ZIP SHA-256 **`9e5e62531c1115cb030bb0b1dd77ba7b32a84bd60858e22d8eddd4af81fc369e`**, 86.026.468 bytes; metadatos consultados, no se afirma descarga/verificación local del ZIP. Nuevo build de `6511cc8`: [42503076393](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42503076393), pendiente al corte.
- API29 de `a3e9b2d` ejecutó **7 casos / 0 skips / 1 fallo**: los dos originales y los cuatro casos anteriores de integridad **pasaron**, incluido el cross-check Tink corregido. Sólo falló el test adicional de alias: asumía erróneamente que RSA-OAEP y AES comparten alias. Se corrige con **RSA18/PKCS1** en `6511cc8`, sin quitar ningún assert; se añade una sexta regresión que exige preservar también el SecretKey y ciphertext frente al reemplazo inverso AES→RSA. Los dos guardas necesitan ejecución nueva: **13 casos API36 / 8 API29**.
- API29 de `6310f96` / `128796939231` terminó **FAILURE sin casos reales**: preflight API29/ABI/framework correcto, después DDMLib `PropertyFetcher` falló y Gradle reportó `Unknown API Level` / `No compatible devices connected`. No es fallo probado del proveedor ni del nuevo test. API36 de `a3e9b2d` y `6310f96` seguía en curso al corte. La ampliación acotada del timeout DDMLib y el stack XML API29 son cambios de diagnóstico/setup, nunca aceptación ni reintento.
- Modelo de `6310f96`, [42501520093](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42501520093): **FAILURE / candidato rechazado**, recall adversarial **0,020236 < 0,60**; benchmark/golden/upload sí terminaron. SHA del candidato **`3e9f1ef3a5086d926ea04f7259adb72fb4e59411cf931652138e31102f880826`**, manifiesto de dataset **`2e821c762bdac4916d170121eddd58f4587b88cc8352713ae60667791f9e9882`**. Nada de 3.1.0 fue promovido/firmado. No se sustituyen estos hashes por los de `a3e9b2d` ni se atribuye su benchmark a esta ejecución.
- Linux real: cierre TCP sin payload `[ACK2,RX1,segsOut0,segsIn0]` no activa egress; TLS verificado sí y caduca a **60,100436 s**. **No es TUN/Android/Redmi**. RSA18 y AES comparten `PluginKey`; RSA-OAEP usa `PluginKeyOAEP` y no presenta esa colisión.
- Suite local de `6511cc8`: **221 passed, 8 skipped, 124 subtests / 10.94s**. Los ocho skips son AAB por falta de JDK completo, no fallos escondidos. Firma CI completada `42498431877` es efímera, **no identidad de distribución**. Teléfono de referencia/Codemagic no verificados.

Los registros siguientes son cronológicos y están ligados a su SHA. Sus resultados anteriores no aprueban código o pruebas modificados después. No se presenta un porcentaje final mientras las lanes obligatorias de la revisión actual no hayan concluido; pendiente/parcial sigue aportando cero al denominador de nueve.

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

| # | Criterio solicitado | Evidencia exigida | Estado al corte |
|---|---|---|---|
| 1 | Compilación Android/JNI | APK del código corregido, cuatro ABI y artefacto identificado | **Aprobado sólo `6310f96`**, build `128795093082`; nueva revisión `6511cc8` pendiente |
| 2 | Todas las pruebas automáticas | Flutter/analyze/format/Python/JVM/instrumentación/modelo sin fallos ocultos | **No aprobado**: Flutter/Python/JVM actuales positivos pero device skip, instrumentación pendiente/fallida y modelo rechazado |
| 3 | Migración ejecutada | Dos originales con Android Keystore real, sin sustituirlos | Originales aprobados API29/API36 de `1195e46` y API29 de `a3e9b2d`; revisión actual pendiente |
| 4 | VPN tráfico y recuperación | TCP/UDP/v4/v6 TUN real, handover/worker/stop, sin falsos estados | **No aprobado**: Android previo falló antes del TUN, cinco casos actuales pendientes; handover/Redmi no probados |
| 5 | IA integrada y métricas verificables | Modelo serializado, holdout y gates aprobados | **No aprobado**: candidato cabe pero recall adversarial 0,0202; revisión por dominio FP/FN pendiente; activo 3.0.0 intacto |
| 6 | Sin altas/críticas sin resolver | Cerrar y verificar hallazgos, incluido vault autorizado criptográficamente | **No aprobado**: VAULT-01 sigue abierta; correcciones nativas/proveedor requieren aceptación dinámica completa |
| 7 | Teléfono Android de referencia | Registro físico, rendimiento/consumo/OEM; no inferir compatibilidad | **Pendiente externo**, ninguna función validada en Redmi Note15 Pro Plus 5G / Android16 |
| 8 | Firma de distribución | Identidad real, APK/AAB verificado y Codemagic | **Pendiente externo**; firma CI efímera no cuenta |
| 9 | Documentación actualizada | SHA, todos los archivos, resultados/fallos y bloqueos coherentes | **Actualizada al corte**, no una certificación de producto ni aprobación de lanes pendientes |

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
- Corrección `0bdd79b`: runtime fijado localmente mediante `dependency_overrides`, inicialmente 42 archivos (el helper SDK omitido se restauró después en `1195e46`, total actual 43) con procedencia completa en `third_party/flutter_secure_storage/UPSTREAM.json`; **3 archivos Android con cambios funcionales, 3 cambios sólo de whitespace**. No hay cambios funcionales Dart del proveedor. Licencia original preservada. No se modifica la caché global de paquetes ni se depende de un parche remoto mutable.
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

1. Completar la CI actual: API36 exige los **13 casos** y API29 los ocho de almacenamiento. Diagnosticar el primer error real; nunca borrar originales, suavizar guards de seguridad ni convertir omisiones en éxito. Repetir el cross-check de integridad contra AndroidX/Tink y el alias RSA intacto.
2. **VAULT-01: implementación técnica pendiente**, no sólo hardware. Atar material real a CryptoObject con alias distinto, preservar datos anteriores y verificar cancelación, invalidación/enrollment, background y recuperación sin una copia descifrable que eluda autenticación. La serialización de prompts y rechazar un alias destructivo no lo resuelven.
3. Tráfico Android: validar el consentimiento en UI realmente visible; ejecutar TUN TCP/UDP/IPv4/IPv6, worker/reanudación/stop y SYN/FIN sin falso active. Handover real y consumo siguen sin prueba. No presentar Linux ni fixture host como Android.
4. IA: candidato rechazado, no promover 3.1.0, no bajar gates ni ajustar usando el test observado. Falta revisión FP/FN por dominio independiente y calidad aprobada; 3.0.0 sigue activo. El adversarial es sintético/disjunto, no un feed de incidentes confirmados.
5. Dispositivo de referencia no conectado: **ninguna función validada físicamente**. Hace falta ejecución/registro del Redmi Android16, incluido CPU/RAM/batería y restricciones OEM.
6. Firma de producción y Codemagic: configurar/verificar por canal seguro del propietario. CI efímera no es identidad de distribución; no se piden claves en chat. Sin nueva integración a main ni publicación.

El lock federado **ya no es un bloqueo abierto**: se incorporó la resolución pública real y el siguiente build emitió delta vacío, SHA-256 `9958a5fa02a610e113d4be0c3061e9c6eee2667a39af066c60aa22ef8c80bb99`. La toolchain y las firmas completas aún no se declaran herméticamente reproducibles.

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
third_party/flutter_secure_storage/lib/test/test_flutter_secure_storage_platform.dart
third_party/flutter_secure_storage/pubspec.yaml
tool/bench_aura_brain.py
tool/run_android_vpn_instrumentation.py
tool/test_android_runtime_ready.py
tool/test_aura_brain.py
tool/test_forwarding_health_native.py
tool/test_mobile_budget.py
tool/test_secure_storage_instrumentation_policy.py
tool/test_secure_storage_vendor.py
tool/test_verify_android_instrumentation.py
tool/test_vpn_config_template.py
tool/test_vpn_consent_policy.py
tool/test_vpn_echo_fixture.py
tool/test_vpn_instrumentation_driver.py
tool/train_max_aura_brain.py
tool/verify_android_instrumentation.py
tool/verify_android_runtime_ready.py
tool/vpn_echo_fixture.py
```


### Primer error de CI del proveedor fijado y corrección de completitud SDK

- `f64d1db`, Flutter `42496260438` / `128779157011`: **201 Python + 124 subtests, sin skips**, 8 AAB reales aprobadas y Dart format **66 archivos / 0 cambios**. Static analysis falló con `uri_does_not_exist` en `flutter_secure_storage.dart:7` y `undefined_method` en `:399`.
- Causa: al seleccionar runtime se omitió el helper de compatibilidad publicado `lib/test/test_flutter_secure_storage_platform.dart`, pero la librería de producción lo importa. Se restaura **exactamente desde el mismo commit upstream** y se comprueba su hash y el inventario completo Dart. No se deshabilita analyze ni se elimina la API.
- Ese helper original del SDK no es un mock inventado por Aura ni evidencia Android; ninguna prueba de migración lo usa. Los tests reales siguen con Keystore del sistema y todos sus asserts. Se requiere nueva CI del SHA con esta reparación; los tests Flutter aún no llegaron a ejecutarse en el run fallido.


## Evidencia posterior y regresiones adicionales — código `b2eb802` / `db91722` / `1315929`

### CI real de `1195e46`, sin transferirla al código cambiado después

- Flutter `42496511614` / `128779903086` **SUCCESS**: `dart format` **67 archivos / 0 cambios**; analyze **sin issues**; Python **202 passed + 124 subtests, sin skips**; los **8 AAB reales** ejecutados/aprobados. Flutter **194 tests passed, 1 skipped** (benchmark que requiere dispositivo; sigue sin aprobación física).
- Android `42496511706` / build `128779903412` **SUCCESS**: **26 JVM, 0 failures/errors/skips**, incluidas **7 LocalAuthRequestGate**; APKs de instrumentación compilados; 4 ELF HEV de ABI correcta empaquetados; modelo/digest/firma idénticos al checkout. APK debug SHA-256 **`ab628fcfde335df43dbea3820efe7e1435c3ad2f283db42f395fc48ed1b7c162`**. No es firma de distribución.
- Los jobs reales Android 16 `128781731430` y API 29 arrancaron después del build; su resultado final aún no se conoce en esta actualización. Compilar los APKs instrumentados NO aprueba Keystore/tráfico.
- `f64d1db` tuvo firma/SBOM CI **SUCCESS** (`42496260415`); modelo `42496260496` fue **cancelado** al llegar otra corrección, no aprobado ni evaluado completamente. La concurrencia del modelo pasa a agruparse por SHA, igual que Android, para que futuras correcciones no cancelen una evaluación distinta ya en curso. No se cambia ningún gate ni se evita el trigger.

### VPN-02 — SYN/FIN contados como payload: reproducción real y corrección

- Probe Linux real a `github.com:443`, **sin enviar TLS ni payload de aplicación**, observando primero el peer conectado y después el FIN: `bytes_acked=2`, `bytes_received=1`, `data_segs_out=0`, `data_segs_in=0`. El C anterior devolvió evidencia **true**. Es un falso positivo; la prueba anterior que sólo observaba después de cerrar no lo había encontrado porque `getpeername()` ya fallaba.
- `b2eb802`: se exigen segmentos TCP de datos en ambas direcciones, además de ACK/payload y avance real de los contadores de segmentos. FIN/control sin datos no renueva evidencia vieja. Si un kernel devuelve TCP_INFO demasiado corto, se mantiene sin confirmar; no se inventa compatibilidad de kernels antiguos.
- **27 casos locales** del componente C/guards, incluidos ocho inputs unitarios del predicado TCP; dichos inputs son unidad, no tráfico Android.
- Repetición real tras compilar C con GCC/Werror: el mismo cierre control-only queda **false**; TLS con certificado/hostname verificados + HEAD real 200 da `[714,1439,3,3]` y evidencia **true**; después de **60,100436 s** caduca a **false**. Informe `tool/reports/completion/native-egress-after-fin-fix.json`, con SHA exacto del C/header compilados. **Esto no es TUN/Android/Redmi.** Requiere repetir CI nativa del código nuevo.

### VAULT-03 — impedir destrucción del alias RSA al solicitar AES

- Auditoría del runtime publicado: `KeyCipherImplementationAES23.ensureSymmetricKeyAtAlias()` borraba un PrivateKey RSA existente y generaba AES en el mismo alias. Los backups del ciphertext no recuperan una clave privada destruida.
- `db91722` sustituye ese borrado implícito por un error explícito. Exigir un algoritmo distinto no autoriza rekey/reset ni borrar el alias que protege datos anteriores. Se añade un quinto caso real de integridad: certificado/PrivateKey intactos, ciphertext intacto y secreto descifrado desde una **instancia nueva**, sin valerse de la clave cacheada.
- La ruta normal actual de Aura sigue RSA-OAEP/AES-GCM; no se habilita a ciegas una migración biométrica. CryptoObject real requiere alias distinto, autorización criptográfica y recuperación verificada. **VAULT-01 sigue abierta**, y la nueva regresión del alias aún espera Android.
- Manifiesto del proveedor: **43 archivos, 4 cambios Android funcionales y 3 de whitespace**; helper publicado intacto para compatibilidad. Android 16 exige ahora **11 casos** (2 migración originales + 5 integridad + 4 VPN); API 29 añade los siete de almacenamiento, sin sustituir la aceptación Android 16.

### Lock resuelto realmente, sin hashes/versiones inventados

- `1315929` aplica el delta público del lock emitido por el job Android `128779903412`, con verificación del SHA-256 completo **`9958a5fa02a610e113d4be0c3061e9c6eee2667a39af066c60aa22ef8c80bb99`**. Se actualizan las dependencias federadas reales de v10, se elimina macOS antiguo y se conserva el runtime Android corregido por path. No se descarga un artefacto desde un host prohibido ni se inventa la resolución local.
- El build siguiente debe resolver sin deriva; el lock real se sigue guardando junto al APK. El problema del lock v9 vs declaración v10 queda corregido; la reproducibilidad completa de toolchain/firmas no se infiere de este único dato.

### Suite local más reciente

`python -m pytest -q -rs`: **203 passed, 8 skipped, 124 subtests passed in 11.03s**. Los ocho skips siguen siendo sólo AAB por falta de JDK completo local; CI `1195e46` sí ejecutó sus ocho casos, pero el código nuevo necesita su propia CI. Guards, procedencia y diff-check aprobados; modelo activo y fixture original de migración siguen intactos. Ningún éxito anterior se transfiere a los cambios nuevos sin repetir la verificación pertinente.


### Primera ejecución de `2a196dc`: fallo real de compilación del test, no Keystore

- Flutter `42497569413` **SUCCESS** y firma CI `42497569402` **tres jobs SUCCESS**. El build Android `42497569423` / `128783129310` ejecutó otra vez **26 JVM, 0 fallos/skips**, pero **FAILURE** al compilar el APK instrumentado: el nuevo test importaba `KeyCipherImplementationAES23`, clase package-private publicada por el SDK. No llegó a ejecutar Android ni a producir el APK final de esa lane.
- Se corrige **sólo el test** para invocar el `StorageCipherFactory.getCurrentKeyCipher()` público real, que construye el mismo provider contra el mismo alias. No se expone una clase privada, no hay reflexión/mock, no se elimina la regresión y no se suprime el compilador. Necesita una nueva CI real.
- También se reprodujo y quitó `NameError: name 'setoo' is not defined` al importar el benchmark: una expresión basura ya presente en main, situada después del `SystemExit` del CLI. No cambiaba el benchmark CLI, pero impedía importarlo/validarlo. Dos tests de importación/estadística cubren la corrección. El benchmark CI mantiene **10.000 warm / 500 cold** y ahora expone su salida real con `ci_run`, incluso si el candidato es rechazado.

### Evaluación completa real de `1195e46`: candidato explícitamente rechazado

Modelo `42496511684` / `128779981812`: **FAILURE exit 2**, por gate de calidad real; benchmark y golden tests **SUCCESS** y artefacto de rechazo preservado. SHA candidato **`15a15e151ae1e8c3ca038b41712ca483980ec78e0569953a34112e0397ba8dac`**; manifiesto de datos **`051a73cdaf9e4e1cceb6c7190801b26bf017d0be66c8115a71fabd13a4cd6e33`**.

- Bosque calibrado **500 árboles / 3.621.963 bytes / depth 8 / leaf mínimo 1024 / umbral 0,52**. El primer ensayo depth10/leaf512 fue 7.207.921 bytes y no se seleccionó.
- Holdout **88.219** (14.899 safe / 73.320 threat): TN **14.139**, FP **760**, FN **12.323**, TP **60.997**; accuracy **0,8516986**, precision **0,9876937**, recall **0,8319285**, FPR **0,0510101**.
- Holdout adversarial **sintético y disjunto**, **1.186** (593 / 593): TN **582**, FP **11**, FN **581**, TP **12**; recall **0,0202361**, FPR **0,0185497**. Rechazado por recall **0,0202 < 0,60**, sin bajar el gate ni ajustar usando ese holdout. Estas cifras agregadas no sustituyen una revisión independiente por dominio de FP/FN.
- Runtime de esa evaluación: Python **3.11.18**, NumPy **2.4.6**, scikit-learn **1.9.1**. No son métricas del modelo activo 3.0.0 ni de un teléfono. No se promueve/firma 3.1.0. La evaluación de `2a196dc` sigue en curso; no se asume su resultado.


### Extensión de la regresión SYN/FIN al TUN real, sin inyectar salud

Se añade `controlOnlyTcpDoesNotActivateForwarding`: socket ligado a Network VPN, cero writes de aplicación, conexión mantenida 2 s para observar el peer antes de cerrar, EOF real, cinco segundos sin evidencia activa, generación constante/worker vivo y contadores TUN TX/RX crecientes. No llama al observador privado ni simula TCP_INFO, y fallará si la fixture/ruta real no funciona. El verificador Android 16 exige ahora **12 casos** (2 originales + 5 integridad + 5 VPN); API29 sigue exigiendo los siete de almacenamiento. Su ejecución sigue pendiente; la prueba Linux ejecutada no se presenta como ese resultado.

CI del código `dcead91`: Flutter `42498290214` / `128785294949` **SUCCESS**: **214 Python + 124 subtests, sin skips; 8 AAB reales OK; 194 Flutter / 1 skip de dispositivo; analyze sin issues; formato 67 archivos / 0 cambios; pub get sin cambios de lock**. Firma de ese mismo SHA solicitada por workflow_dispatch (`42498431877`), resultado aún pendiente. Local antes de esta extensión: **206 passed, 8 skipped, 124 subtests in 11.09s**. Es evidencia de `dcead91`, no aprobación anticipada de la nueva prueba Android.

Nota de alcance de migración: el segundo test original construye el estado persistido de backup `started` y un backup parcial en el UID aislado, y arranca el proveedor real. No mata un proceso Android en mitad de un commit; aprobarlo prueba recuperación de ese estado, no todos los puntos posibles de crash ni un corte de energía físico. Ambos originales permanecen byte-identical.


### Primer resultado de integridad en API29 y corrección de contrato de excepción

`1195e46` / `42496511706` / `128781731365`: Android 10 real ejecutó **6 casos / 0 skips / 1 failure**. Los **dos originales aprobaron**; también GCM actual alterado, conflicto sin overwrite y recuperación de secreto idéntico. Sólo falló `corruptedLegacyFailsWithoutResetAndCanRetryAfterExactRestoration`, en el assert que exigía un `AEADBadTagException` anidado. XML SHA-256 **`5193e4d4bd79b23d2284b008a4219a73f0fb511fc79aa12ec4037791af055e6e`**. El aviso ddmlib de properties no es la causa del fallo: los seis casos se ejecutaron y la lane queda FAILURE.

El runtime fijado usa Tink **1.21.0**. Su [WrappedAead publicado, líneas 92–105](https://github.com/tink-crypto/tink-java/blob/v1.21.0/src/main/java/com/google/crypto/tink/aead/internal/WrappedAead.java#L92-L105) **descarta** la excepción de cada primitiva y arroja `GeneralSecurityException("decryption failed")` sin causa. Exigir que preserve el tag exception no es el contrato real de Tink.

La regresión nueva se corrige sin aceptar cualquier error: prueba lectura correcta antes de alterar un único bit, exige que el **proveedor AndroidX original** rechace el mismo registro alterado, acepta sólo AEADBadTag o el exacto tipo/mensaje Tink publicado, y exige **misma clase y mensaje raíz** al inicializar Aura. Mantiene snapshot intacto, restauración exacta y relectura real desde una instancia nueva. El caso GCM directo sigue exigiendo `AEADBadTagException`; los dos originales no se modifican. Esta corrección del test necesita una nueva ejecución, no convierte el resultado fallido anterior en éxito.

`f5b5168`: Flutter `42498706962` **SUCCESS**, **215 Python + 124 subtests, sin skips**; Android build `42498707196` / `128786548573` **SUCCESS**, **26 JVM / 0 fallos/errores/skips**, ambas APKs instrumentadas compiladas, APK debug nativo generado. Lock resuelto idéntico (`resolved_lock_diff=""`). API36/API29 de esa revisión siguen pendientes al escribir esta actualización; no aprueba aún la nueva regresión corregida. Firma `dcead91` / `42498431877` **SUCCESS**, sólo identidad CI efímera, no distribución.


### Android16 sí ejecutó: migración preservada; VPN aún no llegó al TUN

El run `1195e46` / `42496511706` / `128781731430` terminó **FAILURE**, **10 casos ejecutados / 0 skips / 5 fallos**. Ambos originales de migración pasaron en Android16, igual que conflicto, GCM directo alterado y secreto ya migrado idéntico. Falló el mismo assert del contrato Tink y los cuatro VPN fallaron en **setup de consentimiento**, no en un intercambio de paquetes. XML SHA-256 **`7b1bfce7a322f43a543542528b1992c0077fddd34cc35050376befd3149cb296`**. Primer error real publicado: `Real system VPN consent dialog was not displayed`, línea87 de esa revisión. No se etiqueta como incompatibilidad IPv6, ni se cuentan como tráfico probado.

El harness no despertaba la pantalla ni gestionaba el keyguard de swipe tras una larga compilación por software. Se añaden precondiciones de UI reales: despertar, host de test visible/keep-screen-on, pedir descartar **sólo keyguard sin PIN** mediante API pública y comprobar pantalla encendida. Se conservan el click del botón real y la comprobación `VpnService.prepare()==null`; no hay appops, permiso concedido por shell ni skip. Si sigue sin aparecer, el assert expone componente OS, paquete visible, estado pantalla/keyguard y jerarquía real (acotada) para diagnosticar el siguiente error. **La causa UI exacta y el resultado de esta corrección siguen pendientes de repetición; no se afirma que despertar por sí solo haya resuelto el caso.** La Activity de test sólo existe en `.vaultmigrationtest`, no en la app de distribución.

APK debug `f5b5168`: SHA-256 **`5b04bcd093716ad957c704731c8db7f27c589758126cefd5275c87f067cca252`**. Las cuatro ELF nuevas tienen los mismos hashes que `dcead91` (mismo código C), incluyendo arm64 **`81d1f7dc188e0bab051801422ec3fb1d20b003e8dceabfba91e9bb84e4cb370c`**. Esto demuestra empaquetado/compilación, no aprobación del TUN.


### Benchmark real de runner, sin inferir rendimiento móvil

`dcead91` / `42498290165` / `128785294792`: benchmark del candidato rechazado ejecutado, **500 cold con recarga JSON**; p50 **120,791885 ms**, p95 **132,230261 ms**, p99 **135,746021 ms**, throughput **9,18 dominios/s**. Linux7.0.0-1019-azure / x86_64 / cuatro CPU lógicas. La salida compacta conservada no incluye los valores warm: no se inventan; el artefacto `benchmark_mobile.json` contiene el informe completo. Estos números no son del modelo activo 3.0.0 ni del Redmi y **no aprueban el presupuesto móvil**.


### Nueva causa real de cero casos: framework Android no disponible al instalar

`dcead91` / `42498290239`: API36 `128787418254` y API29 `128787418242` terminaron **FAILURE con cero casos**, no aprobaciones. El primer error real de API36 fue instalar el APK: `cmd: Can't find service: package`; API29: `Device emulator-5554 API level=1. Cannot install split APKs with API level < 21`, tras fallo de consulta ddmlib. No es un test del proveedor ni demuestra que Android real fuera API1. XML vacíos hashes `47f3c23b18d8f3a520d9702609ace98ca124241947f2cb891e6cf668e4323c07` y `54732f4e3325e70f53c9eb3c6ae84622a09ab74cbd87b35f4bfb8394bacd9792`; el verificador los rechazó correctamente. **No se confirma OOM ni causa del system_server sin logs adicionales.**

Se evita compilar de nuevo HEV/Flutter/Gradle mientras arranca el emulador por software: ambas lanes ensamblan primero las mismas APKs reales y después ejecutan el connected test sin quitar tareas, clases ni asserts. Antes de instalar se leen **SDK exacta, ABI exacta, boot completed, fingerprint y resolución real del framework APK mediante Package Manager**. El preflight es de sólo lectura, una sola toma con timeouts, sin reiniciar Android/Keystore, sin appops ni retries de tests. Un estado falso/incompleto devuelve error y mantiene cero casos como fracaso. Sus fixtures Python validan el parser, **no son Android**. El resultado de esta orquestación todavía necesita CI; no se proclama que haya estabilizado el emulador.

El código de aplicación/tests Android permanece idéntico a `a3e9b2d`; este ajuste afecta sólo workflow y preflight host. Se exige su propia ejecución antes de cerrar la lane completa. La documentación no debe usarse para heredar una aprobación de runtime.


Suite local del ajuste de orquestación: **220 passed, 8 skipped, 124 subtests**. Se conserva también el `adb shell getprop ro.build.version.sdk` original; el preflight añade comprobaciones, no elimina ese log ni su guard. YAML y diff-check aprobados. Las diez nuevas pruebas son fixtures/guards de preflight, no diez ejecuciones Android.


### API29 ejecutó siete casos: Tink corregido aprobado; test del alias necesitaba el algoritmo legacy real

`a3e9b2d` / `128792953127`: **7 ejecutados / 0 skips / 1 fallo**, XML **`a3acb2ebc9bbcac0a1bc0480d8b39c05906305e4e370ed027101aa10a79dd35d`**. Los dos originales y los cuatro casos previos de integridad, incluido el cross-check Tink corregido, **pasaron**. Falló únicamente el nuevo caso del alias: creaba el RSA-OAEP por defecto, cuyo alias es `PluginKeyOAEP`, pero buscaba `PluginKey`, que corresponde a **RSA18/PKCS1** y AES. No ejercitaba la colisión que pretendía comprobar.

Se fija la precondición con el algoritmo legacy **RSA_ECB_PKCS1Padding** y se conserva cada assert de clave/certificado/ciphertext/lectura nueva. La ruta normal OAEP no comparte ese alias: se corrige esta precisión en el alcance del hallazgo, no se proclama destrucción del alias OAEP por el constructor AES.

La revisión del código simétrico encontró además el mismo borrado implícito **AES→RSA18**. Ahora ambos constructores rechazan tipos incompatibles sin borrar datos. Se añade una sexta regresión de integridad que crea AES real no-exportable en AndroidKeystore, persiste un ciphertext GCM, exige rechazo RSA y lo descifra mediante un handle recuperado de **un KeyStore nuevo**. La clave de esa prueba no exige autenticación y **no es evidencia CryptoObject**. Proveedor: 43 archivos / **5 cambios funcionales** / 3 whitespace. API36 exige ahora **13 casos** (2 originales + 6 integridad + 5 VPN); API29 **8**. Requiere CI nueva; no convierte el caso anterior en éxito.


### DDMLib: timeout real de lectura distinto del preflight y diagnóstico API29 completo

En `6310f96` / API29 `128796939231`, las cinco lecturas adb reales pasaron: SDK29, boot=1, x86, fingerprint Android10 y `/system/framework/framework-res.apk`. Después falló **`PropertyFetcher` con `ShellCommandUnresponsiveException`**, seguido de `Unknown API Level` y XML TestRunner `No compatible devices connected` (SHA **`bd693de8d0c51bc501fdccae3e81d957bdd39f0a58067b14eb560d0b6e61a1f1`**). **Cero casos originales/integridad ejecutados**, no un resultado del Keystore.

Código fuente de AGP **8.13.0**, que coincide con `android/settings.gradle`, consultado en [PropertyFetcher.java, mirror fijado](https://github.com/jrodbx/agp-sources/blob/1fa1ad1b0753d0a079b9f24fad0187cd95c38772/8.13.0/com.android.tools.ddms/ddmlib/com/android/ddmlib/PropertyFetcher.java): `GETPROP_TIMEOUT_SEC = 2`, configurable mediante **`ddmlib.getprop.timeout.sec`**. El `IDeviceSharedImpl.getVersion()` puede devolver `AndroidVersion.DEFAULT` cuando no dispone de esa propiedad; eso no significa que el sistema Android ejecutado sea API1.

Se añade **`-Dddmlib.getprop.timeout.sec=20`** a los dos comandos originales connected-test, manteniendo un límite finito, precompile anterior al boot, lectura de API real, mismos originales/proveedor/UID/aserciones y verificación XML estricta. No se establece una API artificial, no se reintenta, resetea ni reinicia el emulador y no se infiere causa OOM no demostrada. Puede seguir fallando: el cambio sólo amplía la lectura, no garantiza estabilidad. API29 también imprime ahora el stack XML del primer error/fallo, al igual que API36. El guard de fuente nuevo sólo comprueba la configuración; no es Android.
