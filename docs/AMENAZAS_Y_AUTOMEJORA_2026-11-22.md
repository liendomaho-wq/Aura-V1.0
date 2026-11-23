# Amenazas, actualizaciones y automejora: qué es real y qué no

Fecha: 2026-11-22

## 1. Sistema de amenazas

### Lo que ya existe

- `lib/services/aura_threat_correlator.dart`: agrupa eventos DNS/SNI
  bloqueados en una ventana de 10 minutos, conserva hasta 500 eventos, calcula
  severidad (baja/media/alta), atribuye la app de origen y adjunta indicadores
  del escaneo de aplicaciones.
- `AuraLocalTelemetry`: cola local de eventos; no se envía a ningún servidor.
- Motor DNS/SNI, clasificador DGA/phishing, auditoría de apps y postura del
  dispositivo.
- `AgentEvent` ya transporta evidencia verificable de cada herramienta.

Es decir: **hay detección y correlación, pero no un sistema de casos**. Falta
convertir alertas sueltas en un expediente que el usuario pueda entender y
cerrar.

### Lo que propongo implementar

**Corte 1 — Centro de amenazas local**

1. `AuraThreatCase`: identificador derivado del contenido (no del usuario),
   primera/última observación, severidad, confianza, señales de origen,
   dominio/paquete, técnica MITRE Mobile cuando corresponda, acciones
   recomendadas y estado (`nueva`, `en revisión`, `mitigada`, `descartada`).
2. Deduplicación entre sesiones y persistencia cifrada local, con retención
   configurable (30 días por defecto).
3. Fusión de fuentes: eventos bloqueados, hallazgos del escáner, postura
   (root/emulador/overlay/accesibilidad) y brechas de cobertura (QUIC/ECH).
4. Evidencia enlazada: cada frase del caso apunta al evento o hallazgo que la
   sostiene. Sin evidencia, no hay caso.
5. Acciones: bloquear dominio, aislar app, abrir ajustes, descartar. Todas pasan
   por las herramientas y confirmaciones existentes; ninguna acción destructiva
   se automatiza.

**Corte 2 — Detección más allá del bloqueo**

- Reglas con versión y explicación: DGA/phishing de alta confianza, app con
  accesibilidad y overlay, intentos de evasión del túnel, resolución DNS
  cifrada no inspeccionable.
- Aprendizaje de falsos positivos **solo local**: el usuario marca un caso como
  descartado y Aura ajusta su allowlist, no un modelo remoto.

**Corte 3 — Inteligencia firmada opcional**

- Paquete de IOC (dominios/hashes) descargado como artefacto firmado, igual que
  el modelo. Se instala solo si la firma y el SHA-256 son válidos.
- Nunca se sube historial de navegación, lista de apps ni identificadores.

### Lo que no voy a hacer

- Inventar alertas o métricas para que la pantalla se vea activa.
- Presentar heurísticas como veredictos.
- Enviar telemetría a un servidor propio para «mejorar el sistema».

## 2. Internet, actualizaciones y automejora

### Lo que ya existe

- `update_defenses` descarga el modelo de 500 árboles desde GitHub Pages junto
  con su `.sha256` y su firma RSA, valida ambos y lo instala cifrado para el
  dispositivo. Si falla, cae a las reglas locales.
- La descarga del modelo LLM local es explícita, con consentimiento y SHA-256.

Eso ya es un canal de actualización de **datos y modelos**, no de código.

### ¿Se puede conectar a internet para buscar actualizaciones?

Sí, con un canal firmado:

1. Manifiesto `aura-update.json` firmado con la misma clave que los artefactos.
2. Campos: esquema, canal, `versionCode`, versión mínima, artefactos con URL,
   SHA-256, tamaño y firma, más un puntero de rollback.
3. Comprobación manual o periódica **con consentimiento**, sin identificadores:
   una petición GET a un archivo estático.
4. TLS con pinning, límite de tamaño, timeout, instalación atómica y rollback al
   artefacto anterior si la validación falla.

Transparencia: cualquier servidor ve la IP y la hora de la petición. Si quieres
evitar incluso eso, la actualización debe ser manual/offline (importar el
archivo firmado). No se puede prometer «cero información» y además descargar de
un servidor.

### ¿Aura puede corregir su propio código?

**No en producción, y no debería.** Razones concretas:

- Flutter en Android compila AOT: no hay forma de sustituir código en caliente
  sin un intérprete y sin romper la firma de la app.
- La app verifica su propia integridad y firma. Un mecanismo que reescribe su
  código anula esa garantía y convierte cualquier fallo en ejecución remota de
  código.
- Una actualización silenciosa de código es exactamente el vector que un
  adversario querría. No se puede vender como «automejora» y a la vez como
  seguridad.

### Lo que sí se puede hacer, sin engañar

1. **Autorreparación de estado**: al arrancar, verificar modelo, configuración,
   base local y servicio VPN; si algo está corrupto, restaurar el último
   artefacto firmado válido o el paquete base, y registrar el incidente.
2. **Actualización firmada de modelos/reglas/IOC** con rollback y etapas.
3. **Automejora supervisada**:
   - Aura detecta localmente umbrales o reglas candidatas a partir de casos
     etiquetados por el usuario.
   - Genera una propuesta **sin datos personales** (solo métricas agregadas o
     eventos sintéticos).
   - El usuario decide exportarla; el repositorio la evalúa con el corpus, el
     gate del clasificador y las pruebas de seguridad.
   - Una persona la revisa y se publica una versión firmada.
4. **Actualización de la app** por Play Store o APK firmado con confirmación del
   usuario. Aura puede avisar; nunca instalar sola.

## 3. Privacidad

- Por defecto: cero telemetría, cero cuentas, cero identificadores.
- Las actualizaciones envían solo la petición del manifiesto (IP visible para el
  servidor).
- Los casos de amenaza y la evidencia viven en el dispositivo y se borran con la
  purga criptográfica.
- Cualquier exportación es una acción explícita del usuario y se muestra antes
  de compartir.

## 4. Orden recomendado

1. Diseño del núcleo (prototipo ya disponible) y migración visual de la pantalla
   principal sin tocar la lógica.
2. Centro de amenazas local (casos + evidencia + acciones).
3. Canal de actualización firmado con manifiesto y rollback.
4. Automejora supervisada y exportación opt-in.

Cada corte debe pasar por CI y por una prueba en dispositivo antes de decir que
está terminado.
