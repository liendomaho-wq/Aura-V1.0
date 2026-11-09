# Evaluación inicial de LLM en Android (pendiente de ejecución)

Esta herramienta mide rendimiento de `llama-bench` en un Android ARM64 autorizado.
**No integra un LLM en Aura**, no prueba llamadas a herramientas, calidad del
español, seguridad, RAM, energía ni funcionamiento offline de la aplicación. No
se ha seleccionado ni descargado un modelo y ningún resultado se considera PASS
hasta ejecutar las pruebas reales.

## Preparación

1. Elegir un teléfono de prueba autorizado y registrar modelo, versión Android,
   parche, RAM disponible, temperatura y estado de batería. Usar modo avión para
   las pruebas offline, manteniendo únicamente la conexión física ADB autorizada.
2. Compilar `llama-bench` de una revisión concreta y revisada de
   [llama.cpp](https://github.com/ggml-org/llama.cpp), con Android NDK para
   `arm64-v8a`, y registrar revisión, configuración y licencias. El procedimiento
   oficial de compilación Android está en su `docs/android.md`. Usar solo un
   binario y bibliotecas de procedencia verificada.
3. Obtener cada GGUF de una fuente cuya autenticidad, licencia y digest se hayan
   comprobado independientemente. Anotar modelo, versión, cuantización, fuente,
   licencia y SHA-256. La igualdad de hashes **no autentica por sí sola** la
   fuente. No introducir modelos ni binarios grandes en Git.
4. Copiar el binario y cada modelo al directorio de pruebas del dispositivo con
   autorización del propietario y espacio suficiente. Son copias de evaluación,
   no un modelo instalado en el almacenamiento privado de Aura. La herramienta
   no copia, descarga, modifica ni elimina archivos del dispositivo.

## Ejecución

Seleccionar un dispositivo de `adb devices -l` y proporcionar rutas absolutas y
hashes realmente verificados (los valores siguientes son variables que debe
establecer el operador):

```bash
python3 tool/benchmark_llm_android.py \
  --serial "$AURA_DEVICE_SERIAL" \
  --binary "$AURA_LLAMA_BENCH_ON_DEVICE" \
  --binary-sha256 "$AURA_LLAMA_BENCH_SHA256" \
  --model "$AURA_GGUF_ON_DEVICE" \
  --sha256 "$AURA_GGUF_SHA256"
```

El comando rechaza un hash erróneo, rutas no absolutas, ABI distinta de ARM64,
resultados no válidos y fallos ADB. Comprueba de nuevo el hash del modelo tras
la medición. El resultado JSON incluye versión API, ABI, tamaño y hash del
modelo, hash del ejecutable y mediciones producidas por `llama-bench`.
Los parámetros se limitan para evitar ejecuciones accidentalmente desbordadas;
`--timeout` determina el máximo de espera por comando ADB, no garantiza que
Android haya detenido un proceso nativo tras desconectarse.

Para registrar respuestas reales a cuatro casos sintéticos en español, usar un
`llama-completion` ARM64 cuya procedencia y hash también se hayan verificado:

```bash
python3 tool/evaluate_llm_android.py \
  --serial "$AURA_DEVICE_SERIAL" \
  --binary "$AURA_LLAMA_COMPLETION_ON_DEVICE" \
  --binary-sha256 "$AURA_LLAMA_COMPLETION_SHA256" \
  --model "$AURA_GGUF_ON_DEVICE" \
  --sha256 "$AURA_GGUF_SHA256"
```

Esta evaluación ejecuta cuatro procesos individuales con `--offline`, semillas
fijas y prompts públicos sintéticos; guarda las respuestas en la salida JSON para
revisión humana. **No ejecuta herramientas**, no valida autorización ni verifica
memoria conversacional entre turnos. `--offline` por sí solo no demuestra que el
dispositivo estuviera en modo avión. El formato y los parámetros corresponden
al ejecutable de llama.cpp y requieren probarse con la revisión compilada.

Repetir con condiciones comparables para Qwen3-1.7B, DeepSeek-R1-Distill-Qwen-1.5B
y Qwen3-0.6B, sin modificar los controles del modelo actual. Complementar con
una evaluación separada de calidad en español, instrucciones, llamadas a
herramientas, memoria de proceso, energía, temperatura y comportamiento tras
reinicios. Proteger los logs y eliminar únicamente las copias de prueba cuando
el propietario lo autorice. Registrar fallos y ausencia de dispositivo como tales.

## Límite experimental de propuestas

`LlmToolProposal` es un parser aislado para futuras propuestas JSON del modelo.
Solo admite `analyze_domain`, `audit_device` y `scan_apps`, valida sus
argumentos con la política existente y rechaza afirmaciones de confirmación del
modelo. No está conectado a la interfaz, al motor ni al ejecutor, y aceptarlo
no autoriza ni ejecuta nada. Antes de conectarlo se requieren revisión de
privacidad y permisos, mediación del usuario, auditoría, pruebas de integración
y una política separada para acciones con efectos. El JSON no constituye una
frontera completa contra prompt injection; su parser convencional tampoco
certifica unicidad de claves. Ninguna prueba de este componente demuestra
inferencia, seguridad o funcionamiento de un modelo real.
