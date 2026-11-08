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
- **Ejecución Android de la nueva corrección todavía pendiente; añadir evidencia de CI antes de cerrar CI-01 o la migración.**

### MODEL-01 — reintentos reales con presupuesto, sin promover el candidato

- Plan fijado antes de evaluar: `(depth, min_samples_leaf) = (10,512), (8,1024), (6,2048), (4,4096)`, exactamente 500 árboles en cada entrenamiento real. Máximo cuatro intentos; ningún gate de calidad se rebaja.
- Se mide el JSON UTF-8 exacto, finito y con terminador reproducible. Los candidatos sobredimensionados se rechazan **antes** de consumir la validación. Tras calibrar únicamente con validación se vuelve a comprobar el tamaño final, estrictamente menor a **4.194.304 bytes** como antes.
- Cada intento real queda registrado inmediatamente, con profundidad, hojas, tamaño, etapa y si consumió validación. Si todos fallan, el mensaje enumera exclusivamente esos intentos; ya no inventa profundidad 8 ni poda.
- El test holdout y su conjunto adversarial no eligen configuraciones. Las métricas se calculan sobre el modelo serializado elegido, guardan SHA del candidato, script, corpus y splits, versiones Python/NumPy/scikit-learn y resultado explícito del gate.
- Nuevas regresiones verifican el plan acotado, el límite original, árbol completo de peor caso para el último fallback, serialización finita, estadísticas del modelo real 3.0.0 y separación de selección/holdout. **No son métricas de entrenamiento del dataset ni un benchmark del teléfono.**
- Suite local tras estos cambios: **155 passed, 8 skipped, 124 subtests passed in 8.79s** (`python -m pytest -q -rs`). `compileall` y `git diff --check` aprobados. Las ocho omisiones AAB locales siguen pendientes.
- **Reentrenamiento y evaluación completos pendientes de CI; el modelo 3.0.0, su digest y firma permanecen intactos.**
