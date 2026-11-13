# Modelo de IA local de Aura

Estado: **integrado en código y verificado hasta donde permite este entorno**.
La inferencia real en hardware sigue sin observarse. Este documento describe el
pin, el flujo fail-closed y lo que falta antes de afirmar que la IA local está
lista para producción.

## 1. Modelo fijado

| Campo | Valor |
| --- | --- |
| Repositorio | `unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF` |
| Revisión | `3cb4d15544a2a5e07439592b9a0965b6445fbd34` |
| Archivo | `DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf` |
| Tamaño exacto | `1.117.321.312` bytes |
| SHA-256 | `f3bdf9cf31dee4b57ae4e455a1cb0d01b5c2c1b50d72d3112141c195506c2840` |
| Licencia | Apache-2.0 |
| Publicador | `unsloth` |

URL inmutable:

```text
https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/3cb4d15544a2a5e07439592b9a0965b6445fbd34/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf
```

El modelo **no se empaqueta en la APK**: se descarga desde Hugging Face después
de un consentimiento explícito. La app no envía análisis, telemetría ni datos
del dispositivo; solo solicita el archivo del modelo.

### Verificación independiente realizada

En esta sesión se descargó el archivo completo fuera de la app y se comprobó su
integridad:

```bash
curl -L -C - -o /tmp/aura-model.gguf '<URL fijada>'
sha256sum /tmp/aura-model.gguf
stat -c '%s' /tmp/aura-model.gguf
```

Resultado:

```text
f3bdf9cf31dee4b57ae4e455a1cb0d01b5c2c1b50d72d3112141c195506c2840  /tmp/aura-model.gguf
1117321312
```

El tamaño y el SHA-256 coinciden con el pin de
`lib/llm/aura_llm_model_source.dart`. Esta verificación no sustituye una prueba
de inferencia ni de descarga a través de la app.

## 2. Flujo de preparación

1. `AuraLlmSetupController.initialize()` lee consentimiento
   (`aura.llm.consent.v1`), preferencia de precarga (`aura.llm.prefetch.v1`) y
   espacio libre vía `AuraStorage` (canal Android `StatFs`).
2. Si hay un modelo instalado, `AuraLlmModelManager.verifyInstalled()` calcula
   el SHA-256 con progreso. Si no coincide, el archivo se borra.
3. La descarga solo empieza desde la hoja de preparación, con consentimiento
   marcado. `installModel()`:
   - valida URL HTTPS, SHA-256 de 64 hex y tamaño máximo;
   - comprueba espacio libre antes de abrir la conexión;
   - reanuda un `.partial` con `Range`; si el servidor ignora el rango,
     reinicia desde cero;
   - escribe en `aura-local.gguf.partial` dentro del directorio de soporte de
     la app;
   - verifica tamaño exacto y SHA-256 por bloques;
   - solo entonces renombra a `aura-local.gguf` (rename atómico);
   - permite pausar y conserva el prefijo para reanudar.
4. Si la verificación es correcta, el controlador pide al planner cargar el
   modelo (`prefetchModel`). Un fallo del runtime deja el estado en
   "Modelo verificado" y no simula inferencia.
5. El path de órdenes del agente usa `resolveInstalledModel()`, que **nunca
   descarga**: solo devuelve un archivo ya verificado.

## 3. Dónde vive el código

- `lib/llm/aura_llm_model_source.dart` — pin inmutable y formato de tamaño.
- `lib/llm/aura_llm_model_manager.dart` — descarga, reanudación, cancelación,
  espacio libre, SHA-256, caché de verificación y borrado.
- `lib/llm/aura_llm_setup_controller.dart` — consentimiento, estados y
  preferencias.
- `lib/llm/local_llm_planner.dart` — precalentamiento, carga, contexto
  adaptativo y generación; el agente nunca descarga.
- `lib/llm/aura_llm_context_policy.dart` — selección pura del contexto y
  fallback por memoria, sin efectos secundarios.
- `lib/agent/llm_tool_proposal.dart` — esquema estricto de propuestas de
  herramienta y de respuestas conversacionales.
- `lib/infrastructure/storage/aura_storage.dart` — espacio libre y memoria
  (Dart).
- `android/app/src/main/kotlin/com/ciberdefensa/aura/AuraStoragePlugin.kt` —
  `StatFs` y `ActivityManager.MemoryInfo`.
- `lib/widgets/aura_llm_setup_sheet.dart` — consentimiento, progreso, pausa,
  borrado y precarga.
- `lib/widgets/aura_capability_ring.dart` y `aura_llm_setup_scope.dart` — UI
  reactiva del estado del modelo.
- `lib/main.dart` — crea el planner, lo enlaza al `AgentController` y expone el
  controlador al árbol de widgets.

## 4. Contexto adaptativo y respuesta conversacional

La carga del GGUF no reserva 64K por defecto. `LocalLlmPlanner` consulta
`ActivityManager.MemoryInfo` y `AuraLlmContextPolicy` elige el mayor nivel que
cabe en el presupuesto conservador: **8K como base**, niveles de 64K, 32K, 16K,
8K, 4K y 2K, y un máximo configurable de 64K. La política descuenta el peso del
modelo, 384 MiB de overhead y deja un margen de seguridad sobre la memoria
disponible. `lowMemory` reduce la elección a 4K.

Si el runtime no puede cargar el contexto elegido, el planner reintenta con
niveles menores (hasta tres intentos por mitades). `effectiveContextTokens`
solo refleja el contexto que el runtime aceptó realmente; no se anuncia 64K ni
ningún nivel no confirmado. En un perfil de 8 GB con 3 GB disponibles, la
prueba local selecciona 16K, no 64K.

Cuando el NLU determinista no reconoce una orden, el planner puede devolver:

- `{"tool":"NOMBRE","arguments":{...}}` para una de las tres herramientas de
  solo lectura ya permitidas (`analyze_domain`, `audit_device`, `scan_apps`); o
- `{"answer":"texto breve"}` para una respuesta conversacional de un solo turno.

`LlmConversationReply` limita la respuesta a 4096 caracteres y rechaza claves
extra, tipos incorrectos, texto vacío, caracteres de control y salida mayor de
8192 bytes. La respuesta se muestra como salida local no verificada y **nunca
ejecuta herramientas ni sustituye un veredicto de seguridad**. No hay memoria
conversacional persistente ni historial largo: cada orden se evalúa con el
prompt acotado actual.

## 5. Override de compilación

El build usa el pin integrado por defecto. Para un build propio se pueden
sobrescribir URL y SHA-256; ambos son obligatorios y el SHA-256 debe tener 64
caracteres hexadecimales:

```bash
flutter build apk --debug \
  --dart-define=AURA_LLM_MODEL_URL='<https url>' \
  --dart-define=AURA_LLM_MODEL_SHA256='<64 hex>' \
  --dart-define=AURA_LLM_MODEL_BYTES='<bytes exactos>'
```

Sin URL y SHA-256 válidos, la app queda en **Aura Básica** y no descarga ni
carga ningún GGUF.

## 6. Pruebas

- `test/aura_llm_model_installer_test.dart` — reanudación con `Range`,
  reinicio cuando el servidor ignora el rango, cancelación con prefijo
  conservado, espacio insuficiente, tamaño incorrecto, resolución sin red,
  verificación con progreso y borrado.
- `test/aura_llm_setup_controller_test.dart` — consentimiento obligatorio,
  persistencia, estados, warm-up, fallos mapeados, pausa, borrado y prefetch.
- `test/aura_llm_setup_ui_test.dart` — hoja, consentimiento, descarga,
  confirmación de borrado, build sin pin, scope y anillo de capacidades.
- `test/aura_storage_test.dart` — canal de espacio libre y memoria, incluido
  fallo cerrado ante datos inválidos.
- `test/aura_llm_model_source_test.dart` — pin completo y formateo.
- `test/aura_llm_context_policy_test.dart` — niveles, presupuesto de memoria,
  `lowMemory` y fallback.
- `test/local_llm_planner_test.dart` — `prefetchModel` devuelve estado real,
  `unloadModel` libera el runtime, el path de órdenes no descarga, la respuesta
  conversacional se valida y el contexto baja de 16K a 8K si la carga falla.
- `test/agent_controller_test.dart` — una pregunta desconocida muestra la
  respuesta local sin ejecutar tools.

Suites locales con Flutter `3.47.9`: **294 pruebas pasan, 1 omitida**;
`flutter analyze --no-pub` no reporta errores ni warnings; `dart format` deja
0 archivos cambiados. El commit `a6ff02e` pasó CI: Flutter Quality, Android
Debug Build (incluida la migración real de Keystore en emulador Android 16),
Release signing integrity y dataset/training. El APK debug de ese commit fue
descargado y validado en estructura, JNI y assets; ver `AURA_FINAL_AUDIT.md`.

## 7. Límites y pendientes

- No hay inferencia observada en un dispositivo físico (Redmi Note 15 Pro+
  5G u otro): falta cargar el GGUF, generar el primer token, cancelar una
  generación y medir memoria real para 8K, 16K, 32K y 64K.
- Los cambios Kotlin de `memoryInfo` compilaron en CI, pero su comportamiento
  en el Redmi y la selección real de contexto no se observaron en hardware.
- La respuesta conversacional es de un solo turno y no tiene memoria
  persistente. No se probó calidad, alucinación ni latencia real del modelo.
- No se probó la descarga desde la app de extremo a extremo; el hash se
  verificó con una descarga independiente del mismo pin.
- El runtime nativo no es bit-reproducible entre builds; los hashes de `.so`
  identifican artefactos, no garantizan reproducibilidad byte a byte.

Por todo esto, Aura puede operar en modo Básico y preparar el modelo de forma
verificable, pero **no se declara lista para release con IA local**.
