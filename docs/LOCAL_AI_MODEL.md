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
- `lib/llm/local_llm_planner.dart` — precalentamiento y descarga de runtime;
  el agente nunca descarga.
- `lib/infrastructure/storage/aura_storage.dart` — espacio libre (Dart).
- `android/app/src/main/kotlin/com/ciberdefensa/aura/AuraStoragePlugin.kt` —
  `StatFs` sobre el volumen privado de la app.
- `lib/widgets/aura_llm_setup_sheet.dart` — consentimiento, progreso, pausa,
  borrado y precarga.
- `lib/widgets/aura_capability_ring.dart` y `aura_llm_setup_scope.dart` — UI
  reactiva del estado del modelo.
- `lib/main.dart` — crea el planner, lo enlaza al `AgentController` y expone el
  controlador al árbol de widgets.

## 4. Override de compilación

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

## 5. Pruebas

- `test/aura_llm_model_installer_test.dart` — reanudación con `Range`,
  reinicio cuando el servidor ignora el rango, cancelación con prefijo
  conservado, espacio insuficiente, tamaño incorrecto, resolución sin red,
  verificación con progreso y borrado.
- `test/aura_llm_setup_controller_test.dart` — consentimiento obligatorio,
  persistencia, estados, warm-up, fallos mapeados, pausa, borrado y prefetch.
- `test/aura_llm_setup_ui_test.dart` — hoja, consentimiento, descarga,
  confirmación de borrado, build sin pin, scope y anillo de capacidades.
- `test/aura_storage_test.dart` — canal de espacio libre.
- `test/aura_llm_model_source_test.dart` — pin completo y formateo.
- `test/local_llm_planner_test.dart` — `prefetchModel` devuelve estado real,
  `unloadModel` libera el runtime y el path de órdenes no descarga.

Suites locales: **282 pruebas pasan, 1 omitida**. `flutter analyze` en el
Flutter master local solo reporta avisos informativos de deprecaciones de
`material.dart`/`activeColor`; CI stable sigue siendo la referencia.

## 6. Límites y pendientes

- No hay inferencia observada en un dispositivo físico (TECNO LH7n u otro):
  falta cargar el GGUF, generar el primer token y cancelar una generación real.
- No se ejecutó un build Android completo en este entorno ni un run de CI para
  este cambio. El plugin `AuraStoragePlugin` compila en la misma estructura que
  `AuraLlmPlugin`, pero su comportamiento en dispositivo no fue observado.
- La descarga a través de la app no se probó de extremo a extremo; el hash se
  verificó con una descarga independiente del mismo pin.
- El runtime nativo no es bit-reproducible entre builds; los hashes de `.so`
  identifican artefactos, no garantizan reproducibilidad byte a byte.

Por todo esto, Aura puede operar en modo Básico y preparar el modelo de forma
verificable, pero **no se declara lista para release con IA local**.
