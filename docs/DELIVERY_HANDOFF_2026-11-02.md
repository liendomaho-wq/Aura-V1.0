# Aura V1.0 — entrega técnica y estado de salida

Fecha: 2026-11-02  
Rama: `main`  
Último commit de esta entrega: `6ea642304d58b53a373577cb60531645ebf7a6df`

## Resultado de este ciclo

Se conserva la arquitectura Flutter/Dart + Kotlin/JNI/C y el servicio VPN local existente. No se reinicia el proyecto ni se elimina la VPN. Se consolidan las siguientes mejoras:

- La consola falla de forma cerrada cuando Android no confirma la autenticación nativa. Un error de autenticación ya no abre silenciosamente una sesión sin bloqueo.
- Se añadió una regresión estática que impide reintroducir el fallback inseguro en `AuraCoreScreen`.
- Se corrigieron cinco expresiones regulares sobreescapadas en `tool/test_vpn_config_template.py`.
- GitHub Actions ejecuta ahora `tool/test_vpn_config_template.py` y `tool/test_aura_sni_firewall.py`, además de `flutter analyze` y `flutter test`.
- CodeMagic conserva `~/.pub-cache` y `~/.gradle/caches` entre builds exitosos para reducir descargas de dependencias.
- README y auditoría de salida describen las capacidades de red con límites verificables y ya no atribuyen enforcement SNI/ECH al camino TUN.

## Commits de esta entrega

- `1b65c6413a07267419e1949e7eb9ad1f17c3d173` — corrección de patrones regex de regresión VPN.
- `f70d4a54f0a5d0e11dec225ac056af41569bb6ab` — autenticación fail-closed de consola.
- `7f2a0dc8b8e967adfb372e914b1f296549e67fde` — guardia estática contra bypass de autenticación.
- `854c14807d186dd0f3976fb181426f36be0db5c6` — auditoría de preparación de release.
- `febfefd6bfb41bd83700552781d24d0048b25e00` — limpieza de formato de mensaje.
- `4fd5e6a321651a41c89c5fd9c5c38b440fe8096e` — regresiones nativas en GitHub Actions.
- `58fe67ad89d353bf1f2d943cb4e981296db1df62` — caché de dependencias en CodeMagic.
- `6ea642304d58b53a373577cb60531645ebf7a6df` — documentación de red corregida.

## Alcance real de la protección de red

- El código configura rutas TUN IPv4/IPv6 y usa tun2socks/HEV con listener SOCKS5 local.
- El ingreso TUN descarta DoT/TCP 853, DoQ/UDP 853 y UDP/443 solo hacia IP de resolutores DoH conocidos.
- No hay bloqueo universal de DoH sobre TCP/443 ni de QUIC/HTTP3.
- El parser SNI y sus reglas existen y tienen pruebas nativas aisladas, pero no se invocan desde el flujo de paquetes TUN. No se anuncian como inspección o bloqueo SNI operativo.
- ECH no se descifra y no existe enforcement ECH activo.
- El feed de reputación, el escáner de apps y el modelo local aportan señales limitadas; no son certificación universal de malware.

## Estado de validación

**No se certifica este commit como build aprobado ni como release de producción.**

Al consultar GitHub Actions después de estos cambios, los runs visibles más recientes correspondían al commit anterior `d9a5d2994f1062afd90bfb465c3d6a15bea138d9` (2026-10-27). No había un run visible para el commit actual de entrega. Los estados de commit tampoco informaban checks. Por tanto, no se afirma que los nuevos workflows, el análisis, las pruebas Flutter o el build Android hayan pasado en este commit.

CodeMagic está configurado para ejecutar en push a `main`: Flutter stable, `flutter pub get`, `flutter analyze --no-pub`, las dos pruebas Python, `flutter test`, compilación y verificación de firma. La caché de pub/Gradle mejora builds posteriores, pero no elimina por sí misma un timeout al descargar el SDK de Flutter. La descarga del SDK ocurre antes de los scripts del workflow.

## Puertas obligatorias antes de distribuir

1. Confirmar en CodeMagic un build del SHA actual, con `flutter analyze`, ambas regresiones Python y `flutter test` en verde.
2. Confirmar `bash tool/compile_aura.sh` y `bash tool/compile_aura.sh --verify-artifact`.
3. Para producción, configurar `AURA_KEYSTORE_PATH` o `AURA_KEYSTORE_BASE64`, `AURA_STORE_PASSWORD`, `AURA_KEY_ALIAS` y `AURA_KEY_PASSWORD`; activar `AURA_REQUIRE_RELEASE_SIGNING=true`. Un APK firmado con debug solo sirve para pruebas.
4. Verificar applicationId, ABI, certificado SHA-256 y APK/AAB descargado.
5. Completar la matriz física de Android: autenticación, permisos VPN, inicio/parada, revocación, Wi-Fi↔datos móviles, pérdida/recuperación de red, IPv4/IPv6, DNS, TCP/UDP, batería, temperatura, ANR y reinicio del proceso.
6. Capturar evidencia de conectividad y fugas. No activar ni promocionar reglas SNI hasta diseñar e integrar reensamblado TCP seguro y probarlo con tráfico real.

## Decisión de entrega

**Estado: candidato de entrega técnica para CI y validación en dispositivo; no listo para distribución pública como protección de producción.**

La compilación, incluso si pasa, no demuestra cobertura completa ni funcionamiento en todos los dispositivos. Las funciones de alto impacto siguen requiriendo confirmación explícita de la persona usuaria. No se deben prometer protección del 100 %, detección universal de malware ni borrado absoluto de memoria.
