# Aura — integración de DeepSeek local en Android

**Estado:** decisión de producto aprobada; diseño de implementación. No es una integración terminada ni evidencia de inferencia ejecutada.

## 1. Modelo seleccionado

- Familia: **DeepSeek-R1-Distill-Qwen-1.5B**.
- Formato de ejecución: **GGUF**.
- Cuantización inicial: **Q4_K_M**.
- Archivo candidato: `DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf`.
- Artefacto candidato: [bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF](https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF), revisión publicada `c92dd823ac7cbd845647419c87b8549de8c0f156`.
- Tamaño orientativo publicado: aproximadamente 1.12 GB. El tamaño exacto debe leerse del artefacto fijado antes de descargarlo.
- Modelo base y licencia: [DeepSeek oficial](https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B), MIT según la ficha oficial. Conservar también los avisos/licencias del cuantizador y del runtime.

La cuantización Q4_K_M es el punto de partida por equilibrio entre tamaño y calidad. No es una certificación de calidad ni una garantía de velocidad en el Redmi. No cambiar a Q2/Q3 automáticamente para ocultar un fallo de memoria: medir primero y documentar cualquier alternativa.

## 2. Runtime Android

Usar **llama.cpp** como runtime local de inferencia, compilado para Android con Android NDK y ABI `arm64-v8a`. La documentación upstream describe la compilación Android por NDK y una app de ejemplo Android que carga GGUF desde el almacenamiento privado y transmite tokens.

- Fuente upstream: https://github.com/ggml-org/llama.cpp
- Guía Android: https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md
- No descargar ejecutables nativos de terceros en tiempo de ejecución.
- Fijar una revisión exacta de llama.cpp antes de integrar; registrar licencia, commit, opciones CMake y SBOM.
- Compilar bibliotecas nativas en CI con NDK fijado y comprobar ELF/ABI/JNI. No añadir flags de CPU que excluyan dispositivos ARM64 compatibles.
- Integrar el motor mediante JNI/bridge nativo y una API Kotlin acotada; Flutter/Dart habla con Kotlin por MethodChannel. No ejecutar comandos shell ni iniciar un servidor localhost abierto para la app.

## 3. Almacenamiento y ciclo de vida del modelo

El GGUF no se incluye en Git, APK, assets ni repositorio de código. La app lo descarga una sola vez a almacenamiento privado de Aura, con pantalla de progreso, tamaño requerido y consentimiento del usuario.

Antes de habilitarlo:
1. Fijar revisión inmutable, nombre, tamaño esperado, licencia y SHA-256 real del archivo.
2. Obtener el artefacto por HTTPS desde el origen fijado; no confiar en un hash servido por el mismo canal sin una firma independiente.
3. Verificar digest y manifiesto firmado con una clave pública de confianza incorporada en la app.
4. Descargar a archivo temporal, limitar bytes, comprobar espacio libre, cancelar limpiamente y hacer rename atómico solo después de verificar.
5. Rechazar truncamiento, exceso de tamaño, redirect a host no permitido, digest incorrecto y downgrade no autorizado.
6. No registrar prompts, respuestas, rutas privadas ni secretos. No subir contenido del usuario a servicios externos.
7. Borrar o sustituir modelos solo mediante acción explícita del usuario; no borrar automáticamente el modelo activo durante una actualización.

La revisión del repositorio GGUF no sustituye la verificación criptográfica del archivo. El SHA-256 debe calcularse sobre el artefacto exacto seleccionado y quedar revisado en el manifiesto de Aura antes de publicar un endpoint de descarga.

## 4. Límites iniciales para el Redmi objetivo

Dispositivo de referencia declarado: Redmi Note 15 Pro Plus 5G, 8 GB RAM, Android 16.

Perfil inicial conservador, sujeto a medición real:
- Contexto inicial: 2,048 tokens; probar 4,096 solo si memoria y latencia permanecen dentro de los límites.
- CPU primero, `arm64-v8a`; aceleración opcional solo tras pruebas de compatibilidad y consumo.
- Un único contexto/sesión activa; serializar inferencias y liberar el contexto al cerrar la sesión o cuando Android indique presión de memoria.
- Limitar tokens de salida, longitud de entrada, historial, hilos y duración. Recortar historial con resumen explícito y sin perder confirmaciones de seguridad.
- Medir memoria pico PSS/RSS, tiempo de carga, tokens/s, temperatura, batería, ANR, crash y recuperación después de cerrar/reabrir la app.
- No prometer ejecución continua en segundo plano ni funcionamiento en todos los Android por el mero hecho de cargar el modelo una vez.

No fijar umbrales PASS inventados. Antes del gate de rendimiento se acordarán límites reproducibles y se medirán en el dispositivo físico.

## 5. Arquitectura del agente: el LLM no ejecuta directamente

```text
Flutter UI / voz
    |
    v
AuraConversationController
    |
    v
DeepSeek local (solo genera texto y propuestas estructuradas)
    |
    v
Parser JSON estricto + schema allowlist
    |
    v
AuraToolExecutionPolicy + AgentExecutionGuard
    |
    +--> lectura: auditoría, análisis de dominio, inventario permitido
    |
    +--> acciones con efectos: confirmación explícita en UI, token de un uso,
         caducidad, auditoría previa y postcondición verificada
    |
    v
Resultado real de Aura -> respuesta al usuario
```

Reglas obligatorias:
- La salida del modelo es dato no confiable. Nunca es autorización, consentimiento, identidad del usuario ni evidencia de que una acción ocurrió.
- El modelo no recibe secretos, credenciales SOCKS, claves, tokens, contenido de SecureVault ni datos privados que no sean necesarios.
- No se permiten shell, JavaScript arbitrario, SQL arbitrario, reflexión, escritura de archivos fuera de los gestores de Aura ni herramientas inventadas por el modelo.
- El parser exige JSON acotado, objeto exacto, claves únicas, esquema estricto, argumentos tipados, límites de bytes/profundidad y nombre de herramienta allowlisted. Rechaza texto adicional y duplicados.
- La primera integración ejecutable permite solo propuestas de lectura: `analyze_domain`, `audit_device`, `scan_apps`. La política existente valida argumentos.
- Las acciones que cambian estado no se activan en la primera versión LLM. Se incorporarán por herramienta y con pruebas de confirmación independientes; el modelo nunca puede establecer `confirmed_by_user`.
- La UI debe mostrar qué hará Aura, pedir confirmación humana para efectos, y distinguir solicitud, aceptación del sistema, evento y postcondición.
- Prompt injection en mensajes, webs, nombres de paquetes o resultados de herramientas no puede cambiar políticas ni conceder permisos. Tratar todo contenido externo como datos.
- No afirmar análisis, escaneo, bloqueo, aislamiento o VPN activos hasta recibir resultados reales del motor y verificar su postcondición.

## 6. Experiencia conversacional

DeepSeek sustituirá progresivamente las respuestas conversacionales fijas de `AgentController`, pero no reemplazará:
- el clasificador de amenazas actual ni sus gates de integridad;
- `AuraTools`, `AuraToolExecutionPolicy`, `AgentExecutionGuard`;
- los canales nativos, SecureVault, auditoría o controles de consentimiento.

El sistema debe conversar en español natural, reconocer incertidumbre, explicar límites y responder con un resumen conciso. No mostrar cadenas internas de razonamiento; mostrar conclusiones, evidencia disponible, pasos ejecutados y limitaciones. Si el runtime o el modelo no está listo, informar que está descargando/no disponible y ofrecer las funciones deterministas existentes sin fingir conversación generativa.

## 7. Fases y gates

1. **Runtime reproducible:** fijar commit llama.cpp, compilar arm64-v8a en CI, verificar bibliotecas/ABI y licencias.
2. **Artefacto fijado:** descargar Q4_K_M desde revisión inmutable, registrar tamaño y SHA-256 independiente; verificar manifiesto firmado.
3. **Inferencia nativa aislada:** cargar GGUF desde almacenamiento privado, generar tokens, cancelar de forma segura, liberar memoria y manejar errores.
4. **Descarga segura:** descarga reanudable/limitada, hash y firma, rename atómico, espacio libre, cancelación y recuperación.
5. **Conversación Flutter:** integrar controlador conversacional, streaming, historial local limitado, voz y UX de estado; sin herramientas al principio.
6. **Propuestas de herramientas de solo lectura:** endurecer parser JSON (incluidas claves duplicadas), pruebas de prompt injection, validación y auditoría.
7. **Acciones con efectos:** añadir una por una solo tras revisión, consentimiento explícito y verificación de postcondición.
8. **Pruebas físicas:** Redmi Android 16; modo avión real, reinicio, interrupción de descarga, almacenamiento insuficiente, presión de memoria, llamadas entrantes, rotación, segundo plano, temperatura, batería y ANR.
9. **Release gate:** CI verde, SBOM/licencias, integridad de artefacto, tests Flutter/Kotlin/JNI, firma release válida y aprobación del propietario.

Estados de evidencia: PASS, FAIL, NOT RUN, NOT VERIFIED, BLOCKED. No convertir un test ausente o un equipo no disponible en PASS.

## 8. Fuentes

- DeepSeek model card y licencia: https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B
- Artefacto GGUF Q4_K_M candidato: https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF
- llama.cpp Android/NDK: https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md

## Estado actual

**Seleccionado:** DeepSeek-R1-Distill-Qwen-1.5B GGUF Q4_K_M.

**Todavía no implementado:** runtime llama.cpp en Aura, descarga del GGUF, hash firmado del artefacto, inferencia en el Redmi, integración conversacional y ejecución de herramientas por el LLM. Este documento no afirma lo contrario.
