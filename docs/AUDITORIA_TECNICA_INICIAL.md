# Aura Mobile Defens — Auditoría técnica inicial

**Fecha:** 2026-10-27  
**Rama auditada:** `main`  
**Alcance:** revisión estática inicial de archivos seleccionados. No equivale a una auditoría completa, pentest ni validación en dispositivos físicos.

## Resumen ejecutivo

Aura combina Flutter/Dart, servicios Android en Kotlin, componentes nativos C/C++, una VPN local, reglas de inspección TLS SNI y un modelo local. La arquitectura tiene componentes relevantes, pero la existencia de esos componentes no demuestra cobertura de protección completa. Las prioridades iniciales son privacidad por defecto, validación automatizada, integridad de releases, minimización de permisos y pruebas de red en dispositivos.

## Cambios aplicados en esta iteración

- La telemetría local ahora está **desactivada por defecto**. El usuario debe habilitarla explícitamente mediante `setEnabled(true)`.
- Se agregaron pruebas para verificar el comportamiento opt-in y se adaptó la prueba existente para habilitar la telemetría expresamente.
- `clearEvents()` ya no falla si la clave de preferencias no existía; la operación de borrado es idempotente.
- El flujo de publicación Android exige `AURA_REQUIRE_RELEASE_SIGNING=true` al compilar y verificar el artefacto.
- Se añadió un workflow para ejecutar análisis estático y pruebas Flutter en pushes y pull requests.
- La ejecución de CI del commit `f956af6` terminó correctamente: análisis estático y suite Flutter aprobados (run [40587999575](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/40587999575)).
- Se retiraron del árbol Git 26 archivos generados y se confirmó que no quedan entradas rastreadas bajo `android/.gradle/`.
- El motor de integridad ahora trata una firma de aplicación ausente o inválida como estado crítico aunque un informe nativo contradictorio indique `isSecure=true`; se añadieron pruebas unitarias para esos casos.
- El motor de detección de root ya no interpreta el binario `su` del host Linux/macOS como evidencia de root Android.
- El commit `a3ea203` pasó `flutter analyze` y toda la suite Flutter en CI (run [40588530841](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/40588530841)).
- El commit `bac0f41` pasó el workflow Flutter de calidad (análisis estático y pruebas) en el run [40588910406](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/40588910406).
- El workflow de compilación Android de depuración pasó para `bac0f41`, incluyendo Kotlin/C/JNI, en el run [40588910379](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/40588910379). Esto valida compilación, no conectividad VPN en un dispositivo.
- Se añadieron pruebas negativas de firma de modelos: firmas vacías, truncadas y fuera del rango RSA deben rechazarse.
- El endpoint upstream SOCKS5 ya no depende de un hostname `.local` ficticio: el build lee `AURA_SOCKS5_HOST` y `AURA_SOCKS5_PORT` del entorno y falla con un mensaje explícito si faltan o son inválidos.

## Hallazgos priorizados

### P0 — Privacidad y minimización de datos

**Observación:** antes del cambio, `AuraLocalTelemetry.isEnabled()` interpretaba una preferencia ausente como `true`, habilitando la recopilación local en una instalación nueva. Los eventos pueden incluir nombres de dominio en texto claro.

**Mitigación aplicada:** opt-in por defecto.

**Trabajo pendiente:** revisar la interfaz de consentimiento y la política de privacidad; determinar si el usuario entiende qué datos se guardan y durante cuánto tiempo; valorar la minimización, el borrado automático y el almacenamiento protegido para datos sensibles. No afirmar que los dominios quedan cifrados: esta modificación no cifra el almacén de eventos.

### P1 — Permisos Android y elegibilidad de distribución

**Observación:** `AndroidManifest.xml` declara `QUERY_ALL_PACKAGES` y `RECORD_AUDIO`. El primero permite visibilidad amplia del inventario de aplicaciones instaladas, que Android/Google Play trata como información sensible y restringe a casos de uso admisibles. La grabación de audio también requiere que la función que la necesita esté clara y que el permiso se solicite en el momento adecuado.

**Recomendación:** rastrear los usos de cada permiso en Dart/Kotlin y justificar su necesidad para la función principal. Si Aura solo necesita detectar un conjunto limitado de aplicaciones, sustituir `QUERY_ALL_PACKAGES` por consultas específicas. Mantener el permiso amplio únicamente si la función principal lo requiere y puede justificarse en la declaración de Play Console. Verificar divulgación destacada y consentimiento para cualquier recopilación sensible relacionada con la VPN. No eliminar permisos sin revisar primero los flujos dependientes.

Referencias:
- Google Play, permisos y APIs con acceso a información sensible: https://support.google.com/googleplay/android-developer/answer/16558241
- Política de visibilidad de paquetes: https://support.google.com/googleplay/android-developer/answer/10158779

### P1 — Integridad de publicación

**Observación:** `tool/compile_aura.sh` permite una firma de depuración como fallback salvo que `AURA_REQUIRE_RELEASE_SIGNING=true`. Aunque el script marca el artefacto como solo de pruebas y contiene validaciones adicionales, la distribución de producción debe exigir siempre una clave de release.

**Mitigación aplicada:** el workflow Android de publicación ahora establece `AURA_REQUIRE_RELEASE_SIGNING=true` durante compilación y verificación.

**Trabajo pendiente:** probar el workflow con secretos ausentes y credenciales inválidas; comprobar que el certificado del artefacto final coincide con el certificado esperado y restringir publicación a tags/revisiones autorizadas.

### P0 — Endpoint SOCKS5 del túnel no localizado

**Observación:** `AuraVpnService.kt` fija `SOCKS5_HOST = "socks5.tun2socks.local"` y puerto `1080`, y llama a `InetAddress.getAllByName` seguido de una comprobación de saludo SOCKS5. El árbol nativo vendorizado sí incluye fuentes del protocolo servidor (`android/app/src/main/cpp/hev-socks5-tunnel/src/core/src/hev-socks5-server.c`), pero la clase `TProxyService` solo expone el JNI del cliente tun2socks. En la integración de Aura no se encontró una rutina que cree un socket de escucha, acepte conexiones y ejecute `hev_socks5_server_run`, ni un listener local iniciado por `AuraVpnService`. Por tanto, la presencia de código servidor no demuestra que exista un SOCKS5 local activo. El README de Hev documenta `socks5.address` como dirección del servidor upstream.

**Impacto probable:** si no existe infraestructura externa que resuelva y sirva ese endpoint, la resolución o el saludo fallará y el servicio VPN no llegará a iniciar. El repositorio no contiene una configuración visible de ese upstream.

**Mitigación aplicada:** el host y el puerto se configuran mediante `AURA_SOCKS5_HOST` y `AURA_SOCKS5_PORT` al compilar. Si faltan o el puerto no es válido, el servicio aborta con un mensaje claro en vez de intentar resolver `socks5.tun2socks.local`. Ejemplo de configuración de entorno para un despliegue: `AURA_SOCKS5_HOST=proxy.example.net` y `AURA_SOCKS5_PORT=1080` (el dominio es solo ilustrativo; no representa un servidor real).

**Pendiente crítico:** todavía no hay un servidor SOCKS5 activo/configurado que se haya validado de extremo a extremo. No sustituir el endpoint por `127.0.0.1` solo porque existan fuentes del protocolo servidor: hace falta integrar e iniciar un listener, limitarlo a loopback, evitar bucles de encaminamiento protegiendo sus sockets de salida y probar TCP CONNECT y UDP ASSOCIATE. La otra opción es configurar un upstream real gestionado; el cliente actual valida el saludo sin autenticación y no admite credenciales en este flujo. La validación requiere un build Android y pruebas en dispositivo/emulador con tráfico TCP/UDP; no se declara la VPN funcional hasta completarlas.

### P1 — VPN, DNS y firewall SNI

**Observación:** la inspección SNI no proporciona visibilidad universal del tráfico. ECH, DNS cifrado, protocolos no TLS, QUIC/HTTP3 y rutas IPv6 pueden cambiar lo que es observable, dependiendo del túnel y de las políticas de red. La cobertura real no se puede inferir únicamente de la presencia del firewall.

**Recomendación:** crear pruebas de integración con tráfico controlado para IPv4/IPv6, DNS, DoT/DoH, TLS fragmentado, ClientHello dividido entre registros, ECH, QUIC, reconexión, cambio Wi-Fi/datos y cierre inesperado del servicio. Documentar los límites y no prometer protección contra tráfico que no se inspecciona.

### P1 — Calidad automatizada

**Observación:** el repositorio contiene pruebas Flutter, pero la revisión de archivos seleccionados no demuestra que el análisis estático y los tests se ejecutaran en cada cambio.

**Mitigación aplicada:** se añadió `.github/workflows/flutter-quality.yml` con `flutter analyze` y `flutter test` en pull requests y pushes a `main` y `principal`.

**Trabajo pendiente:** confirmar el resultado de la primera ejecución y corregir cualquier fallo de análisis o pruebas. Añadir pruebas nativas y análisis de dependencias.

### P1 — Archivos generados

**Observación:** el árbol Git incluye archivos bajo `android/.gradle/`, a pesar de que el directorio aparece excluido en `.gitignore`. Ignorar un archivo no lo elimina si ya está rastreado.

**Recomendación:** confirmar que no se necesitan para reproducibilidad y retirar los artefactos ya rastreados en un cambio separado; conservar lockfiles y fuentes necesarias.

### P2 — Almacenamiento y claves criptográficas

**Observación:** el código nativo intenta limpiar buffers mutables, pero esto no garantiza borrar todas las copias creadas por el runtime, JNI o el proveedor criptográfico. La autenticidad de los modelos depende de una verificación de firma y de proteger correctamente la clave privada de firma.

**Observación adicional:** `encryptModel`/`decryptModel` usan AES-CBC con padding PKCS#7. CBC no autentica el ciphertext por sí solo; un descifrado exitoso no prueba que el contenido no haya sido alterado. La firma RSA del modelo aporta autenticidad cuando se verifica sobre exactamente los bytes firmados, pero no debe asumirse que protege automáticamente cada payload cifrado o cada uso futuro del modelo.

**Recomendación:** revisar generación, almacenamiento, rotación y recuperación de claves; preferir AES-GCM u otra construcción AEAD para un formato nuevo. Para preservar compatibilidad, no cambiar el formato actual en caliente: diseñar un formato versionado con nonce, etiqueta de autenticación y migración explícita; rechazar datos no autenticados antes de utilizarlos. Añadir pruebas de round-trip y entradas inválidas; probar fallos de firma, truncamiento, archivos grandes y downgrade.

## Matriz de validación pendiente

| Área | Evidencia requerida | Estado |
|---|---|---|
| Telemetría opt-in | Pruebas unitarias y revisión de UX | Cambio implementado; ejecución local no disponible en esta sesión |
| Flutter | `flutter analyze`, `flutter test` | Aprobado en run 40587999575 para commit f956af6; nuevas modificaciones deben volver a validarse |
| VPN | Pruebas instrumentadas en dispositivos/emuladores | Pendiente; resolver antes el endpoint SOCKS5 P0 |
| IPv6/DNS/TLS/QUIC | Matriz de tráfico controlado | Pendiente; incluye endpoint SOCKS5, ECH y tráfico UDP |
| Firma release | Validación de APK/AAB con certificado esperado | Cambio de workflow implementado; validación real de release pendiente |
| Permisos | Justificación y revisión de divulgación/consentimiento | Pendiente |
| Dependencias | Auditoría de vulnerabilidades y licencias | Pendiente |
| Rendimiento | CPU, RAM, batería y latencia en equipos representativos | Pendiente |

## Criterio de salida

No declarar Aura “segura” ni “de nivel líder” hasta que los controles tengan pruebas reproducibles, cobertura definida, revisión independiente y resultados documentados. Las comparaciones con PCAPdroid, Rethink DNS y OWASP MASVS deben basarse en escenarios y métricas equivalentes, no solo en listas de características.
