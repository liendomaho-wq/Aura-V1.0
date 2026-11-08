# Aura Android — auditoría técnica y estado de cierre

**Fecha:** 2026-11-08 (UTC)
**Repositorio:** `liendomaho-wq/Aura-V1.0`
**Rama de la PR #10:** `arena/623642b7-aura-v1-0` (actualizada mediante fast-forward desde `fix/vpn-recovery-and-security-closeout`)
**`main` verificado al inicio:** `77617f32a016608e3869fd7144e153005c9e3b38` — merge de la PR #9
**Estado:** correcciones adicionales en rama aislada; no integradas en `main`.
**Dictamen:** **no listo para release**. Las pruebas Python disponibles pasan, y en esta pasada se endureció el manejo de cambios de red. No se pudo ejecutar Flutter, Gradle/JVM, NDK, Codemagic ni una prueba en teléfono; por tanto, no se afirma que este SHA compile Android, que exista un APK verificable o que la VPN transporte tráfico real.

## 1. Alcance y resumen ejecutivo

La base auditada ya contiene el listener local HEV/SOCKS5 con autenticación RFC 1929 integrada por la PR #9. El usuario y la contraseña son efímeros y se comprueba el handshake antes de anunciar el forwarding como activo. Esto reduce el riesgo de que otra app local use el listener sin credenciales; **no demuestra forwarding ni protección de red**.

En la revisión del ciclo de vida se encontraron dos huecos en la supervisión de la red física y se corrigieron en esta rama:

1. Si Android rechazaba el registro del `NetworkCallback`, el servicio solo escribía un log y todavía podía iniciar el túnel. Ahora el inicio, la reanudación y la recuperación exigen que el callback esté registrado; si no, la operación falla cerrada.
2. `refreshUnderlyingNetwork` guardaba el `Network` candidato antes de que `setUnderlyingNetworks` confirmara el cambio. Si Android rechazaba el cambio, la siguiente notificación con el mismo candidato podía quedar descartada como si ya estuviera aplicado. Ahora el candidato se guarda solo tras una actualización confirmada, para que una notificación posterior pueda reintentarla.

Se añadieron guards de regresión en `tool/test_vpn_config_template.py`. Son verificaciones estáticas de flujo fuente; no simulan Android ni sustituyen una prueba del ciclo de vida en dispositivo. El forwarding, las fugas, la recuperación real y la parada nativa siguen sin validación física.

## 2. GitHub, CI y regresiones anteriores

### SHA actual de `main`

La API de GitHub confirma `main` en `77617f32a016608e3869fd7144e153005c9e3b38`. Para ese SHA, `check-runs` está vacío y el estado de commit es `pending` sin statuses. La ejecución GitHub más reciente consultada que pasó el build Android y Flutter Quality es la `40601644781` / `40601644887`, en `d9a5d2994f1062afd90bfb465c3d6a15bea138d9`, **anterior** al cambio SOCKS5 de la PR #9. No valida `main` actual ni esta rama.

La PR #9 está fusionada en `main`. En la última consulta permanecían abiertas la #8 (conflictiva), la #4 (draft/conflictiva) y la #1 (conflictiva); no se integró ninguna alternativa de proxy de esas PRs. No se deben combinar dos relays VPN sin reconciliar sus diffs y pruebas.

La PR de esta pasada es la [#10](https://github.com/liendomaho-wq/Aura-V1.0/pull/10). Su `statusCheckRollup` está vacío. Se intentó despachar manualmente `Aura Android Debug Build`, `Aura Flutter Quality`, `Aura Model Dataset, Training and Benchmark` y `Release signing integrity`; GitHub rechazó las cuatro solicitudes con HTTP 422: **“Actions has been disabled for this repository.”** Por tanto, no hay validación remota del commit de la PR. No se intentó el workflow de release firmado con credenciales de producción. Rehabilitar Actions requiere un cambio de configuración del repositorio fuera de este checkout.

La revisión adicional de `codemagic.yaml` encontró otro bloqueo de automatización: los patrones `main`/`principal` no indicaban `source: false`, por lo que Codemagic los interpretaba como ramas de origen para eventos `pull_request`; la PR #10 sale de `arena/623642b7-aura-v1-0`, no de `main`. Se corrigió en el commit `ce82a49`: los patrones ahora seleccionan explícitamente la rama destino `main`/`principal` para PRs, manteniendo el build por push a `main`. Esto corrige la configuración versionada, pero no prueba que el webhook esté instalado/activo ni que Codemagic haya iniciado un build. Tras el push, verificar `Apps → Webhooks → Recent Deliveries` en Codemagic y ejecutar manualmente el workflow si no hay entrega automática. Referencia de sintaxis: [documentación oficial de patrones source/target de Codemagic](https://docs.codemagic.io/yaml-running-builds/starting-builds-automatically/).

### Fallo del build Android del 27 de octubre

- En el commit `41f4a77e6390278fb4098a6405880dffa7b69ded`, el workflow Android llegó a `Build debug APK including native tunnel` y falló; el validador de configuración VPN anterior pasó.
- El siguiente cambio de código (`d9a5d2994f1062afd90bfb465c3d6a15bea138d9`) añadió únicamente los imports `java.net.Inet6Address` y `java.net.InetAddress` a `AuraVpnService.kt`, donde se usan para validar direcciones IP. El build Android volvió a ejecutarse y pasó en ese commit.
- **Conclusión con evidencia disponible:** la causa raíz más probable y directamente corregida fue la ausencia de esos imports. Los logs originales del compilador no se pudieron descargar en esta sesión, así que no se presenta una línea de error textual inventada ni se asegura que esa fuera la única causa.
- El run Codemagic del mismo periodo falló en `Build Android Release artifact` y también en la verificación posterior del artefacto. Sus logs completos no estuvieron disponibles; el fallo es consistente con el problema de compilación del commit anterior, pero no basta para afirmarlo como causa exclusiva.

Referencias: [Android Debug fallido](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/40599010770), [Codemagic fallido en build del 27 de octubre](https://codemagic.io/app/6ad56a4e398d916a89605bb1/build/6ae12fe2206ce93970c6a881), [Android Debug exitoso en `d9a5d29`](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/40601644781), [PR #9](https://github.com/liendomaho-wq/Aura-V1.0/pull/9).

### Pipeline de modelo

El run `40599010820` del commit `41f4a77...` completó la instalación de dependencias, la construcción del dataset y la generación de splits adversariales, pero falló en `Train model and write held-out metrics`; el paso de golden tests también terminó fallando y el benchmark se omitió. El resumen de GitHub no aporta la excepción concreta. El artefacto de informes registrado tiene solo 263 bytes y no se pudo descargar desde este entorno, por lo que no hay métricas utilizables que atribuir a esa ejecución.

No se han bajado los umbrales de calidad ni se han creado métricas sustitutas. En este checkout no existe `data/` (los datasets están ignorados) y no se ejecutó un nuevo pipeline con fuentes externas. La causa precisa de ese fallo sigue **pendiente de logs**.

Referencia: [run de entrenamiento fallido](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/40599010820).

### Regresión de la prueba de transparencia UI

El historial/documentación del run Codemagic del 5 de noviembre describe un fallo de `test/aura_transparency_ui_test.dart`: el estado local de falso positivo quedó en `false` (`Expected true / Actual false`) y apareció una advertencia de hit-test al pulsar el texto del botón. Después se añadieron una clave estable y desplazamiento hasta el control visible; la prueba actual pulsa el botón por clave y el callback local llama a `markExplanationAsFalsePositive`.

Esto apunta a una interacción de widget/visibilidad no determinista, no demuestra un defecto del callback de producción. Los cambios posteriores no tienen un run verde verificable sobre `main` actual, y Flutter no está instalado en este entorno; la regresión se considera **corregida en código, pendiente de verificación**. Referencia: [run Codemagic del 5 de noviembre](https://codemagic.io/app/6ad56a4e398d916a89605bb1/build/6aec4375004ce28f20ee1577).

### Antecedente NDK / Android

El cambio de noviembre `adc0bd1` incluyó ajustes del código nativo (entre ellos, restringir a Android un normalizador usado por HEV) y se tituló como corrección de NDK. El proyecto actual declara NDK `28.2.13676358`, usa `ndk-build` y configura alineación de páginas de 16 KiB. No hay evidencia de una compilación NDK del SHA actual. Una nota anterior sobre resolución local del plugin Flutter/Gradle tampoco se pudo reproducir: aquí faltan Flutter, Java y Android SDK, así que no se puede atribuir ese antecedente a una regresión vigente.

Referencia histórica: [cambio NDK/privacidad `adc0bd1`](https://github.com/liendomaho-wq/Aura-V1.0/commit/adc0bd17463a7d80a1bc05c2d16ee276c4a6b3d7).

### Toolchain declarada (no compilada en este entorno)

`pubspec.yaml` requiere Dart `>=3.12.0` y Flutter `>=3.44.0`. El proyecto declara Gradle Wrapper `8.14.3`, Android Gradle Plugin `8.13.0`, Kotlin `2.2.20`, JDK `17`, `compileSdk 36`, `minSdk 24`, `targetSdk 36` y NDK `28.2.13676358`; incluye ABIs `armeabi-v7a`, `arm64-v8a`, `x86` y `x86_64`. Codemagic declara Flutter stable/JDK 17 en `mac_mini_m2`, pero `AURA_REQUIRE_RELEASE_SIGNING=false` y firma DEBUG para builds de prueba. Estas versiones/configuraciones se inspeccionaron, no se validaron mediante build aquí.

## 3. Cambios de esta pasada

### Recuperación de la red física

En `android/app/src/main/kotlin/com/ciberdefensa/aura/AuraVpnService.kt`:

- `requireUnderlyingNetworkMonitor()` lanza `IOException` si Android no confirmó el registro del callback de red física. Se aplica al inicio, a la reanudación desde aislamiento y a la recuperación de handover; un fallo no debe presentarse como forwarding activo sin mecanismo de recuperación.
- `underlyingNetwork = selected` se mueve después de la confirmación de `setUnderlyingNetworks`. Si la sincronización falla, se conserva el valor anterior, se detiene el forwarding y un callback posterior puede volver a intentar la selección.

En `tool/test_vpn_config_template.py`:

- Se comprueba que inicio, reanudación y recuperación exijan el monitor.
- Se comprueba el orden de sincronización y commit del `Network`, incluido que el retorno por fallo suceda antes de guardar el candidato.

En `docs/RELEASE_AND_DEVICE_VALIDATION.md`:

- El comando JVM documentado incluye los cuatro tests existentes: correlación de inicio, lifecycle, credenciales SOCKS5 y autenticación RFC 1929.

### Implementación existente que se conserva

- `AuraVpnService` instala rutas IPv4 e IPv6 de ruta completa, protege los sockets upstream y los enlaza a la red física seleccionada. El arranque del motor HEV se verifica con el estado JNI y con el handshake SOCKS5 local autenticado.
- El parser C SNI está conectado a las sesiones TCP HEV y dispone de pruebas host para ClientHello normal, fragmentado, ECH y reglas. Esas pruebas ejercitan el parser y guards de integración; no equivalen a una captura de tráfico real del teléfono.
- El servicio trata la disponibilidad del feed de reputación IP como cobertura opcional: el arranque no debe depender de una descarga. El servicio puede funcionar con cobertura reducida cuando la fuente remota falla.
- SecureVault usa el puente de migración v9→v10 con `resetOnError=false` y backup; existen tests Robolectric de migración, pero no se ejecutaron aquí.
- El modelo empaquetado vigente es `3.0.0`, con seis características y 500 árboles; mide 3,004,068 bytes. El SHA-256 comprobado es `d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2`. El verificador de paquete comprueba digest y firma del archivo incluido. Esto no mide calidad predictiva. El candidato de entrenamiento `3.1.0` no se promocionó ni se evaluó en esta sesión.
- `RECORD_AUDIO` se solicita al invocar reconocimiento de voz en Android; `flutter_tts` por sí solo no usa micrófono. `QUERY_ALL_PACKAGES` respalda inventario/escaneo de aplicaciones y debe seguir documentado para el canal de distribución elegido. No se inspeccionaron permisos concedidos en un dispositivo.

## 4. Validación ejecutada en esta rama

| Validación | Resultado | Qué demuestra / qué no demuestra |
|---|---|---|
| `/tmp/aura-audit-venv/bin/python -m pytest -q -rs` | **112 passed, 8 skipped, 124 subtests passed** | Los ocho omitidos son las pruebas AAB que requieren JDK (`java` y `javac`). No cubre Flutter, JVM Android ni red física. |
| `python3 tool/test_vpn_config_template.py` | **Pass**, incluidos los dos nuevos guards | Comprobaciones de configuración y orden del código fuente; no ejecuta `AuraVpnService` en Android. |
| `tool/test_aura_sni_firewall.py`, `test_mapped_dns.py`, `test_tun_packet_filter.py`, `test_lwip_fragment_policy.py` | **Pass** | Pruebas host/harness nativo disponibles; no es una compilación NDK ni un test de tráfico del teléfono. |
| `tool/test_verify_packaged_model.py` | **Pass** | Verificación del SHA y de la firma del modelo empaquetado con la clave configurada; no es una evaluación ML. |
| `tool/test_release_signing_policy.py`, `test_release_signing_runtime.py` | **Pass** | Guards de política y casos de verificación con fixtures; no verifica un APK/AAB Android real. |
| `python3 tool/test_verify_aab.py` | **Bloqueado por entorno** | Sale con código 1 y exige JDK 17 (`java`, `javac`) y OpenSSL. OpenSSL sí está disponible; falta JDK. En `pytest` las ocho pruebas se reportan explícitamente como omitidas. |
| `bash -n` sobre scripts de build/setup | **Pass** | Sintaxis Bash; no ejecuta Flutter, Gradle ni NDK. |
| `git diff --check` | **Pass** | Sin errores de whitespace en el diff actual. |
| Flutter/Dart, Gradle/JVM/Robolectric, APK/AAB, NDK | **No ejecutados** | No están instalados `flutter`, `dart`, Java/JDK, Gradle, Android SDK/NDK, `clang` ni `sdkmanager`; `ANDROID_HOME`, `ANDROID_SDK_ROOT` y `JAVA_HOME` están vacíos. |
| GitHub Actions para la PR #10 / commit candidato | **No ejecutado: Actions deshabilitado** | La PR no tiene checks; los cuatro `workflow_dispatch` devolvieron HTTP 422 `Actions has been disabled for this repository`. Tampoco aparece un check nuevo de Codemagic en la PR. |
| GitHub CI para `77617f3` | **Sin evidencia actual** | No hay check-runs en ese SHA. Los resultados anteriores corresponden a otros commits. |
| Redmi Note 15 Pro Plus 5G / Android 16, túnel y tráfico real | **No ejecutados** | No hubo dispositivo conectado ni evidencia de TCP, UDP, DNS, IPv4/IPv6, handover, aislamiento o ausencia de fugas. |

## 5. Límites de seguridad y afirmaciones permitidas

- RFC 1929 no cifra el transporte. Aquí limita el listener SOCKS5 de loopback al secreto efímero; no protege frente a root, un proceso comprometido o extracción de memoria.
- El secreto existe en memoria Kotlin/JNI y en el YAML privado durante el ciclo del túnel. La limpieza es de mejor esfuerzo; ni sobrescritura de arrays ni `File.delete()` garantizan borrado forense del heap, allocator o almacenamiento.
- El parser SNI no descifra TLS. ECH puede ocultar el nombre interior; DoH, QUIC/DoQ, protocolos no observables, fragmentos y resolvedores externos limitan la cobertura. Reglas cargadas o contadores no son prueba de tráfico bloqueado.
- La comprobación del estado local, el handshake, las pruebas estáticas y los harnesses C **no autorizan** afirmar “VPN activa/funcional”, “forwarding confirmado”, “sin fugas” o “tráfico inspeccionado” sin una compilación del SHA y observación en dispositivo.
- `codemagic.yaml` selecciona modo de artefacto DEBUG para pruebas (`AURA_REQUIRE_RELEASE_SIGNING=false`). No se han usado credenciales de producción ni generado un APK/AAB en esta sesión. Ese artefacto no se debe distribuir.

## 6. Cierre y siguientes pasos necesarios

**Estado: cambios de ciclo de vida preparados en la rama Arena; revisión técnica y release aún abiertos.** Para cerrar:

1. Ejecutar sobre el commit candidato Flutter `pub get`, `flutter analyze`, toda la suite `flutter test`, las regresiones Python y los cuatro tests JVM; compilar APK Debug con Flutter/Gradle y NDK. Conservar logs del SHA exacto y corregir cualquier fallo sin reducir aserciones.
2. Ejecutar o inspeccionar una nueva corrida del pipeline ML con dataset real, manifiesto, splits, métricas holdout y logs de entrenamiento. Si el candidato no pasa gates, no publicarlo ni alterar los umbrales para obtener verde.
3. Obtener la excepción completa del Codemagic fallido del 27 de octubre y confirmar si era el mismo error de imports; ejecutar Codemagic en el commit candidato si el workflow está disponible.
4. Probar en dispositivo: permiso VPN, inicio/parada/revocación, pérdida y recuperación de red, cambio Wi‑Fi/datos, aislamiento, SOCKS5, DNS y tráfico TCP/UDP IPv4/IPv6 mediante destinos controlados. Registrar fugas y estado JNI/TUN observado, no solo la UI.
5. Ejecutar SecureVault v9→v10 y pruebas de firma AAB/APK con JDK/Android SDK; para distribución, configurar firma de producción en el almacén seguro y verificar certificado/SHA. Nunca publicar un fallback DEBUG.

No se declara que la tarea esté “terminada”, que se haya generado un APK instalable o que Aura VPN esté validada hasta que esas evidencias existan.


## Correcciones adicionales de recuperación VPN y política ADB — 2026-11-08

### Recuperación de forwarding sobre la interfaz TUN retenida

Se corrigió el caso que dejaba el servicio sin forwarding después de un handover fallido:

- Se añadió un gate atómico independiente `recoveryRequested` para serializar solicitudes de recuperación y evitar reinicios nativos duplicados.
- Si el usuario vuelve a activar Aura y Android conserva la interfaz TUN pero el forwarding está detenido, `onStartCommand` solicita recuperación sobre esa misma interfaz en lugar de establecer una segunda TUN.
- Una notificación posterior de la misma red física también puede volver a solicitar recuperación cuando el forwarding sigue inactivo.
- El ID de solicitud de inicio se propaga a la recuperación y a su respuesta, para conservar la correlación del canal Flutter.
- `startRequested` ahora representa el arranque inicial en curso: se libera cuando el inicio o la reanudación concluyen, y tras un fallo de recuperación. El estado activo se determina por `tunnelStarted` y la verificación del worker, no por mantener ese gate ocupado.
- La recuperación exige que el monitor de red siga registrado y que exista una red física seleccionada; no informa forwarding activo si no puede confirmar el worker y el handshake SOCKS5.

Se añadieron guards estáticos para el gate single-flight, el reintento sobre la misma red, la reactivación explícita con TUN retenida y la liberación de `startRequested`. Los guards no han sido ejecutados en este entorno y no sustituyen los tests JVM ni el handover real en Android.

### Depuración USB como señal informativa

`ADB_ENABLED` se conserva como dato de diagnóstico, pero ya no forma parte de `integrityFailed`. Tener depuración USB activada no demuestra por sí solo que el APK esté manipulado y no debe apagar la VPN de un usuario que utiliza ADB legítimamente. Se mantienen como condiciones de integridad el certificado permitido, la inspección de mapas, la detección de Frida/Gadget y el depurador adjunto en builds no debug. Se añadió un guard estático para evitar que ADB vuelva a convertirse accidentalmente en bloqueo.

### Commits de esta corrección

- `025a4e8`: recuperación single-flight y reintento del forwarding sobre TUN retenida.
- `1b7e9b7` y `fc6295b`: guards de regresión y corrección de sus patrones.
- `9a2b7f3`: ADB como señal informativa.
- `e4c0428`: guard de política ADB.

### Bloqueos que siguen abiertos

- No hay ejecución CI sobre esta rama. La auditoría anterior documenta GitHub Actions deshabilitado; no hay evidencia de que se haya habilitado desde entonces.
- No se ha ejecutado Codemagic sobre estos commits; no existe APK de este HEAD ni resultado de compilación Android.
- Los guards Python añadidos/modificados, Flutter analyze/tests, Gradle/JVM, NDK y las pruebas nativas siguen pendientes de ejecución.
- El vínculo criptográfico entre biometría y clave de SecureVault sigue pendiente. El `BiometricPrompt` actual devuelve éxito de autenticación para desbloquear la interfaz y no usa `CryptoObject`; no se debe presentar como protección biométrica de la clave de cifrado.
- El pipeline del modelo sigue sin una nueva ejecución verificable ni métricas holdout. No se promocionó el candidato 3.1.0.
- La cancelación cooperativa/progreso nativo del escáner APK/DEX y la validación del planificador del agente siguen pendientes.
- El modo de firma de producción, el keystore/credenciales, la verificación de APK/AAB reales y la matriz física en Redmi Note 15 Pro Plus 5G / Android 16 siguen pendientes.

**Dictamen actualizado:** la recuperación manual y automática sobre TUN retenida tiene una corrección de código y guards añadidos, pero no está validada por ejecución. Aura continúa **no lista para release** hasta que CI, Codemagic, firma y pruebas en dispositivo aporten evidencia sobre el SHA exacto.


### Revisión de concurrencia de recuperación — 2026-11-08

Una segunda revisión del helper single-flight detectó que el gate no debía rechazar `tunnelStarted == true`: durante un handover normal el worker está activo, pero sus sockets upstream pertenecen a la red física anterior y deben reiniciarse. Se corrigió para que:

- un cambio real de red física pueda reiniciar el worker incluso si el túnel estaba activo;
- el reintento sobre la misma red solo ocurra cuando el forwarding esté detenido;
- aislamiento de emergencia y destrucción sigan bloqueando la recuperación;
- el gate atómico impida que dos callbacks ejecuten reinicios simultáneos.

Se añadió un guard que falla si el helper vuelve a descartar una recuperación únicamente porque `tunnelStarted` está activo.

Commits adicionales:
- `2fff4bb`: permite recuperar el worker activo después de un handover.
- `e395f55`: añade regresión para handovers con worker previamente activo.

La corrección continúa pendiente de ejecución de los workflows sobre el SHA final y de pruebas de handover en Android real.
