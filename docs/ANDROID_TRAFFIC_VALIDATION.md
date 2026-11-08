# Tráfico Android real — protocolo reproducible, pendiente de dispositivo

**Todos los casos de este documento están PENDIENTES DE DISPOSITIVO.** Un
comando preparado, un test JVM o un handshake local no es una ejecución física.
No usar root, Shizuku, Superuser, listeners sustitutos de HEV ni certificados TLS
ignorados. Ejecutar únicamente contra infraestructura y dispositivos autorizados.

## 1. Identidad y condiciones

Registrar SHA fuente, enlace del build, SHA-256 del APK, certificado y modo debug.
Usar un teléfono físico; referencia: Redmi Note 15 Pro Plus 5G, 8 GB, Android 16.
Anotar build OEM/HyperOS, parche, ABI, red, operador y si realmente hay IPv6.
Repetir aparte en API 24 y otras versiones relevantes: minSdk no prueba compatibilidad.

En la estación de trabajo, seleccionar explícitamente el dispositivo autorizado:

```bash
: "${AURA_DEVICE_SERIAL:?Selecciona el serial real mostrado por adb devices -l}"
adb devices -l
adb -s "$AURA_DEVICE_SERIAL" shell getprop ro.product.model
adb -s "$AURA_DEVICE_SERIAL" shell getprop ro.build.version.release
adb -s "$AURA_DEVICE_SERIAL" shell getprop ro.build.version.security_patch
adb -s "$AURA_DEVICE_SERIAL" shell getprop ro.build.fingerprint
adb -s "$AURA_DEVICE_SERIAL" shell dumpsys package com.ciberdefensa.aura
adb -s "$AURA_DEVICE_SERIAL" logcat -v threadtime 'AuraVPN:V' '*:S'
```

Conservar logs locales protegidos y redactar datos personales antes de compartir.
No leer ni registrar credenciales de usuario, claves de SecureVault o el YAML VPN
con `cat` en la terminal. Si adb no está autorizado o un comando está denegado,
parar ese paso y pedir al propietario que autorice la depuración; no elevar privilegios.

Requisitos externos que debe suministrar el propietario:

- Servidor HTTPS controlado con certificado válido y un archivo binario no vacío
  (recomendado: 256 KiB), con SHA-256 calculado allí e independiente del cliente.
- Servidor `iperf3` propio accesible por IPv4 y, para el caso IPv6, por IPv6 real.
- Zona DNS de prueba y acceso a logs de su servidor/resolver controlado.
- Cliente de tráfico como app Android normal (por ejemplo, terminal autorizado
  con `curl`, `dig` e `iperf3`). **No ejecutar el cliente en el PC y confundirlo
  con tráfico que entra al TUN del teléfono.**

Guardar la salida sin VPN como línea base y repetir con Aura. Registrar por
separado ahorro de batería/always-on/«bloquear conexiones sin VPN»; no atribuir a
Aura una propiedad suministrada por Android o por la red.

## 2. Listener HEV real: rechazo, RFC 1929 y salida autenticada

Con APK **debug** del SHA candidato, abrir Aura y activar su VPN por la UI,
aceptando el consentimiento de Android. Este probe usa `run-as` exclusivamente
porque el APK es depurable; no funciona ni debe forzarse en una instalación release.
No necesita root y no arranca otro proxy.

En la estación, indicar los datos reales del servidor controlado:

```bash
: "${AURA_TEST_TLS_HOST:?Nombre DNS real del servidor HTTPS controlado}"
: "${AURA_TEST_TLS_PATH:?Ruta ASCII real del archivo binario controlado}"
: "${AURA_TEST_PAYLOAD_SHA256:?Digest real calculado en ese servidor}"
python3 tool/device_socks5_probe.py \
  --serial "$AURA_DEVICE_SERIAL" \
  --host "$AURA_TEST_TLS_HOST" \
  --path "$AURA_TEST_TLS_PATH" \
  --sha256 "$AURA_TEST_PAYLOAD_SHA256"
```

El script crea un `adb forward` con puerto efímero, lee las credenciales privadas
solo en memoria y conecta al listener **HEV real** del dispositivo. Exige:

1. rechazo de SOCKS5 `NONE`;
2. rechazo real de contraseña incorrecta;
3. autenticación con las credenciales efímeras actuales;
4. `CONNECT` confirmado, TLS con validación de certificado y descarga completa
   cuyo SHA-256 coincida con el calculado en el servidor.

Un error de autenticación, TLS, contenido o limpieza del forward produce código
no cero. No se imprimen secretos. La limpieza de bytearrays es de mejor esfuerzo:
Python, adb y el SO pueden conservar copias inmutables; no es borrado forense.

**Límite:** este probe entra por el listener mediante adb, no por el TUN. La
conexión del cliente HEV del TUN con el listener debe probarse además con tráfico
de una app normal, como en el apartado siguiente. Ninguno demuestra ausencia de
fugas por sí solo. No presentar el test JVM con pipes como una sesión HEV real.

## 3. TUN: TCP, UDP, DNS e IPv4/IPv6

En el servidor controlado, como usuario normal, iniciar `iperf3 -s -p 5201` y
conservar sus logs. Permitir el puerto solo para los clientes autorizados según
la política de esa infraestructura. No cambiar firewalls ajenos.

En el **cliente del teléfono**, con los valores reales de ese entorno:

```bash
: "${AURA_TEST_IPV4:?IPv4 real del servidor iperf3 propio}"
: "${AURA_TEST_HTTPS_URL:?URL HTTPS real del archivo controlado}"
: "${AURA_TEST_DNS_NAME:?FQDN de la zona DNS propia}"
iperf3 -4 -c "$AURA_TEST_IPV4" -p 5201 -t 10 --json
iperf3 -4 -c "$AURA_TEST_IPV4" -p 5201 -t 10 -u -b 1M -l 1200 --json
curl --fail --show-error --max-time 20 --http1.1 "$AURA_TEST_HTTPS_URL" -o aura-probe.bin
sha256sum aura-probe.bin
dig "$AURA_TEST_DNS_NAME" A +time=3 +tries=1
dig "$AURA_TEST_DNS_NAME" AAAA +time=3 +tries=1
dig "$AURA_TEST_DNS_NAME" A +tcp +time=3 +tries=1
```

Con IPv6 realmente disponible, repetir con `iperf3 -6 -c "$AURA_TEST_IPV6"` y
`curl -6`, requiriendo antes que `AURA_TEST_IPV6` contenga la dirección real. Si
no existe conectividad IPv6, el resultado es **NO PROBADO**, no PASS.

Validar bytes y digest en ambos extremos, recepción UDP y pérdida, además del
resultado de consola. El transporte UDP configurado por HEV es `udp: 'tcp'`;
registrar rendimiento y semántica observados, no asumir UDP nativo equivalente.
El mapdns puede entregar direcciones internas sintéticas por diseño: documentar
esa política y comprobar resolución/conexión contra los logs del servidor real,
no comparar ciegamente su respuesta con la de un resolver externo.

Para fugas, comparar IP de origen y consultas DNS que **el servidor realmente
recibió** antes, durante y tras la VPN, y durante cada cambio de red. Esta es una
VPN local, no un servicio de anonimización: conservar la misma IP pública puede
ser correcto y no es una prueba de fuga ni de túnel funcional. Comprobar que no
hay paquetes que evadan el TUN durante recuperación usando instrumentación de
red autorizada; sin esa evidencia, dejar «fugas» pendiente.

## 4. Fallo real de recuperación y reactivación (defecto A)

1. Verificar tráfico real y el probe autenticado. Anotar interfaz TUN y red
   subyacente observadas con `dumpsys connectivity` si Android permite la consulta.
2. Desde ajustes del teléfono, quitar Wi-Fi y datos hasta no tener red física.
   Verificar que Aura informa forwarding detenido y conserva el TUN. No deducir
   fail-closed solo por el icono de VPN.
3. En un terminal normal del teléfono, **reservar realmente** el puerto 18763
   mientras el worker HEV está detenido. No servir SOCKS ni fingir una respuesta:

   ```bash
   python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",18763)); print("Puerto reservado; liberar con Ctrl+C"); input()'
   ```

   Si el bind falla porque HEV sigue vivo, conservar el error y no declarar
   inducido el fallo. No matar procesos con privilegios.
4. Restaurar la red. El conflicto de puerto debe impedir el listener real y
   producir un fallo de recuperación verificable en logs/estado. Confirmar que
   no se anuncia activo y que el tráfico sigue retenido, no que sale sin filtrar.
5. Liberar el puerto (Ctrl+C). Pulsar activar de nuevo **sin stopShield previo**.
   Verificar que reutiliza el TUN válido, termina el request correcto y solo
   anuncia activo después de worker vivo y handshake autenticado. Repetir el
   probe y el tráfico TCP/UDP/DNS, con sus datos reales.
6. Repetir la recuperación mediante un callback real de la **misma** red:
   registrar el identificador de `Network` antes/después y observar
   `onCapabilitiesChanged`/`refreshUnderlyingNetwork` con Android Studio en debug.
   La condición `selected == previous` debe cumplirse de verdad y el worker debe
   estar detenido. No invocar un callback falso ni sustituir ConnectivityManager.
   Si el sistema no produce ese callback, este subcaso queda **PENDIENTE**.
7. Repetir con aislamiento de pánico: un callback o start normal no puede
   reanudar forwarding hasta la salida explícita del aislamiento.
8. Repetir Wi-Fi → datos → Wi-Fi, pérdida total/restauración y al menos diez
   ciclos start/stop. Detener durante establecimiento TUN, arranque JNI y espera
   SOCKS. Medir ANR/latencia de parada y comprobar workers/sockets/callbacks sin
   huérfanos. Correlacionar solicitudes; un timeout no prueba apagado.

La reserva de puerto es una inyección de fallo real del sistema, **no** un mock de
HEV ni evidencia de protección. No dejarla ejecutándose al terminar.

## 5. Cobertura selectiva, integridad y datos

- Aplicar una regla local a un dominio benigno controlado mediante la confirmación
  de Aura; contrastar evento, conexión y log de servidor. No usar destinos dañinos.
- ECH, DoH personalizado, QUIC/HTTP3 y conexión directa por IP requieren casos
  independientes. Usar `curl --http3-only` solo si su build lo soporta y el servidor
  tiene HTTP/3. No afirmar inspección/descifrado de contenido cifrado por un fallo
  de conexión, una lista de IP o una regla de puerto.
- Probar USB debugging activado con build no debug y certificado permitido: la
  VPN no debe apagarse por ADB. El probe `run-as` no aplica a release. Adjuntar un
  depurador a release es un caso distinto y conserva su política de integridad.
- Actualizar una instalación v9 autorizada con datos de prueba conservados hacia
  v10; probar interrupción/backup, corrupción y recuperación sin reset silencioso.
  Respaldar los datos según el contrato de producto; no borrar secretos para pasar.
- BiometricPrompt sin CryptoObject sigue siendo una puerta de UI; no certificar
  vinculación de biometría con cada operación criptográfica.

## 6. Registro por caso

Usar la plantilla de `RELEASE_AND_DEVICE_VALIDATION.md`: fecha UTC, SHA, enlace de
run, APK/digest/certificado, modelo/build Android, precondiciones, comando exacto,
salida y logs de ambos extremos, resultado PASS/FAIL/NO PROBADO y defecto abierto.
No marcar «VPN funcional», «sin fugas» o «compatible con Android 16» hasta
completar los casos aplicables sobre el SHA candidato y hardware de referencia.
