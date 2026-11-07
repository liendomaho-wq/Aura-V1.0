# Guía de release y validación en dispositivo — Aura

Esta guía separa la evidencia automática de la validación humana. Un APK generado no equivale a un release aprobado y una prueba estática no demuestra comportamiento de red en hardware.

## 1. Identidad de la compilación

Registrar antes de probar:

| Campo | Valor que debe documentarse |
|---|---|
| Commit completo | SHA de Git del código compilado. |
| PR y pipeline | URL del PR y del build de Codemagic/GitHub Actions. |
| Versión | `versionName` y `versionCode` de Gradle/pubspec. |
| Artefacto | Nombre, tamaño y SHA-256 del APK/AAB. |
| Firma | Certificado SHA-256 devuelto por `apksigner`. |
| Configuración | DEBUG de prueba o producción estricta, sin revelar secretos. |
| Dispositivo | Modelo, Android, parche, build OEM, ABI y espacio libre. |

Comandos de referencia en una estación con Android SDK:

```bash
sha256sum build/app/outputs/flutter-apk/app-release.apk
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
adb devices -l
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.security_patch
```

El certificado no debe contener `CN=Android Debug` en una entrega de producción.

## 2. Puerta automática obligatoria

Sobre el commit exacto del candidato:

```bash
flutter pub get
flutter analyze --no-pub
flutter test --reporter expanded
python3 tool/test_vpn_config_template.py
python3 tool/test_aura_sni_firewall.py
python3 tool/test_release_signing_policy.py
bash tool/compile_aura.sh
```

También deben conservarse los resultados de las pruebas Python del modelo y de las suites Android que estén configuradas. No omitir una suite para obtener un pipeline verde.

Un build Codemagic con `AURA_REQUIRE_RELEASE_SIGNING=false` produce únicamente un **artefacto DEBUG de prueba**. Sirve para instalación controlada, no para distribución.

## 3. Instalación, actualización y desinstalación

En el dispositivo de prueba:

- [ ] Instalar desde un estado limpio y abrir Aura sin crash.
- [ ] Comprobar que el paquete instalado es `com.ciberdefensa.aura` y que la versión coincide.
- [ ] Actualizar sobre una instalación anterior sin perder la configuración válida.
- [ ] Probar la migración SecureVault v9→v10 con datos anteriores y confirmar que una corrupción no reinicia secretos silenciosamente.
- [ ] Reiniciar el teléfono y abrir de nuevo.
- [ ] Desinstalar y comprobar el comportamiento documentado de datos locales y VPN.

Guardar modelo de teléfono, logs y resultado de cada paso. Si se prueba el Redmi Note 15 Pro Plus 5G, registrar también la versión exacta de HyperOS/Android.

## 4. Splash, autenticación e interfaz

- [ ] Biometría fuerte válida avanza al dashboard.
- [ ] Ausencia de biometría fuerte con credencial segura usa la credencial del dispositivo.
- [ ] Dispositivo sin bloqueo presenta las opciones y no concede acceso silenciosamente.
- [ ] Denegación/cancelación mantiene la consola bloqueada.
- [ ] Continuar sin bloqueo muestra claramente el estado inseguro.
- [ ] No hay excepciones ni franjas de overflow en 320×568, 800×600, pantalla completa y landscape.
- [ ] Probar tamaño de fuente del sistema normal y grande.
- [ ] Todos los botones permanecen alcanzables; las tarjetas desplegables abren y muestran su evidencia.
- [ ] Telemetría puede recuperarse mediante scroll después de llegar un evento nuevo.
- [ ] TalkBack/etiquetas semánticas y reducción de movimiento funcionan según lo implementado.
- [ ] El nombre visible es Aura, sin sufijos ajenos al producto.

Cualquier `RenderFlex overflow` o excepción de render es un fallo bloqueante, no un defecto cosmético aceptable.

## 5. IA y modelo local

- [ ] El modelo activo declarado es 3.0.0, con seis características y digest esperado.
- [ ] El candidato 3.1.0 no se presenta como publicado sin entrenamiento, evaluación y release explícitos.
- [ ] Hosts vacíos, IDN malformados, URLs con credenciales y entradas extremas se rechazan sin crash.
- [ ] Las explicaciones distinguen características del vector activo y señales auxiliares.
- [ ] Una firma o digest inválido impide aceptar un modelo descargado.
- [ ] La clasificación funciona sin conexión con el modelo ya instalado.
- [ ] Una clasificación no se presenta como garantía de seguridad.
- [ ] Registrar RAM, CPU y latencia en el dispositivo durante una serie medida de inferencias.

Para métricas ML, conservar dataset real, manifiesto, splits, semilla y reportes holdout. No utilizar datos semilla/sintéticos como evidencia de calidad de producción.

## 6. VPN y red — pruebas críticas en hardware

Documentar estado inicial, acción, resultado observable y logs para cada caso:

- [ ] Android muestra el diálogo de permiso VPN y Aura no lo marca como concedido antes de confirmación.
- [ ] `AuraVpnService`, TUN y HEV inician; el estado activo se anuncia solo tras verificar forwarding.
- [ ] Una conexión TCP real atraviesa el relay SOCKS5 y alcanza un destino controlado.
- [ ] Comprobar HTTP/HTTPS de salida y DNS real sin usar resultados inventados.
- [ ] Verificar rutas y tráfico IPv4 e IPv6 cuando la red los soporte.
- [ ] Ejecutar una prueba independiente de fuga DNS y de IP pública antes/después de activar la VPN.
- [ ] Wi-Fi → datos móviles → Wi-Fi sin fuga silenciosa y con recuperación verificada.
- [ ] Pérdida total de red, restauración y nueva sesión de forwarding.
- [ ] Detener desde Aura, detener desde Android y revocar el permiso VPN.
- [ ] Repetir al menos diez ciclos start/stop sin worker huérfano ni falso estado activo.
- [ ] Bloquear una regla SNI controlada y verificar el evento; probar ECH sin afirmar descifrado.
- [ ] Suspender/reanudar el teléfono y reiniciar con la VPN previamente activa.
- [ ] Medir batería, memoria, temperatura y estabilidad durante una sesión prolongada documentada.

No marcar la fase como cerrada si solo pasan pruebas unitarias o si el dispositivo no ofrece IPv6/datos móviles; ese caso debe quedar como **no probado**, no como éxito.

## 7. Protección Android y permisos

- [ ] Inventario de aplicaciones acorde a la visibilidad concedida por Android.
- [ ] Permisos peligrosos y accesos especiales reflejan el estado real del sistema.
- [ ] Root/emulador/overlays/accesibilidad se describen como señales con límites, no verdades absolutas.
- [ ] Las acciones sobre otras apps abren revisión del usuario; no se afirma aislamiento o desinstalación inexistente.
- [ ] Bloqueos y aislamiento de emergencia requieren la confirmación prevista.
- [ ] Micrófono, notificaciones, biometría y VPN denegados degradan solo la función correspondiente.
- [ ] Revisar la justificación de `QUERY_ALL_PACKAGES` para el canal de distribución elegido.

## 8. Privacidad y criptografía

- [ ] En instalación limpia no hay telemetría local/remota activa por defecto.
- [ ] Los registros locales nuevos contienen HMAC y no dominios en claro.
- [ ] Revocar consentimiento elimina las colas locales pendientes y cancela subidas.
- [ ] No hay claves privadas, tokens o secretos en APK, logs o repositorio.
- [ ] AES/HMAC, SecureVault, autenticación y corrupción de datos siguen sus suites sin errores.
- [ ] La política `docs/PRIVACY.md` coincide con endpoints y permisos del build candidato.
- [ ] Revisar licencias de dependencias directas/transitivas y conservar el informe de `flutter pub deps` y Gradle.

## 9. Firma de producción

Configurar secretos únicamente en el almacén seguro del proveedor CI, nunca en chat ni Git:

- `AURA_KEYSTORE_PATH` o el mecanismo seguro previsto por el pipeline;
- `AURA_STORE_PASSWORD`;
- `AURA_KEY_ALIAS`;
- `AURA_KEY_PASSWORD`.

Para una compilación de producción:

1. Establecer `AURA_REQUIRE_RELEASE_SIGNING=true`.
2. No habilitar `AURA_ALLOW_DEBUG_SIGNING`.
3. Ejecutar `bash tool/compile_aura.sh` y `bash tool/compile_aura.sh --verify-artifact`.
4. Verificar certificado, SHA-256, versión y ausencia de fallback DEBUG.
5. Instalar el artefacto firmado y repetir las pruebas críticas.
6. Guardar evidencia y aprobación humana antes de publicar.

## 10. Plantilla de evidencia

```text
Fecha UTC:
Commit:
Pipeline:
APK/AAB SHA-256:
Certificado SHA-256:
Dispositivo y build Android:
Caso ejecutado:
Resultado: PASS / FAIL / NO PROBADO
Evidencia (logs, capturas, mediciones):
Defecto abierto y severidad:
Aprobado por:
```

El cierre definitivo exige que las funciones anunciadas estén verificadas en el commit y hardware objetivo. Los elementos no ejecutados deben permanecer explícitamente pendientes.
