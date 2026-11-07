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
- [x] Validar el contrato del informe `scan_apps`: contadores no negativos, listas tipadas, correspondencia entre contadores y evidencias, y conteo de accesos especiales realmente `ACTIVE`.
- Política central de permisos y confirmaciones.
- Plan de tareas con progreso, cancelación y recuperación.
- Verificación post-acción y bitácora de resultados.
- Pruebas de prompt injection y entradas maliciosas provenientes de feeds.

### Etapa 3 — módulos Android y protección de red
- [x] VPN local opcional con rutas IPv4/IPv6 y túnel SOCKS5 local.
- [x] Parser TLS ClientHello/SNI y reglas dinámicas de dominio en el módulo C, probados de forma aislada.
- [x] Integrar el parser SNI en las sesiones TCP del túnel, acumulando el ClientHello antes de evaluar reglas. Esta integración en código y sus pruebas nativas no sustituyen la validación de tráfico real en el dispositivo.
- [x] Descarga del feed IP HTTPS con límites de tamaño y actualización asíncrona.
- [x] Pruebas nativas para reglas de dominio, allowlist, entradas inválidas y ClientHello malformado/incompleto.
- [x] Confirmar ejecución verde de la suite nativa ampliada en Codemagic (confirmación del usuario, 2026-10-30).
- [x] Integrar descarte de TCP/853 (DoT) y UDP/853 (DoQ) en el lector de paquetes TUN antes de entregar el paquete a lwIP.
- [x] Integrar descarte de UDP/443 hacia una lista explícita de resolutores DoH conocidos, con evento de auditoría del destino y transporte.
- [x] Añadir pruebas unitarias de la política de transporte: TCP/853, UDP/853 y UDP/443 solo para resolutores marcados.
- [ ] Validar en Android y con tráfico real la integración del analizador de paquetes IPv4/IPv6 (fragmentos, extensiones, longitudes y paquetes malformados); las pruebas host del parser no cubren el túnel completo.
- [x] Validar los límites declarados de longitud IPv4/IPv6 antes de inspeccionar puertos DoT/DoQ/DoH; no inspeccionar datos fuera de la longitud declarada ni jumbogramas IPv6 aún no soportados.
- [x] Limitar el análisis de cabeceras de extensión IPv6 a la longitud declarada del paquete y a un máximo de ocho extensiones/296 bytes; las cadenas que exceden el límite se descartan sin registrarlas como DNS.
- [ ] Validar el compromiso de compatibilidad de la política provisional: lwIP tiene desactivado el reensamblaje IPv4/IPv6, por lo que descarta datagramas fragmentados en lugar de correlacionarlos. Los fragmentos atómicos IPv6 se inspeccionan como paquetes completos. No afirmar cobertura completa de tráfico cifrado.
- [x] Añadir pruebas host del parser TUN real con pbufs encadenados y de la entrada IP real de lwIP con adaptadores locales. Incluyen un control que demuestra reensamblaje cuando se habilita; no sustituyen las pruebas del túnel Android.
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
- [x] Dar al avatar una expresión facial abstracta y luminosa mediante CustomPainter local, sin imágenes remotas ni dependencias adicionales; conservar estados accesibles y no presentar la animación como actividad de protección real.

- [x] Distinguir visual y semánticamente una advertencia ámbar de una alerta crítica coral en el avatar; la postura warning ya no se representa como amenaza crítica.


### Incremento de validación del escáner — 2026-11-04

- El límite Dart de `scan_apps` ya no convierte campos nativos ausentes o malformados en contadores cero.
- El informe se marca como incompleto si faltan colecciones, si sus elementos no son mapas, si los contadores no coinciden con la evidencia, si la marca temporal no es válida o si el total de accesos activos no coincide con las entradas cuyo estado nativo es `ACTIVE`.
- Se añadieron pruebas de regresión para informes incompletos, contadores incoherentes y accesos especiales no confirmados.
- Commits de implementación en `main`: `8363955`, `35809c6`, `a584c28`, `9a4a57f` y `dfaf4c9`.
- **Validación pendiente:** ejecutar `flutter analyze`, `flutter test` y el build Android en CodeMagic sobre el HEAD actual. Esta corrección no convierte el escáner heurístico en detección garantizada de malware.

### Fase 1 — endurecimiento del agente inteligente — 2026-11-05

- [x] Allowlist central de herramientas y rechazo de nombres no registrados.
- [x] Contratos estrictos de argumentos por herramienta; límites de tamaño/profundidad y validación DNS/paquetes.
- [x] Confirmación explícita centralizada para operaciones con efectos laterales.
- [x] Confirmación de dos pasos, un solo uso y caducidad de 60 segundos; la autorización se vincula a la orden exacta y se invalida ante cualquier instrucción distinta.
- [x] Límite de longitud de instrucciones y rechazo de ejecución concurrente.
- [x] Cancelación segura antes de cruzar la frontera de ejecución; no se afirma abortar llamadas nativas ya iniciadas.
- [x] Plazos máximos por herramienta; timeout reporta resultado desconocido y bloquea reintento automático.
- [x] Postcondición booleana obligatoria para no promover resultados incompletos a éxito.
- [x] Identificador local de operación y reducción de argumentos crudos en eventos de inicio/finalización.
- [x] Bitácora de operaciones cifrada en SecureVault: el inicio se guarda antes del despacho (fallo = fail-closed), el cierre no conserva valores de argumentos y la purga criptográfica elimina la bitácora.
- [x] Pruebas unitarias añadidas para política, confirmaciones, límites, cancelación y concurrencia.
- [ ] Ejecutar `dart format`, `flutter analyze` y `flutter test` sobre el HEAD resultante en CodeMagic.
- [ ] Revisar resultados reales de CodeMagic y corregir cualquier incompatibilidad antes de declarar Fase 1 cerrada.
- [ ] Verificar en un dispositivo Android que cancelación, confirmación y resultado desconocido por timeout se comportan según lo documentado.

**Nota de seguridad:** un timeout de Future no mata un trabajo nativo o HTTP que ya empezó. Aura no lo presenta como cancelado ni lo reintenta automáticamente; el resultado se clasifica como desconocido hasta una comprobación independiente.



### Avance de la Fase 2 — agente ejecutor — 2026-11-05

- Se añadió rechazo fail-closed de mensajes con más de una intención ejecutable, y de órdenes incrustadas después de separadores típicos de texto pegado. El parser no interpreta feeds o informes pegados como autorización para ejecutar una segunda orden.
- Se añadieron pruebas de regresión para órdenes concatenadas, texto de indicadores con instrucciones incrustadas y confirmaciones fuera del inicio de la orden.
- **Pendiente antes de cerrar Fase 2:** cancelación cooperativa/progreso del escaneo nativo APK/DEX, planificador de tareas con checkpoints y recuperación, y ejecución de todas las pruebas en CodeMagic. No se afirma que un timeout Dart detenga el escáner Kotlin.
