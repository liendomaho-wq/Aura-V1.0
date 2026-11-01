# Aura — Arquitectura de producto y seguridad

**Estado:** documento de arquitectura de trabajo  
**Objetivo:** convertir Aura en una plataforma de ciberdefensa personal para Android sin root, con controles verificables y límites explícitos.

## 1. Principio rector

Aura no debe afirmar que el dispositivo está seguro simplemente porque no recibió eventos, porque una API devolvió una lista vacía o porque un modelo de IA no encontró una amenaza. Toda conclusión de seguridad debe incluir:

- qué componente realizó la comprobación;
- qué datos y superficie pudo observar;
- cuándo se realizó;
- qué controles se ejecutaron;
- qué quedó fuera del alcance;
- si la comprobación terminó correctamente.

Los estados de seguridad deben distinguir al menos: **protegido/operativo**, **amenaza detectada**, **cobertura reducida**, **auditoría incompleta** y **función no disponible**. La ausencia de evidencia nunca se convierte en evidencia de ausencia.

## 2. Identidad del producto

Aura será una interfaz conversacional con avatar, no un panel de métricas convencional. La IA coordina motores especializados, pero no sustituye controles deterministas ni decide por sí sola que una amenaza es real.

### Experiencia propuesta

1. El usuario expresa una intención en lenguaje natural.
2. Aura identifica qué comprobaciones o acciones son pertinentes.
3. Los motores locales recopilan únicamente datos permitidos por Android.
4. Las reglas deterministas y fuentes verificadas producen hallazgos trazables.
5. La IA explica los resultados en lenguaje claro, con incertidumbre y límites.
6. Las acciones sensibles requieren confirmación explícita.
7. Aura registra el resultado y permite deshacer o revisar cuando sea posible.

El avatar comunica estado y actividad, pero nunca debe simular análisis o protección que no estén ocurriendo.

## 3. Arquitectura por capas

### A. Aura Local — protección sin Internet

- inventario de aplicaciones y permisos expuestos por Android;
- revisión de servicios sensibles habilitados por el usuario;
- inspección de configuración de seguridad del dispositivo;
- análisis local de enlaces, archivos que el usuario comparte y señales de riesgo;
- almacenamiento cifrado y registro local con retención limitada;
- reglas locales y listas verificadas en caché;
- respuesta guiada y acciones nativas autorizadas.

### B. Aura Intelligence — inteligencia conectada y opcional

- reputación de dominios, IP y URL;
- descarga autenticada de reglas y listas firmadas;
- análisis asistido de incidentes complejos;
- actualización de modelos y políticas con control de integridad;
- telemetría estrictamente opcional, minimizada y revocable.

No se enviarán archivos privados, mensajes, contenido de aplicaciones ni tráfico completo por defecto. La IA remota recibirá solo el mínimo contexto necesario y autorizado.

### C. Motores especializados

- **Network Engine:** túnel local, DNS, reglas de dominio/IP, metadatos de conexión y estado de conectividad.
- **App Intelligence:** permisos solicitados/concedidos cuando Android los exponga, servicios sensibles activos, firma y señales estáticas.
- **Scam & Link Analysis:** normalización de URL, reputación, homógrafos/IDN, redirecciones y análisis de phishing.
- **Device Posture:** bloqueo de pantalla, depuración, configuración de seguridad y señales de integridad disponibles.
- **Secure Vault:** claves protegidas por Android Keystore, cifrado autenticado, migración segura y borrado verificable.
- **Incident Response:** aislamiento o bloqueo de alcance limitado, notificaciones y guía de recuperación.

Cada motor debe exponer un contrato tipado, versión, estado, alcance, timestamp, evidencia, errores normalizados y límites.

## 4. Contrato común de hallazgos

Cada hallazgo debe contener como mínimo:

- `id`: identificador único;
- `engine` y `engine_version`;
- `severity`: info, low, medium, high o critical;
- `confidence`: low, medium o high;
- `status`: observed, confirmed, mitigated, false_positive o unresolved;
- `observed_at`;
- `evidence`: referencias mínimas y redactadas;
- `scope`: qué se examinó;
- `limitations`: qué no pudo examinarse;
- `recommended_action`;
- `requires_user_consent`.

La IA puede resumir y priorizar hallazgos, pero no elevar la severidad ni ejecutar mitigaciones sin que la política determinista lo permita.

## 5. Modelo de confianza y acciones

- Lecturas locales de bajo riesgo pueden ejecutarse sin confirmación adicional cuando el usuario inicia la auditoría.
- Bloqueos, aislamiento, cambios de configuración, eliminación, envío remoto de datos o acciones que puedan interrumpir conectividad requieren confirmación clara.
- Toda acción debe validar parámetros en el lado nativo; la validación Dart no es suficiente.
- Los fallos deben ser fail-closed para operaciones de seguridad, pero no deben destruir claves, datos del usuario ni terminar abruptamente el proceso.
- Los errores visibles deben estar saneados; los registros internos no deben incluir secretos, tokens, contenido privado ni datos innecesarios.

## 6. Red y VPN local: criterio de aceptación

La VPN local solo se considera operativa cuando se demuestre en dispositivos físicos y redes distintas. Un servicio iniciado no equivale a tráfico protegido.

Matriz mínima:

- autorización, inicio, detención y revocación del permiso VPN;
- tráfico TCP y UDP;
- DNS clásico y comportamiento ante DNS cifrado;
- IPv4 e IPv6;
- Wi-Fi y datos móviles;
- cambio de red, pérdida y recuperación de conectividad;
- exclusión del propio túnel para evitar recursión;
- ausencia de fugas fuera del alcance declarado;
- reglas dinámicas y allowlist;
- respuesta a caída del feed remoto;
- consumo de batería, memoria y latencia.

Si un caso no está probado, Aura debe mostrar cobertura reducida o función no verificada. La VPN local no se presentará como un servicio VPN remoto que anonimiza o enruta el tráfico por servidores externos.

## 7. Seguridad de la aplicación y cadena de suministro

- HTTPS obligatorio; no aceptar tráfico en claro.
- Validar certificados TLS mediante el stack estándar; no desactivar la validación para resolver fallos.
- Firmar y verificar feeds, modelos y reglas antes de activarlos.
- Versionado, expiración, rollback seguro y protección contra downgrade.
- Límites de tamaño, tiempo y concurrencia para entradas y descargas.
- Secretos fuera del repositorio y de los logs.
- Firma de release separada de claves de desarrollo; no distribuir artefactos de producción firmados en DEBUG.
- Revisión de componentes nativos/JNI y límites de memoria.
- Dependencias fijadas, análisis de vulnerabilidades y actualización controlada.

## 8. Privacidad y transparencia

- permisos mínimos y explicación contextual;
- telemetría desactivada por defecto;
- consentimiento revocable y borrado de cola local al retirar consentimiento;
- minimización y retención limitada;
- datos sensibles excluidos de logs;
- inventario de aplicaciones sujeto a visibilidad y políticas de Android/Google Play;
- no inspeccionar datos privados de otras aplicaciones ni interceptar HTTPS mediante MITM.

## 9. Estándar de verificación

Usar OWASP MASVS y MASTG como marco de evaluación de la propia aplicación, cubriendo almacenamiento, criptografía, autenticación, red, plataforma, calidad de código, resiliencia y privacidad. No afirmar certificación OWASP: el estándar es una guía de requisitos y pruebas, no una certificación automática.

Cada requisito tendrá:
- identificador interno;
- riesgo y amenaza;
- implementación concreta;
- prueba automatizada;
- prueba manual/dispositivo cuando aplique;
- evidencia;
- estado: planned, implemented, automated-tested, device-tested o accepted-risk.

## 10. Fases de ejecución y puertas de salida

### Fase 0 — estabilización y verdad de estado
- eliminar falsos estados de seguridad;
- inventariar contratos Dart/Kotlin/JNI;
- revisar errores, concurrencia, ciclo de vida y permisos;
- bloquear afirmaciones de cobertura no demostradas.

**Salida:** análisis estático y pruebas de regresión aprobados; estados de error consistentes.

### Fase 1 — núcleo de confianza
- vault, criptografía, autenticación, anti-tampering no destructivo;
- firma de feeds/modelos;
- actualización y rollback;
- secretos y firma de release.

**Salida:** pruebas negativas, migración, restauración y validación de firma aprobadas.

### Fase 2 — motores locales
- auditoría de aplicaciones y permisos;
- postura del dispositivo;
- análisis de enlaces;
- evidencia y niveles de confianza.

**Salida:** datos de Android correctamente interpretados; sin falsos positivos por permisos solo solicitados o inventario incompleto.

### Fase 3 — motor de red
- ciclo de vida VPN;
- DNS, reglas, IPv4/IPv6 y recuperación de red;
- telemetría de cobertura;
- matriz real de dispositivos.

**Salida:** pruebas automatizadas y pruebas físicas documentadas; límites expuestos al usuario.

### Fase 4 — inteligencia conectada
- fuentes de reputación;
- feeds firmados;
- caché local;
- IA remota opcional y minimización de datos.

**Salida:** integridad, expiración, rollback, caída de red y consentimiento probados.

### Fase 5 — agente y experiencia Aura
- orquestador de herramientas con permisos;
- avatar y conversación;
- explicaciones basadas en evidencia;
- confirmación de acciones y registro de resultados.

**Salida:** ninguna acción sensible se ejecuta solo por una salida generada por el modelo.

### Fase 6 — release y auditoría
- MASVS/MASTG gap assessment;
- pruebas de abuso y regresión;
- rendimiento, batería y accesibilidad;
- firma de producción y revisión de políticas;
- pruebas en múltiples versiones/dispositivos Android.

**Salida:** informe de cobertura, riesgos aceptados y limitaciones conocidas.

## 11. Regla de publicación

Una función solo puede etiquetarse como **operativa** si:
1. está implementada en el código final;
2. su contrato y errores están cubiertos;
3. las pruebas automatizadas pasan;
4. se ha probado en los dispositivos/versiones Android declarados cuando depende del sistema;
5. su alcance y limitaciones están documentados.

Compilar no demuestra protección. Una prueba unitaria no demuestra compatibilidad universal. Una detección heurística no demuestra malware. Aura debe ganarse la confianza con evidencia repetible.
