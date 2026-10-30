# Aura — rediseño de ciberdefensa centrado en IA

## Principios

- La conversación con Aura es la interfaz principal; no se usa un dashboard convencional como experiencia por defecto.
- El agente coordina herramientas concretas. El modelo de lenguaje nunca ejecuta operaciones arbitrarias por sí mismo.
- Toda acción debe tener resultado verificable, registro local y un estado explícito: completada, parcial, denegada o no disponible.
- La aplicación funciona sin root y respeta los permisos y límites de Android.
- La VPN local es un módulo opcional, no un requisito para abrir Aura.
- No se promete protección absoluta ni cobertura de capacidades que Android no expone.

## Arquitectura objetivo

1. **Interfaz conversacional:** texto y voz, identidad animada local, historial legible y presentación de resultados.
2. **Orquestador de agente:** interpreta la intención, crea un plan, selecciona herramientas registradas y aplica políticas.
3. **Motor de políticas:** valida alcance, permisos, consentimiento, riesgo y precondiciones antes de ejecutar.
4. **Herramientas Android:** inventario de apps visible para el paquete, revisión de permisos expuestos, ajustes del sistema, almacenamiento seguro y notificaciones.
5. **Motores de protección:** reputación de dominios, bloqueo DNS, análisis estático permitido de archivos, auditoría de red y VPN local opcional.
6. **Inteligencia de amenazas:** fuentes verificadas, caché con caducidad, procedencia y controles contra datos manipulados.
7. **Verificación y auditoría:** cada herramienta devuelve datos estructurados; la IA no puede declarar éxito si el motor no lo confirma.

## Autonomía segura

- Automático: lectura, análisis, clasificación, consultas de reputación y bloqueos de dominios de alta confianza mediante políticas activadas por el usuario.
- Confirmación: cambios de configuración, bloqueo de aplicaciones cuando Android lo permita, aislamiento de red y operaciones que afecten conectividad.
- No permitido: root, vigilancia oculta, interceptación de contenido TLS, desinstalación silenciosa de apps de terceros o acciones sobre sistemas ajenos sin autorización.
- Acciones destructivas requieren confirmación explícita y deben explicar impacto y reversibilidad.

## Etapas de implementación

### Etapa 1 — experiencia y estabilidad
- Identidad visual midnight/cyan/violet.
- Avatar animado local, sin dependencia de red ni SDK adicional.
- Conversación principal y composición de mensajes.
- Conservar historial, telemetría, auditoría, controles de privacidad y accesibilidad existentes.
- Validar Flutter analyze, pruebas unitarias/widget y compilación Android.

### Etapa 2 — agente ejecutor
- Inventario tipado de herramientas y esquemas de entrada/salida.
- Política central de permisos y confirmaciones.
- Plan de tareas con progreso, cancelación y recuperación.
- Verificación post-acción y bitácora de resultados.
- Pruebas de prompt injection y entradas maliciosas provenientes de feeds.

### Etapa 3 — módulos Android
- Auditoría de aplicaciones y permisos realmente expuestos por Android.
- Protección web/DNS con feeds firmados y actualización segura.
- Privacidad, indicadores de rastreo y revisión de ajustes accesibles.
- Diagnóstico de red y VPN local opcional, con pruebas de fugas y estabilidad.

### Etapa 4 — inteligencia avanzada
- Correlación de eventos, reputación y detección de anomalías.
- IA local para clasificación privada y funcionamiento degradado.
- Modelo remoto opcional para razonamiento complejo, con minimización de datos y consentimiento.
- Evaluación de precisión, falsos positivos, latencia y consumo energético.

### Etapa 5 — validación y publicación
- CI de Flutter y Android.
- Matriz de dispositivos/versiones Android sin root.
- Pruebas de red, DNS, IPv4/IPv6, reconexión, batería y privacidad.
- Verificación de APK firmado y reproducible en Codemagic.

## Estado inicial del rediseño

- Se añadió un avatar animado generado localmente con Flutter CustomPainter.
- La pantalla principal muestra la identidad de Aura y el estado de trabajo del asistente.
- El flujo de eventos se presenta como conversación en lugar de líneas de terminal.
- El compositor usa lenguaje natural y mantiene entrada de voz.
- Los módulos existentes no se han eliminado.
- El rediseño todavía requiere ejecución de Flutter analyze, pruebas, build Android y validación en dispositivo.
- La reconstrucción VPN de la rama `rebuild/vpn-from-zero` continúa separada hasta completar validación técnica; no se incorpora automáticamente a main por no disponer aún de una compilación y pruebas físicas confirmadas.
