# Aura Android — auditoría final de estado

**Fecha:** 2026-11-08 (UTC)
**Repositorio:** `liendomaho-wq/Aura-V1.0`
**Rama de trabajo activa:** `arena/611b52b0-aura-v1-0`
**Base auditada:** `234890bb47f9be5ed7487d77a9c084a49c822b9b`
**Cambio aplicado:** `b87375a` — `security(vpn): authenticate local SOCKS5 listener`
**Veredicto:** remediación de una exposición concreta implementada; **no es una aprobación de release ni evidencia de que la VPN transporte tráfico correctamente**.

## 1. Resumen ejecutivo

La revisión confirmó que Aura levantaba en Android un proxy SOCKS5 de loopback en `127.0.0.1:18763` sin configurar autenticación. Eso permitía que un cliente local que alcanzara el puerto intentara usar el listener como proxy abierto mientras el servicio estuviera activo.

El cambio `b87375a` endurece el listener HEV existente, en vez de introducir un segundo relay: genera credenciales efímeras, las entrega al cliente y al servidor nativo mediante la configuración temporal, exige RFC 1929 en Android, limita las sesiones y verifica el handshake autenticado antes de aceptar el motor como listo. También añade regresiones de protocolo y conecta las pruebas JVM a Codemagic y al workflow de build Android.

El cambio **no se ha compilado con Android/NDK ni ejecutado en Gradle, Flutter, Codemagic o un teléfono**. Por tanto, no se declara validado el servicio VPN, el forwarding, el bloqueo de tráfico ni la compilación Android. La suite Python y las verificaciones de sintaxis C descritas abajo no sustituyen esas pruebas.

## 2. Hallazgo y corrección

### Estado previo

- El listener de Aura creaba cada `HevSocks5Server` sin asociarle un autenticador.
- HEV negocia el método `NONE` cuando `server->auth` es nulo; el listener estaba enlazado solo a loopback, pero loopback no constituye autenticación entre aplicaciones del dispositivo.
- La configuración C ya admitía `username` y `password`, y HEV ya implementaba autenticación RFC 1929; se reutilizó esa ruta en lugar de duplicar el proxy.

### Cambios realizados

- `AuraSocks5Credentials` genera, con `SecureRandom`, una contraseña de 32 bytes aleatorios codificada en 64 caracteres hexadecimales. El usuario local es `aura`; no se añadió ninguna contraseña fija ni credencial de producción.
- `AuraVpnService` escribe usuario/contraseña en el YAML temporal dentro del directorio privado de la app. El cliente HEV y el listener local usan el mismo par efímero. Al inicio, reanudación o recuperación de red, la configuración se prepara de nuevo según el estado del servicio.
- `Socks5AuthProtocol` exige que el servidor seleccione USER/PASSWORD y completa RFC 1929. Un servidor que seleccione `NONE`, cierre el handshake o rechace la contraseña no supera la comprobación de readiness.
- El listener C Android falla cerrado si no tiene credenciales; el parser rechaza credenciales incompletas, vacías o de más de 255 bytes. Se adjunta un autenticador HEV a cada sesión.
- Se limitan a 64 las sesiones simultáneas del listener. El timeout de 5 s aplica a cada espera de E/S durante el handshake; **no es un límite total de pared para toda la sesión**.
- La comparación de contraseñas evita el corte por primer byte distinto para contraseñas de igual longitud. Se limpian los buffers temporales Kotlin, las copias de usuario nativas y los buffers globales de configuración al finalizar el worker, en las rutas cubiertas por el código.
- Se intenta borrar el YAML temporal y se descarta la referencia Kotlin al confirmar paradas o al destruir el servicio. No se garantiza borrado forense ni zeroización completa del heap o de bloques de almacenamiento.
- Se añadieron pruebas Kotlin para generación de credenciales y éxito/rechazo del protocolo; se añadieron guards Python para la conexión entre la configuración, el listener y la API de autenticación HEV.
- `.github/workflows/android-debug-build.yml` y `codemagic.yaml` incluyen las pruebas JVM `AuraSocks5CredentialsTest` y `Socks5AuthProtocolTest`.

## 3. Validación ejecutada

| Validación | Resultado | Alcance / límite |
|---|---|---|
| `/tmp/aura-test-venv/bin/python -m pytest -q` | **112 passed, 8 skipped, 124 subtests passed** en 17,86 s | Suite Python completa disponible en este checkout; no ejecuta Android ni prueba forwarding físico. |
| `python3 tool/test_vpn_config_template.py` | **Pass** | Incluye guards estáticos para credenciales, negociación RFC 1929, fail-closed Android y límites; no es un handshake contra el servidor C real. |
| `gcc -std=gnu11 -fsyntax-only` en `hev-config.c`, `hev-main.c`, `hev-socks5-tunnel.c` y `hev-socks5-user.c`, con rama `__ANDROID__` definida | **Pass** | Sintaxis con GCC del host. No enlaza HEV/lwIP/JNI ni equivale a compilación NDK o prueba ABI Android. |
| `git diff --check` | **Pass** | Sin errores de whitespace detectados. |
| `./gradlew :app:testDebugUnitTest --offline --no-daemon` | **No llegó a ejecutar Gradle** | El wrapper terminó antes de iniciar porque no hay `java` ni `JAVA_HOME` en este entorno. Las pruebas Kotlin añadidas siguen sin ejecutarse localmente. |
| Flutter analyze/tests, APK/AAB, NDK y Codemagic | **No ejecutados** | `flutter`, Java/Android SDK y NDK no están disponibles aquí; no se inició un run de CI. |
| Tráfico real / dispositivo físico | **No ejecutado** | No hubo acceso al Redmi Note 15 Pro Plus 5G con Android 16. |

La suite de Python no valida el handshake contra el listener nativo C. La prueba Kotlin usa un servidor de prueba de streams para el protocolo cliente; hace falta todavía una prueba de integración nativa en Android o un harness host que ejecute realmente `HevSocks5Server`.

## 4. Riesgos y limitaciones que permanecen

- RFC 1929 no cifra el transporte. Se usa únicamente en el socket local de loopback; no protege frente a root, una app/proceso comprometido con acceso al proceso de Aura, depuración privilegiada o extracción de memoria.
- La contraseña permanece en una `String` Kotlin y en el YAML de configuración mientras el túnel está activo. Los buffers mutables y las copias C cubiertas se limpian, pero el runtime Java, libyaml, el allocator y el sistema de archivos no garantizan zeroización completa. `File.delete()` es mejor esfuerzo, no borrado seguro.
- El límite de 64 sesiones y los timeouts reducen consumo accidental/abuso local, pero no se sometieron a carga ni a pruebas de denegación de servicio. El timeout de 5 s es por espera de E/S, no un deadline global.
- La autenticación local solo cierra esta vía de acceso al listener; no prueba que la VPN enrute, bloquee o inspeccione tráfico. No declarar forwarding funcional, protección integral, bloqueo de DoH/QUIC/ECH ni éxito de red real a partir del handshake.
- La causa del fallo de Codemagic observado en el HEAD auditado previamente sigue sin determinarse; esta rama no tiene un run nuevo que compruebe ni ese fallo ni el cambio actual.
- No se generó un artefacto de release y no se verificó firma de producción. No se añadieron secretos ni claves de firma.
- Flutter/Dart, agente IA, criptografía de almacenamiento, permisos y UI no recibieron una auditoría manual completa nueva en esta pasada. Los documentos previos —incluido `docs/AUDIT_2026-11-07.md`— son antecedentes, no evidencia de validación del HEAD actual.

## 5. Revisión de la PR #8 y decisión de arquitectura

La revisión del diff descargado de [PR #8](https://github.com/liendomaho-wq/Aura-V1.0/pull/8) concluyó que propone reemplazar el listener nativo por un segundo relay Kotlin. No se integró: el servidor HEV ya ofrece RFC 1929 y esta corrección endurece esa implementación existente.

En el diff revisado se detectaron, al menos, estos problemas que deben corregirse y probarse antes de considerar esa alternativa:

1. `Executors.newCachedThreadPool()` permite crecer sin un límite explícito bajo conexiones entrantes; además, una conexión TCP usa tareas de relay adicionales.
2. En el lector del framing UDP, el código llama dos veces a `input.readFully(encodedAddress)`: la segunda lectura debería llenar el payload, por lo que el frame queda desalineado y el datagrama no se reconstruye correctamente.
3. La parada del relay elimina las credenciales Kotlin, pero la reanudación/cambio de red vuelve a generar credenciales mientras reutiliza el YAML previo. El cliente HEV conserva el par anterior y el relay usa el nuevo; el handshake falla salvo que ambos se regeneren de forma atómica.
4. El diff no incluía pruebas de regresión para estos caminos ni una prueba real de tráfico UDP/TCP.

La API consultada previamente reportó la PR abierta, con base `433e28c…`, mientras `main` ya apuntaba a `234890b…`; eso no demuestra que el diff esté actualizado. La PR #4 también sigue como alternativa draft según la revisión previa. Reconsultar ambos estados y diffs antes de integrarlos; no fusionar dos implementaciones de proxy.

## 6. Estado de cierre y siguientes pasos

**Estado: no listo para release.** El cambio de autenticación está implementado y el código C pasa una comprobación de sintaxis de host, pero quedan pendientes validaciones decisivas:

1. En CI con Java 17, Flutter/Android SDK y NDK configurados, ejecutar los tests JVM añadidos, `flutter analyze`, `flutter test`, los regresores Python y `flutter build apk --debug`/build release. Corregir cualquier fallo sin reducir aserciones.
2. Añadir/ejecutar una prueba de integración que conecte a la implementación nativa C, confirme negociación USER/PASSWORD y rechace `NONE` y contraseña incorrecta. Probar también el límite de sesiones y el cierre/reinicio.
3. Obtener logs del run de Codemagic fallido para identificar la causa raíz; después ejecutar el workflow en el SHA de entrega y guardar sus enlaces/resultados.
4. Validar en el Redmi Note 15 Pro Plus 5G con Android 16: instalación, inicio/parada, panic isolation, reanudación, cambio de Wi-Fi a datos, pérdida de conectividad y tráfico TCP/UDP IPv4/IPv6 hacia endpoints de prueba controlados. Registrar el tráfico observado; la UI no basta.
5. Completar la auditoría de Flutter/Dart, agente IA, criptografía, permisos y UI, y cotejar sus conclusiones con el HEAD actual.
6. Antes de distribuir, configurar la firma de producción real, generar APK/AAB y verificar signer fingerprint y hashes. No distribuir un fallback DEBUG.

No afirmar «VPN funcional», «compilación Android correcta», «validado en Redmi» ni «release listo» hasta completar los pasos correspondientes con evidencia del SHA exacto.
