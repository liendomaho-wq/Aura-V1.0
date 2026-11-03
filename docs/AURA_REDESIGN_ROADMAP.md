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
- [x] Identidad visual midnight/cyan/violet.
- [x] Avatar animado local, sin dependencia de red ni SDK adicional.
- [x] Conversación principal y composición de mensajes.
- [x] Botón de envío conectado al controlador real de instrucciones.
- [x] Eliminar esperas artificiales y eventos de "pensamiento" fabricados; el progreso debe proceder de herramientas reales.
- [x] Mantener historial, telemetría, auditoría y controles de privacidad existentes.
- [x] Avatar con estados disponible/escuchando/analizando/protegiendo/alerta conectados al estado real de la aplicación.
- [x] Etiquetas semánticas accesibles para los estados del avatar.
- [x] Respetar la preferencia Android de reducir animaciones.
- [x] Pruebas widget de estados accesibles y movimiento reducido añadidas a CI.
- [x] Confirmar ejecución verde de las pruebas de estabilidad y accesibilidad en Codemagic (confirmación del usuario, 2026-10-30).
- [ ] Validar el avatar, accesibilidad, batería y estabilidad en dispositivos físicos.

### Etapa 2 — agente ejecutor
- [x] Inventario tipado básico de herramientas y esquemas de entrada/salida.
- [x] Exponer el escáner nativo de aplicaciones como herramienta `scan_apps` del agente, con informe estructurado y límites explícitos de interpretación.
- [x] Exponer `checkHostileEnvironment` como `audit_device`, distinguiendo auditoría incompleta, indicadores que requieren revisión y ausencia de indicadores observados sin afirmar seguridad absoluta.
- [x] Reconocer en lenguaje natural órdenes para analizar/escanea/revisar aplicaciones y reflejar la acción en el historial.
- [x] Añadir la orden "analizar dominio <host>" conectada al bosque local de 500 árboles; exige modelo y firma verificados, no bloquea automáticamente y expone límites del análisis.
- [x] Exigir una segunda orden afirmativa que comience por "CONFIRMO" para bloqueo de dominios, aislamiento de emergencia y purga criptográfica; una frase negada no concede autorización.
- [x] Acotar el análisis DEX a 16 MiB por archivo y un máximo de ocho entradas DEX por aplicación para reducir riesgo de consumo excesivo ante APK anómalos.
- [ ] Añadir cancelación, progreso granular y límites temporales al escaneo nativo de APK/Dex.
- Política central de permisos y confirmaciones.
- Plan de tareas con progreso, cancelación y recuperación.
- Verificación post-acción y bitácora de resultados.
- Pruebas de prompt injection y entradas maliciosas provenientes de feeds.

### Etapa 3 — módulos Android y protección de red
- [x] VPN local opcional con rutas IPv4/IPv6 y túnel SOCKS5 local.
- [x] Parser TLS ClientHello/SNI y reglas dinámicas de dominio en el módulo C, probados de forma aislada.
- [ ] Integrar el parser SNI en una ruta TUN consciente del reensamblado TCP; el túnel actual incluye el encabezado, pero no invoca el parser en el flujo de paquetes.
- [x] Descarga del feed IP HTTPS con límites de tamaño y actualización asíncrona.
- [x] Pruebas nativas para reglas de dominio, allowlist, entradas inválidas y ClientHello malformado/incompleto.
- [x] Confirmar ejecución verde de la suite nativa ampliada en Codemagic (confirmación del usuario, 2026-10-30).
- [x] Integrar descarte de TCP/853 (DoT) y UDP/853 (DoQ) en el lector de paquetes TUN antes de entregar el paquete a lwIP.
- [x] Integrar descarte de UDP/443 hacia una lista explícita de resolutores DoH conocidos, con evento de auditoría del destino y transporte.
- [x] Añadir pruebas unitarias de la política de transporte: TCP/853, UDP/853 y UDP/443 solo para resolutores marcados.
- [ ] Añadir pruebas de integración del analizador de paquetes IPv4/IPv6 (fragmentos, extensiones, longitudes y paquetes malformados).
- [x] Validar los límites declarados de longitud IPv4/IPv6 antes de inspeccionar puertos DoT/DoQ/DoH; rechazar datagramas truncados, longitudes incoherentes y jumbogramas IPv6 aún no soportados.
- [x] Limitar el análisis de cabeceras de extensión IPv6 a la longitud declarada del paquete y a un máximo de ocho extensiones/296 bytes.
- [ ] Resolver explícitamente el tratamiento de fragmentos no iniciales: actualmente no se correlacionan con el primer fragmento, por lo que no se debe afirmar cobertura completa frente a evasión por fragmentación.
- [ ] Añadir pruebas de regresión específicas del parser TUN (no solo pruebas de política SNI) para IPv4/IPv6, fragmentos, cabeceras de extensión y paquetes truncados.
- [ ] Evaluar DoH sobre TCP/443 y resolutores no incluidos en la lista; no afirmar cobertura general de DoH.
- [ ] Validar DoT/DoQ/DoH en dispositivos físicos y comprobar falsos positivos, fugas y compatibilidad.
- [ ] Definir política explícita para ECH; actualmente solo se identifica su extensión, no se descifra.
- [ ] Completar detección y tratamiento de QUIC/HTTP3 sin atribuir bloqueos que el túnel no ejecuta.
- [ ] Corregir/validar la señalización de conexiones directas por IP.
- [ ] Auditoría de fugas DNS/IPv4/IPv6, reconexión, cambio de red y revocación VPN en dispositivos físicos.
- [ ] Medir consumo de batería, estabilidad prolongada y compatibilidad por versión Android.
- [ ] Revisar feeds: firma/procedencia, caducidad, rollback y falsos positivos.

### Etapa 4 — inteligencia avanzada
- [x] Integrar en el flujo del agente el informe existente de apps con servicios sensibles activos, permisos solicitados de alto riesgo, incidencias de firma y heurísticas de ofuscación.
- [x] Clasificador local de dominios basado en un bosque de decisión de 500 árboles, sujeto a la integridad y validez del modelo.
- [ ] Correlación de eventos, reputación y detección de anomalías.
- [ ] Mejorar el agente de intención: actualmente usa reglas/expresiones y respuestas conversacionales predefinidas; no es un modelo generativo ni un LLM.
- [ ] Integrar un modelo generativo local real, con pesos, runtime Android, límites de memoria/batería y pruebas de seguridad; no sustituirlo por respuestas simuladas.
- [ ] Modelo remoto opcional para razonamiento complejo, con proveedor, credenciales, minimización de datos y consentimiento explícito definidos.
- [ ] Evaluación de precisión, falsos positivos, latencia y consumo energético.

### Etapa 5 — validación y publicación
- CI de Flutter y Android.
- [ ] Ejecutar CodeMagic tras los cambios de interfaz del 2026-11-02 y confirmar el commit actual verde.
- Matriz de dispositivos/versiones Android sin root.
- Pruebas de red, DNS, IPv4/IPv6, reconexión, batería y privacidad.
- Verificación de APK firmado y reproducible en Codemagic.

## Estado inicial del rediseño

- Se añadió un avatar animado generado localmente con Flutter CustomPainter.
- La pantalla principal muestra la identidad de Aura y el estado de trabajo del asistente.
- El flujo de eventos se presenta como conversación y el compositor permite enviar instrucciones por texto o voz.
- El avatar ya comunica estados operativos reales; el diseño completo de pantallas secundarias y la validación visual física siguen pendientes.
- El agente actual es un orquestador determinista de herramientas con un clasificador local de dominios; no debe describirse como LLM.
- Los módulos existentes no se han eliminado.
- CodeMagic completó correctamente la compilación y las pruebas tras la corrección de SemanticsHandle, según confirmación del usuario el 2026-10-30.
- La validación física de avatar, accesibilidad, batería, túnel, fugas DNS y cambios de red continúa pendiente.
- La reconstrucción VPN de la rama `rebuild/vpn-from-zero` continúa separada hasta completar validación técnica; no se incorpora automáticamente a main por no disponer aún de una compilación y pruebas físicas confirmadas.

### Incremento visual y de pruebas — 2026-11-02

- [x] La identidad de la pantalla principal prioriza el nombre AURA y el rol de agente local, en lugar de presentar la app como un panel de seguridad genérico.
- [x] El avatar ocupa el centro de la experiencia con un contenedor visual propio y fondo degradado midnight/cyan/violet.
- [x] Se mantiene el estado del avatar derivado de la actividad real: disponible, escuchando, analizando, protegiendo o alerta.
- [x] Se corrigieron los mocks de canal Android de seguridad en las pruebas widget de consola y transparencia.
- [x] Se eliminó una duplicación accidental en la configuración de los mocks biométricos.
- [ ] Ejecutar formato, análisis estático y pruebas Flutter sobre el HEAD actualizado.
- [ ] Validar jerarquía visual, tamaños, accesibilidad y comportamiento con teclado en dispositivos físicos.
- [ ] Diseñar una identidad/avatar de mayor expresividad que conserve renderizado local, consumo moderado y estados accesibles; no presentar animaciones como actividad de protección si no hay una operación real.
