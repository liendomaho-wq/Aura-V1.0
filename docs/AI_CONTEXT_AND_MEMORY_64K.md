# Aura — política de contexto y memoria local (64K)

**Estado:** política de selección implementada y probada en Dart; 64K no está validado ni anunciado como operativo en hardware. El runtime nativo acepta hasta 65.536 tokens, pero la APK aún no confirma ese límite en el Redmi.

## Decisión

- Objetivo máximo de contexto activo: **65.536 tokens (64K)**.
- No configurar 100K ni 500K.
- No declarar 64K operativo hasta que el runtime GGUF confirme la longitud efectiva de contexto, la asignación de KV cache y la inferencia real en Android ARM64.
- El modelo seleccionado sigue siendo DeepSeek-R1-Distill-Qwen-1.5B GGUF Q4_K_M. Su ventana efectiva debe validarse contra el metadata del GGUF y el runtime compilado; no inferirla solamente del nombre del modelo o de un parámetro de configuración.

## Dos presupuestos distintos

### 1. Contexto activo del LLM

El runtime podrá aceptar como máximo 65.536 tokens, pero la configuración efectiva deberá ser adaptativa:

| Nivel | Contexto solicitado | Condición |
|---|---:|---|
| Base | 8.192 | Arranque conservador y comprobación de backend |
| Intermedio | 16.384 | Prueba sostenida sin presión de memoria |
| Alto | 32.768 | Prueba sostenida y medición de KV cache |
| Objetivo | 65.536 | Solo si el backend confirma soporte y el dispositivo supera pruebas de memoria, latencia y temperatura |

No se debe reservar la KV cache máxima al iniciar la app. El runtime debe dimensionarla según el contexto configurado, reutilizarla cuando sea seguro y liberar recursos al cerrar la sesión. Si el backend no soporta el contexto solicitado, Aura debe rechazar o reducir explícitamente el valor y mostrar el límite efectivo; nunca fingir que aceptó 64K.

**Estimación de memoria:** la caché KV aproximada se calcula como `2 × capas × cabezas_KV × dimensión_cabeza × bytes_por_elemento × tokens`. Con 28 capas, 2 cabezas KV, dimensión 128 y FP16, serían aproximadamente 28 KiB por token: cerca de 1,75 GiB para 64K, solo para KV cache. La memoria real también incluye pesos, buffers, runtime y aplicación. `AuraLlmContextPolicy` usa 28 KiB/token solo como preflight conservador derivado de esos metadatos; debe recalibrarse si el GGUF o el runtime cambian, y no sustituye la medición en el Redmi de 8 GB.

### 2. Memoria persistente

La memoria persistente no equivale a ventana de contexto. Puede superar 64K y crecer por sesiones, pero cada consulta recupera solo los fragmentos pertinentes.

Arquitectura prevista:
1. Conversaciones/eventos se guardan por sesión, con timestamps y límites de tamaño.
2. Se crean resúmenes jerárquicos (sesión → proyecto/tema → resumen global) conservando referencias a los registros originales.
3. La recuperación combina búsqueda lexical y embeddings locales cuando el encoder esté disponible; no inventar embeddings ni presentar búsqueda lexical como semántica.
4. Se aplican límites de fragmentos, deduplicación, recencia y relevancia antes de construir el prompt.
5. El prompt final incluye presupuesto explícito para instrucciones del sistema, contexto recuperado, herramientas y respuesta; nunca excede 65.536 tokens.
6. Los datos sensibles se minimizan y cifran en reposo. Los registros de seguridad conservan procedencia, fecha y estado de verificación.
7. La memoria recuperada es dato no confiable: jamás concede permisos ni confirma operaciones.

## Integración del agente

El LLM puede proponer una llamada estructurada o una respuesta breve (`{"answer":"..."}`) cuando la orden no pide una herramienta. El controlador determinista valida:
- nombre de herramienta contra allowlist;
- esquema y tipos de argumentos;
- límites de longitud, dominios, puertos y URLs;
- autorización vigente y confirmación explícita para acciones sensibles;
- estado previo, postcondición y resultado real del canal nativo.

El LLM no ejecuta directamente MethodChannels, no genera código para ejecutarlo y no puede elevar permisos. Una salida JSON malformada, ambigua o no permitida se rechaza; una respuesta conversacional se muestra como salida local no verificada. Las detecciones del clasificador especializado permanecen separadas del LLM; el modelo conversacional no reemplaza las comprobaciones de seguridad. La conversación actual es de un solo turno y no implementa todavía memoria persistente.

## Condiciones para declarar 64K disponible

1. Integrar un runtime llama.cpp/Android ARM64 reproducible, versionado y con licencia revisada.
2. Verificar hash del GGUF antes de cargarlo; descarga reanudable a almacenamiento privado, sin incluir el modelo de 1+ GB dentro del APK.
3. Leer metadatos GGUF y verificar que la arquitectura, RoPE/context extension y contexto solicitado sean compatibles.
4. Ejecutar pruebas reales de 8K, 16K, 32K y 64K en el Redmi Note 15 Pro+ 5G (8 GB RAM, Android 16).
5. Medir pico de RSS/PSS, memoria nativa, tiempo al primer token, tokens/s, temperatura, cierres por OOM y consumo de batería.
6. Ejecutar pruebas de recuperación de conversación larga: recordar un dato al inicio, ignorar instrucciones maliciosas citadas, resolver contradicciones y citar el origen recuperado.
7. Confirmar que la app sigue respondiendo al sistema Android y que el proceso no se reinicia ni degrada de forma sostenida.
8. Mantener un fallback explícito a 8K/16K/32K si 64K no supera los límites del dispositivo. La función de memoria persistente seguirá disponible aunque el contexto activo sea menor.

## Criterio de aceptación

64K solo se anunciará como contexto efectivo cuando el runtime informe el valor real, un prompt de prueba de longitud controlada alcance ese contexto sin truncamiento silencioso, y la batería de pruebas en dispositivo físico pase. Hasta entonces, 64K es el **objetivo máximo configurado para el trabajo de integración**, no una capacidad ya entregada.

## Estado implementado y límites actuales

- `AuraLlmContextPolicy` implementa la selección por memoria y el fallback; `LocalLlmPlanner` consulta `ActivityManager.MemoryInfo`, reintenta contextos menores y solo expone el contexto aceptado por el runtime.
- `AuraLlmModelSource.runtimeContextTokens` usa **8.192** como base conservadora; el máximo configurable es **65.536**, no el valor inicial.
- `AgentController.historyCapacity = 400` limita eventos en memoria; no define tokens del LLM.
- `AuraIntentParser.historyCapacity = 5` limita el buffer del parser; no define memoria conversacional.
- `lib/ai_brain.dart` implementa el clasificador de dominios y herramientas actuales; el runtime DeepSeek vive en el puente JNI/NDK y se carga solo con un GGUF verificado.
- La memoria persistente descrita en la sección 2 **no está implementada**; la respuesta del modelo es de un solo turno.
- La estimación de 28 KiB/token es un cálculo de ingeniería a partir de los metadatos GGUF (`28` capas, `2` cabezas KV, dimensión `128`, FP16). No se declara 64K disponible sin las pruebas físicas de la sección anterior.
