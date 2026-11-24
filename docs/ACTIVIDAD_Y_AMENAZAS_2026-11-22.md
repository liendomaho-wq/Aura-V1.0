# Pantalla de actividad y sistema de amenazas: estado real

## Qué muestra hoy la pantalla de actividad

`AuraActivitySheet` se abre desde la cabecera de la consola. Reúne tres fuentes
reales y no inventa ninguna:

1. Eventos del agente de la sesión (`AgentController.history`), con inicio,
   resultado, duración y evidencia reducida.
2. Eventos de red del Escudo (bloqueos DNS/QUIC, SNI, IP directa, alertas DGA).
3. Auditoría cifrada de operaciones, que sobrevive a la sesión cuando la bóveda
   está disponible.

El límite es de 200 entradas. Una operación permanece «en curso» hasta que el
motor informa el resultado; no hay barras de progreso simuladas.

## Qué añadió este corte

- Un resumen de **detecciones locales** y un acceso «Amenazas».
- Casos derivados de `AuraThreatCorrelator` y `AuraFindingsEngine`, ordenados por
  severidad y actualidad.
- Evidencia expandible, límites explícitos y recomendación por caso.
- Acciones confirmadas: abrir la ficha de una app o solicitar aislamiento de
  emergencia.
- Un indicador visual de núcleo en la cabecera que cambia con la severidad
  máxima; es un indicador, no una animación que simule actividad.

## Detener, contener y eliminar: qué significa cada cosa

- **Detener una conexión:** el motor DNS ya bloquea el dominio observado. El
  caso lo muestra como «DNS bloqueado», no como victoria total.
- **Contener:** «Cortar red» activa el aislamiento de emergencia y descarta todo
  el tráfico hasta que el usuario lo reanude. Es global, no por app.
- **Eliminar:** una app ordinaria de Android no puede desinstalar ni forzar la
  detención de otra. Aura puede llevar al usuario a la ficha de Ajustes; la
  desinstalación sigue siendo una decisión del sistema y del usuario.

## Brechas de ciberdefensa

1. El manifiesto de blocklists se valida con SHA-256 y TLS. La verificación de
   firma RS256 ya está implementada, pero solo se activa cuando el operador
   configura `AURA_BLOCKLIST_MANIFEST_PUBLIC_KEYS` y publica el `.sig`; sin esa
   configuración sigue en modo heredado y lo registra.
2. Los casos ya persisten cifrados en `SecureVault`, con estados `abierta`,
   `en revisión`, `mitigada` y `descartada`, tope de 200 registros y retención
   de 30 días. `mitigada` exige contención real (DNS activo confirmado o
   aislamiento confirmado por el agente); no se usa para una simple revisión.
   Quedan pendientes las pruebas en dispositivo; ver
   `docs/FIRMA_MANIFIESTO_BLOCKLISTS_2026-11-22.md` para la firma.
3. No hay contención por aplicación ni respuesta automática más allá del bloqueo
   DNS y el aislamiento global.
4. Cobertura limitada: QUIC/ECH y IP directa no permiten ver el dominio; no hay
   inspección de contenido TLS ni análisis estático profundo de APK.
5. No hay mapeo MITRE Mobile ni playbooks de respuesta por caso.
6. No hay modo Device Owner/administración empresarial para controles más
   fuertes; todo depende de permisos ordinarios.
7. No hay versión iOS ni protección del sistema fuera del sandbox de Android.
8. La inteligencia de amenazas depende de feeds externos; no hay caza de
   amenazas remota (decisión de privacidad, no solo limitación técnica).

## Brechas de programación

1. `aura_core_screen.dart` supera las 2.000 líneas y mezcla presentación,
   permisos, voz y despacho; dificulta pruebas de UI y cambios visuales.
2. `agent_controller.dart` es un singleton grande; no hay inyección de
   dependencias para probar flujos completos sin canales nativos.
3. Existen dos declaraciones de `AuraIntentParser`/`AuraIntent` en el árbol;
   nunca deben importarse juntas sin alias.
4. No hay pruebas de widget para la nueva pantalla de amenazas ni pruebas
   golden del núcleo; la lógica pura sí está cubierta.
5. No hay pruebas de integración en dispositivo ni presupuesto de rendimiento
   medido en el TECNO POVA 5.
6. La persistencia de casos es un documento JSON cifrado con tope y retención,
   no una base con consultas indexadas; si el volumen crece habrá que migrar.
7. Los textos están hardcodeados en español; no hay capa de localización.
8. Varios `catch (Object)` son deliberadamente amplios para no romper la app,
   pero pueden ocultar errores de programación si no se registran localmente.
9. No hay análisis de dependencias ni fuzzing de los parsers de feeds en CI.

## Orden recomendado

1. ~~Persistencia cifrada de casos, decisión del usuario, tope y retención.~~
   Hecho, incluidos estados y playbooks; falta la prueba en dispositivo.
2. ~~Firma del manifiesto de feeds con clave pública embebida y rotación.~~
   Infraestructura y pruebas hechas; falta configurar la clave real y publicar
   el `.sig` para que la protección esté activa.
3. Pruebas de widget/golden de actividad, amenazas y núcleo.
4. Contención por app solo si se puede hacer con una API de Android que lo
   garantice; si no, mantener la verdad actual y no prometerlo.
5. Migración visual de la consola al núcleo, preservando evidencia y acciones.
