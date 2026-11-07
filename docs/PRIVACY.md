# Privacidad y tratamiento de datos — Aura Mobile Defens

**Versión documental:** 7 de noviembre de 2026  
**Aplicación:** Aura Mobile Defens 1.0.2 (`com.ciberdefensa.aura`)

Este documento describe el comportamiento observado en el código de este repositorio. Debe revisarse nuevamente si cambian endpoints, permisos, proveedores o funciones. No constituye una certificación de seguridad ni sustituye el texto legal que el responsable deba adaptar a su jurisdicción y canal de distribución.

## 1. Principios de funcionamiento

- Aura procesa localmente las órdenes del agente, la clasificación de dominios, el inventario de seguridad y las explicaciones del modelo.
- La VPN es opcional y requiere el consentimiento del sistema Android.
- La telemetría local y la telemetría remota son independientes y requieren activación explícita.
- Una instalación con la configuración predeterminada no tiene un endpoint de telemetría remota configurado.
- Aura no debe presentar seudonimización, cifrado o inferencia local como anonimización absoluta o seguridad infalible.

## 2. Datos que puede procesar

Según las funciones que el usuario active y los permisos concedidos, Aura puede procesar:

- Nombres de dominio observados y resultados de clasificación o bloqueo.
- Direcciones IP, puertos y protocolos asociados a eventos de red confirmados por el motor.
- Paquete de la aplicación que origina un evento cuando Android puede determinarlo.
- Inventario visible de aplicaciones, firmas, permisos y accesos especiales.
- Señales heurísticas de root, emulación, instrumentación, overlays y accesibilidad.
- Versión de Aura, versión del modelo, marcas temporales y resultados de herramientas.
- Audio únicamente cuando se utiliza una función de reconocimiento de voz.

El código revisado no solicita ubicación, contactos, cámara ni SMS.

## 3. Telemetría local opcional

La telemetría local está desactivada inicialmente. Si el usuario la activa y no hay un endpoint remoto configurado:

- Se conservan en el dispositivo eventos de red y resultados de dominio permitidos por esa preferencia.
- Los dominios nuevos se representan mediante **HMAC-SHA-256** con una clave protegida por SecureVault; no se guarda el dominio en claro en esos registros nuevos.
- Un HMAC es un identificador seudónimo: puede ser correlacionable y no constituye anonimización irreversible.
- La cola local está limitada a **500 eventos**.
- Al desactivar la telemetría local se elimina su cola. El usuario también puede borrar los datos de Aura desde Android o desinstalar la aplicación.

Los eventos que existen solo en la sesión en memoria desaparecen al cerrarla, aunque otras bitácoras de seguridad pueden seguir reglas de conservación distintas.

## 4. Telemetría remota opcional

El envío remoto requiere simultáneamente:

1. Un endpoint HTTPS válido configurado por el responsable de la compilación.
2. El consentimiento explícito del usuario.

Cuando ambos existen, un evento puede contener:

- HMAC del dominio;
- resultado `blocked` o `allowed`;
- fuente `ml`, `blocklist` o `allowlist`;
- versión del modelo y de Aura;
- marca temporal.

El servidor receptor y los proveedores de red también pueden observar la IP de conexión y metadatos HTTPS habituales. El destino, conservación y base legal de esos datos dependen del endpoint configurado para la distribución correspondiente. **No debe activarse un endpoint de producción sin publicar su responsable y política de conservación.**

Revocar el consentimiento cancela el trabajo de subida y elimina la cola remota pendiente almacenada localmente. No puede borrar automáticamente datos que ya hubieran sido aceptados por un servidor; esa eliminación debe gestionarse con su operador.

## 5. Conexiones a terceros

Aura puede descargar, mediante HTTPS:

- Modelo, digest y firma desde GitHub Pages.
- Feeds de URLhaus, PhishTank y OpenPhish cuando la actualización está configurada.
- Feeds de IP de Feodo Tracker para la protección VPN.
- La Model Card pública cuando el usuario decide abrirla.

Estas conexiones pueden revelar al proveedor la IP del dispositivo, fecha, User-Agent y metadatos técnicos. Descargar un feed no implica enviar el historial de navegación del usuario. PhishTank requiere una credencial de aplicación configurada en builds que utilicen ese feed; dicha credencial no debe publicarse en el repositorio.

## 6. Voz y texto a voz

El texto a voz usa el motor TTS disponible en Android. El reconocimiento de voz depende del proveedor Android instalado y de sus propios permisos y políticas. El repositorio no demuestra que el reconocimiento permanezca siempre offline. El usuario debe revisar la configuración de voz de su dispositivo antes de usarla con información sensible.

## 7. VPN y alcance de la inspección

Cuando el usuario activa la VPN, Android crea un túnel local para procesar tráfico y aplicar defensas. Aura puede observar metadatos necesarios para sus filtros y eventos, pero:

- no descifra ECH;
- no inspecciona de forma general el contenido HTTPS;
- no garantiza cobertura de todo DoH, QUIC, IPv6 o tráfico fuera del túnel;
- no convierte una detección heurística en prueba concluyente de malware.

El DNS local también aplica una heurística de nombres largos y diversos: una
coincidencia puede causar una respuesta NXDOMAIN incluso para un dominio legítimo.
Los dominios bloqueados por esa heurística o por una regla explícita reciben
NXDOMAIN sin direcciones de loopback. Si una consulta contiene varias preguntas
y alguna coincide, se deniega la consulta completa. Esto solo afecta a las
consultas que realmente pasan por el DNS local; no demuestra que se hayan
bloqueado todas las conexiones posibles hacia ese destino.

Por precaución, la pila del túnel está configurada para descartar datagramas
IPv4 e IPv6 que requieran reensamblaje, porque la inspección ocurre antes de que
lwIP pueda reensamblarlos. Los fragmentos atómicos IPv6 se tratan como paquetes
completos. La inspección también descarta cadenas de extensiones IPv6 que superen
su límite de ocho cabeceras o 296 bytes de desplazamiento; no los registra como
coincidencias DNS. Estas medidas pueden interrumpir aplicaciones o redes que
utilicen ese tráfico, y requieren pruebas de compatibilidad en el dispositivo.
No garantizan cobertura completa de DoH, QUIC ni ECH.

Las fugas, cambios de red y el comportamiento de cada fabricante deben comprobarse en dispositivos físicos antes de una distribución.

## 8. Almacenamiento y protección

- `allowBackup=false` y `usesCleartextTraffic=false` están configurados en el Manifest.
- SecureVault y los mecanismos de integridad protegen secretos y modelos según sus implementaciones.
- La autenticación local bloquea la consola cuando Android no confirma la identidad.
- Ningún mecanismo elimina por completo el riesgo de compromiso del dispositivo, falsos positivos o errores de implementación.

Las claves privadas, contraseñas y keystores no deben incluirse en Aura, en logs ni en el repositorio.

## 9. Permisos Android

| Permiso o capacidad | Finalidad |
|---|---|
| Internet y estado de red | Actualizaciones, telemetría opcional y funcionamiento de defensas. |
| `QUERY_ALL_PACKAGES` | Inventario y análisis de aplicaciones visible para Aura; su uso está sujeto a revisión de Google Play. |
| `RECORD_AUDIO` | Reconocimiento de voz únicamente cuando se invoca. |
| Notificaciones | Estados y alertas de protección. |
| Biometría/credencial | Autenticación local de la consola. |
| Servicio en primer plano y VPN | Mantener el túnel autorizado y mostrar su estado. |

Denegar un permiso puede limitar la función correspondiente; no debe presentarse como si la protección afectada siguiera activa.

## 10. Conservación y control del usuario

El usuario puede:

- activar o revocar telemetría local y remota;
- borrar colas locales desde los controles disponibles;
- revocar VPN, micrófono, notificaciones u otros permisos desde Android;
- borrar los datos de la aplicación o desinstalarla;
- abrir ajustes de una aplicación revisada y decidir personalmente cualquier acción.

La retención en servicios de terceros depende de sus políticas. Una futura distribución con telemetría remota debe documentar plazos de conservación del servidor antes de activarla.

## 11. Publicidad, venta y menores

El código revisado no incorpora publicidad ni venta de datos personales. Aura es una herramienta de ciberdefensa y no está diseñada para tomar decisiones automatizadas con efectos legales. Su uso por menores debe ser supervisado por el responsable del dispositivo y del canal de distribución.

## 12. Contacto y cambios

Las solicitudes sobre privacidad o este documento pueden registrarse en:

https://github.com/liendomaho-wq/Aura-V1.0/issues

Los cambios materiales en permisos, endpoints o tratamiento requieren actualizar esta política y la versión distribuida. La fecha y el commit del artefacto deben quedar registrados en la evidencia de release.
