# Aura V1.0 — auditoría de preparación para pruebas

Fecha: 2026-11-02  
Rama auditada: `main`  
Objetivo: consolidar el estado verificable antes de pruebas en un segundo dispositivo.

## Criterio de aceptación

Una capacidad solo puede marcarse como operativa cuando existe una implementación conectada, un resultado observable y una prueba reproducible. La compilación por sí sola no acredita protección. Las pruebas de fuente no sustituyen pruebas instrumentadas ni validación en hardware.

## Correcciones realizadas en este ciclo

- Se corrigieron cinco patrones regex sobreescapados en `tool/test_vpn_config_template.py`, que impedían localizar funciones y bloques del código Kotlin/C durante las verificaciones estáticas.
- Se eliminó el fallback de autenticación de `AuraCoreScreen`: si el canal nativo no confirma autenticación, la consola permanece bloqueada. La opción de continuar sin bloqueo local sigue siendo una decisión explícita del usuario en el flujo inicial, no un fallback silencioso por error.
- Se añadió una comprobación de regresión estática para impedir que vuelva a introducirse el bypass silencioso de autenticación.

## Cobertura de red comprobada en código

- El servicio VPN crea una interfaz TUN con rutas IPv4 e IPv6 por defecto.
- El motor tun2socks usa un listener SOCKS5 local ligado a loopback y sockets salientes protegidos contra recursión VPN.
- La pérdida de la red física detiene el forwarding y el código contempla recuperación cuando vuelve la conectividad.
- El clasificador del ingreso TUN descarta DoT/DoQ en puertos reconocidos y UDP/443 hacia un conjunto limitado de IP de resolutores conocidos.
- La reputación IP se actualiza en segundo plano y su fallo se reporta como cobertura reducida, no como éxito.

## Limitaciones que NO deben presentarse como protección completa

- DNS cifrado: la cobertura es selectiva. No equivale a bloqueo universal de DoH, DoT o DoQ. DoH sobre TCP/443 y resolutores no incluidos pueden evadir la clasificación.
- SNI: existe parser y almacenamiento de reglas, pero la auditoría de fuente no encontró una llamada de inspección SNI integrada en el camino de paquetes del túnel. Registrar reglas no demuestra que el tráfico esté siendo inspeccionado ni bloqueado. Hasta integrar un reensamblado TCP seguro y probarlo con tráfico real, SNI debe mostrarse como no operativo para enforcement.
- VPN: la existencia de TUN y tun2socks no demuestra por sí sola que todas las rutas, DNS, IPv6, UDP, suspensión, roaming y reconexión funcionen correctamente en todos los fabricantes.
- Escáner de aplicaciones: usa metadatos y heurísticas disponibles para la app; no ejecuta, descompila ni certifica que una app sea malware. No sustituye Play Protect.
- IA local: es clasificación heurística/ML con cobertura limitada; no debe anunciarse como detección garantizada de malware ni como protección universal.
- Memoria segura: los buffers nativos pueden limpiarse, pero copias Dart/VM y cadenas inmutables no pueden garantizarse borradas por el código actual. La documentación y mensajes no deben prometer borrado absoluto de memoria.
- Biometría: el acceso sin bloqueo del dispositivo es una opción explícita de menor seguridad. En ese modo debe mantenerse visible el estado degradado y no afirmarse que la identidad fue verificada.

## Validaciones automatizadas necesarias en CI

1. `python3 tool/test_vpn_config_template.py`
2. `python3 tool/test_aura_sni_firewall.py`
3. `flutter analyze --no-pub`
4. `flutter test --reporter expanded`
5. `bash tool/compile_aura.sh`
6. `bash tool/compile_aura.sh --verify-artifact`
7. Verificación del APK/AAB: firma de producción, applicationId, ABI y artefacto generado.

No se marca ninguna de estas validaciones como aprobada en este documento: deben confirmarse con logs del pipeline del commit correspondiente.

## Matriz obligatoria para el segundo dispositivo

- Android: versión, fabricante, modelo, ABI y parche de seguridad.
- Arranque: bloqueo fuerte, credencial del dispositivo, dispositivo sin bloqueo, cancelación y fallo del canal nativo.
- VPN: permiso concedido/denegado/revocado, inicio/parada, pérdida de Wi-Fi, transición Wi-Fi↔datos móviles, pérdida total de red y recuperación.
- Tráfico: IPv4/IPv6, DNS normal, TCP, UDP/QUIC, DoT y resolutores DoH conocidos y desconocidos. Capturar conectividad antes/después y confirmar que no hay fuga silenciosa.
- Aislamiento de emergencia: confirmar que el forwarding se detiene y que la interfaz queda en descarte; confirmar que reanudar exige estado válido.
- Motor de reputación: modelo válido, firma inválida, digest incorrecto, modelo ausente, feed remoto no disponible y rollback.
- Privacidad: telemetría desactivada por defecto, consentimiento explícito, almacenamiento local, exportación/borrado y ausencia de datos sensibles en logs.
- UX/IA: instrucciones válidas, ambiguas, malformadas, acciones que requieren confirmación y respuestas cuando el motor nativo no está disponible.
- Rendimiento/estabilidad: batería, temperatura, memoria, ANR, reinicio del proceso, suspensión y reanudación.

## Estado de salida

**Estado: candidato para validación automatizada y pruebas de dispositivo; no certificado como 100% funcional.**

No se debe distribuir como protección de producción hasta que CI esté verde, el artefacto esté firmado con el certificado de producción esperado y la matriz física de red/seguridad haya sido completada. El operador conserva la decisión de activar VPN, aislamiento y bloqueos; el agente no debe ejecutar acciones de alto impacto sin confirmación explícita.
