# Fase 2 — qué tiene que hacer el dueño en el TECNO POVA 5

Teléfono: TECNO POVA 5, 8 GB, Android 14 (API 34). Un emulador con Android 16 no sustituye estos pasos.

El Escudo es un filtro en el propio teléfono. No envía el tráfico a un servidor de Aura. El DNS del túnel es el resolver local `10.0.0.3`; la salida usa la red Wi‑Fi o los datos móviles. Bloquear `ejemplo.com` también bloquea `a.ejemplo.com`, y no bloquea `ejemplo.com.otro.test`.

## Antes de instalar: la firma puede borrar los datos

Mientras no exista un keystore de prueba fijo, cada APK nuevo puede llevar un certificado distinto. Android rechaza la actualización (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Desinstalar **borra** SecureVault, el modelo descargado y los ajustes.

El `applicationId` sigue siendo `com.ciberdefensa.aura`. No se ha cambiado.

Hasta crear el keystore de abajo, haz la prueba de migración solo si aceptas perder los datos actuales, o no desinstales y quédate en el APK que ya tienes.

## Cómo crear el keystore fijo (una sola vez, en un ordenador)

Hace falta un ordenador con Java (`keytool`) una vez. El teléfono solo no puede generar el archivo.

```bash
keytool -genkeypair -keystore aura-debug.keystore -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
base64 -w 0 aura-debug.keystore > aura-debug.keystore.b64
```

En macOS, `base64 -i aura-debug.keystore` sin `-w`. Guarda el `.keystore` en un sitio privado. No lo subas a Git ni lo pegues en el chat.

### GitHub (repositorio liendomaho-wq/Aura-V1.0)

Settings → Secrets and variables → Actions → New repository secret. Crea estos cuatro:

| Nombre | Valor |
|---|---|
| `AURA_DEBUG_KEYSTORE_BASE64` | el contenido de `aura-debug.keystore.b64` (una sola línea) |
| `AURA_DEBUG_STORE_PASSWORD` | `android` si usaste el comando de arriba |
| `AURA_DEBUG_KEY_ALIAS` | `androiddebugkey` |
| `AURA_DEBUG_KEY_PASSWORD` | `android` |

Si faltan, el build avisa con `::warning::` y puede cambiar de certificado. Las contraseñas no se guardan en `GITHUB_ENV`: cada paso de Gradle las recibe aparte.

### CodeMagic

Crea el grupo secreto `aura_debug_keystore` antes del próximo build de `android-debug`. El workflow lo nombra. Si el grupo no existe, CodeMagic no arranca ese workflow. Puede estar vacío hasta que pegues las cuatro variables, marcadas como secretas, con los mismos nombres y valores. No hace falta pegarlas en `codemagic.yaml`.

A partir del primer APK firmado con esa clave, las siguientes actualizaciones conservan los datos. El APK anterior, firmado con otra clave, igual exige una desinstalación.

## Pruebas en el teléfono

Instala el APK debug del SHA que indique el informe (el que tenga el Android Debug Build en verde).

1. Abre Aura. En la consola el control se llama **Escudo**. El permiso que pide Android sigue diciendo VPN: es el del sistema.
2. Activa el Escudo y acepta el permiso. Debe aparecer el icono de VPN de Android. Debajo del botón, **WiFi** o **Datos móviles**, según la red real.
3. Con el Escudo activo, pasa de Wi‑Fi a datos y al revés. La etiqueta tiene que cambiar y coincidir con la red por la que sale el túnel. El icono de VPN no debe desaparecer.
4. Pulsa el botón para apagar. El icono de Android desaparece y Aura muestra **DEFENSA: OFF**.
5. Vuelve a activarlo y pulsa **Detener** en la notificación. Mismo resultado.
6. Apagado, cambia de red o enciende el modo avión y quítalo. El Escudo no debe encenderse solo. En modo avión la etiqueta es **Sin conexión**.
7. Persistencia al actualizar, no una migración de la bóveda v9 a v10. Solo si el APK nuevo usa la misma firma que el que ya tenía datos:
   - Anota que puedes abrir Aura y que un ajuste local sigue ahí.
   - Instala la actualización encima, sin desinstalar.
   - Abre Aura otra vez. El ajuste tiene que seguir. Si Android pide borrar la app, para: la firma cambió y no se puede comprobar que los datos sobreviven.
8. No pulses la purga (`CONFIRMO` sobre borrar la bóveda) si quieres conservar esos datos. No hay pantalla de la bóveda; la purga es solo por esa orden. Si algún día la ejecutas, desaparecen los datos guardados. La clave de cifrado se queda hasta el siguiente arranque, así lo que Aura escriba en esa misma sesión se puede leer al reabrirla. No se pide huella ni StrongBox para usar el Escudo.
9. Revocación. Con el Escudo activo, en Ajustes de Android quita el permiso de la VPN (o desconecta Aura desde el diálogo del sistema). Tiene que aparecer un aviso de que el Escudo fue revocado, el icono de VPN desaparece y Aura queda en **DEFENSA: OFF**. No debe volver a encenderse solo al cambiar de red.
10. Always-on y bloqueo. En Ajustes → Red → VPN, marca Aura como «VPN siempre activa».
    - Sin «Bloquear conexiones sin VPN»: detén el Escudo desde Aura. Tiene que seguir apagado y mostrar un aviso. No debe quedarse el teléfono sin red y sin explicación.
    - Con «Bloquear conexiones sin VPN»: si pulsas Detener, el Escudo no se apaga. Tiene que salir un aviso que diga que el bloqueo dejaría el teléfono sin red y cómo quitarlo en Ajustes → Red → VPN. El icono de VPN sigue. Si lo habías detenido antes de activar el bloqueo, Android puede volver a levantarlo y Aura dice que el bloqueo lo exige.
11. Notificaciones denegadas. En Ajustes de la app, niega las notificaciones. Activa el Escudo. Anota si Android lo deja en primer plano y si el botón **Detener** no aparece. El Escudo no debe fingir que está apagado si el icono de VPN sigue.
12. Reinicio. Con el Escudo activo, reinicia el teléfono. Anota si vuelve solo. Si lo habías detenido antes del reinicio, no debe encenderse solo, salvo que el paso 10 (bloqueo) esté activo.
13. Fugas. Sigue `docs/ANDROID_TRAFFIC_VALIDATION.md` en este mismo teléfono: IPv4, IPv6 y DNS, con el Escudo activo y otra vez apagado. Esta fase no da por buena esa medición; anota lo que veas y no marques «cero fugas».

Anota el SHA del APK, si tuviste que desinstalar, y el resultado de cada paso.
