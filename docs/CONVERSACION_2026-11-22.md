# Conversación real de Aura (2026-11-22)

Esta entrega amplía el rango conversacional sin añadir una nube, sin simular
datos y sin relajar las reglas de seguridad. Todo lo nuevo se apoya en lo que la
app ya registró: último dominio analizado, último paquete, veredictos,
explicaciones y eventos de red.

## 1. Memoria de objetivo

`lib/agent/aura_conversation.dart` guarda, en memoria del proceso:

- el último dominio que apareció en una intención validada;
- el último paquete de una intención de aislamiento;
- la última intención y la última respuesta de Aura;
- hasta 12 turnos, con texto acotado a 400 caracteres.

No guarda el historial completo ni llama a un modelo. Se borra con la purga
criptográfica y al reiniciar el proceso.

## 2. Seguimientos que ahora entiende

| El usuario dice | Aura resuelve |
| --- | --- |
| «bloquéalo», «bloquea ese dominio» | `bloquear <último dominio>` y pide confirmación |
| «analízalo», «¿y ese dominio?» | `analizar dominio <último dominio>` |
| «aislala», «revisa esa app» | `aislar app <último paquete>` |
| «¿por qué?», «explícamelo en simple» | explica el último veredicto con sus señales y su umbral |
| «¿qué has hecho?», «dame un resumen» | resume eventos, bloqueos, alertas y análisis reales |
| «repítelo» | repite la última respuesta registrada |

Un texto con un host o una IP **nunca** se sustituye por el objetivo anterior:
se trata como una orden nueva. «¿Por qué bloquearlo?» se interpreta como
pregunta, no como bloqueo, porque los verbos de acción solo se aceptan al
inicio de la frase.

## 3. Confirmación natural, con límites

- «sí», «dale», «adelante», «ok», «hazlo» o «CONFIRMO» autorizan una acción
  **reversible** pendiente, durante la misma ventana de 60 segundos.
- La purga criptográfica y el aislamiento de emergencia **solo** aceptan
  `CONFIRMO` escrito. Un «sí» no ejecuta nada y la solicitud sigue armada.
- «no», «mejor no», «cancela» o «detente» cancelan la solicitud pendiente y lo
  dicen de forma explícita.
- Una frase como «sí, bloquea evil.example» no es una confirmación: introduce
  un objetivo nuevo y se procesa como orden distinta.

La autorización sigue siendo de un solo uso y se invalida con cualquier orden
nueva, igual que antes.

## 4. Explicaciones con datos reales

«¿Por qué?» ya no cae al planificador ni a una plantilla. Aura lee el último
`AuraVerdictExplanation` y responde con:

- el host;
- la banda (`sin señal`, `revisión` o `prioridad alta`);
- el umbral aplicado;
- hasta tres señales observadas con su valor;
- el límite: es una heurística sobre el nombre y no inspecciona la página.

Si no hay análisis, lo dice y no inventa un veredicto.

## 5. Resumen de sesión

«¿Qué has hecho?» cuenta solo lo registrado: eventos de red, bloqueos, alertas
DGA, cantidad de análisis y nivel de seguridad actual. No estima tráfico ni
presenta métricas que la app no tenga.

## 6. Voz

`AuraVoiceEngine` ya existía y sigue usando el TTS del dispositivo. Ahora:

- intenta `es-419` (español latinoamericano), luego `es-US` y por último
  `es-ES`;
- limpia prefijos de consola (`[OK]`, `[WARN]`, `[CRIT]`), Markdown y rutas de
  URL antes de hablar, para no leer símbolos;
- acota el texto a 600 caracteres y corta en una oración completa cuando puede.

El reconocimiento de voz sigue siendo el canal nativo existente. No se añadió
palabra de activación ni escucha permanente.

## 7. Contexto para el modelo local

El planificador recibe un contexto estructurado y acotado:

```
ultimo_dominio=tracker.example | ultima_intencion=analyze_domain | nivel_seguridad=warning
```

`AuraLlmPrompt` elimina los delimitadores internos, separa el contexto de la
orden y prohíbe que cualquiera de los dos cierre su bloque. La respuesta previa
del modelo **no** se realimenta como contexto, para no amplificar una posible
inyección de prompt.

## 8. Verificación

- `test/aura_conversation_test.dart`: memoria, seguimientos, confirmación,
  negación, límites y limpieza de texto para voz.
- `test/aura_conversation_controller_test.dart`: integración real con
  `AgentController`, incluida la negativa a autorizar una purga con «sí».
- `test/aura_llm_prompt_test.dart`: delimitadores, truncado y orden completa.
- CI: `dart format`, `flutter analyze` y `flutter test`.

## 9. Límites declarados

- La memoria conversacional vive en el proceso: no sobrevive a un cierre de la
  app.
- La calidad de las respuestas del modelo local depende del GGUF instalado y
  del contexto que el dispositivo pueda cargar.
- El TTS usa el motor del sistema; la voz exacta y la disponibilidad de
  `es-419` dependen del dispositivo.
- No hay conversación en la nube, ni historial remoto, ni entrenamiento con las
  conversaciones del usuario.
