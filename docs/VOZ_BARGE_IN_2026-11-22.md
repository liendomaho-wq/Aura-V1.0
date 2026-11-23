# Voz conversacional: barge-in y corpus de evaluación (2026-11-22)

## Qué cambió

### 1. Barge-in real (interrumpir a Aura mientras habla)

Antes, el motor de voz encolaba la respuesta y nada la detenía: el botón del
micrófono solo funcionaba cuando Aura ya había terminado. Ahora:

- `AuraVoiceEngine` registra los callbacks `start`, `completion`, `cancel` y
  `error` de `flutter_tts`, expone `isSpeaking`, un `Stream<AuraSpeechState>` y
  un `Completer` que se completa con el fin real de la locución.
- `speak()` detiene cualquier locución anterior antes de encolar la nueva.
- `waitForSpeech()` espera al callback con un límite de 30 s. Si el motor no
  emite eventos, el turno continúa en vez de quedarse bloqueado.
- `AuraCoreScreen._captureVoice()` llama a `stopSpeaking()` antes de abrir el
  micrófono. Tocar el micrófono mientras Aura habla la interrumpe y abre el
  dictado; cualquier orden escrita también detiene la voz al entrar en
  `_dispatch()`.
- El controlador expone `stopSpeaking()`, `waitForSpeech()`, `isSpeaking` y
  `hasPendingConfirmation`.

### 2. Rearmado acotado para confirmar por voz

Después de dictar una orden que deja una confirmación pendiente, la interfaz
espera el final de la respuesta hablada y vuelve a abrir el micrófono **una
sola vez**. Ese segundo turno solo sirve para responder «sí», «dale» o
«CONFIRMO»; no queda un micrófono abierto en bucle. Si la ventana de 60 s
expira, `hasPendingConfirmation` devuelve `false` y no se rearma.

Esto no cambia la política de seguridad: las acciones destructivas siguen
exigiendo la palabra `CONFIRMO`; el rearmado solo evita tener que tocar el
micrófono dos veces.

### 3. Idioma del reconocedor

`launchVoiceRecognition()` ya no fija `es-ES`. Usa el español configurado en el
dispositivo (`es-VE`, `es-MX`, `es-ES`…) y cae en `es-419` si el sistema no está
en español. Así el dictado coincide con la voz es-419 que prefiere el TTS.

## Corpus de frases reales

Archivo: `test/fixtures/aura_conversation_corpus_es.json`
Prueba: `test/aura_conversation_corpus_test.dart`

| Categoría | Frases | Qué mide |
| --- | ---: | --- |
| `intents` | 195 | intención exacta de 24 categorías, incluidas 10 frases fuera de dominio |
| `followUps` | 60 | resolución de «bloquéalo», «analízalo», «aislala», resumen, explicación y repetición |
| `confirmations` | 48 | confirmación natural, con 22 negativas que **no** deben confirmar |
| `denials` | 25 | negación natural, con 10 frases que contienen «no» pero no son negaciones |
| **Total** | **328** | |

Las frases están escritas a mano, con acentos, voseo, muletillas y objetivos
reales (`example.com`, `banco.example`, paquetes Android). La prueba exige cero
errores en las cuatro categorías; no es una muestra tolerada, es una regresión
estricta.

### Resultado medido en CI

- Intención: **195/195 (100 %)** tras corregir `revisa la aplicación`, que antes
  caía en `unknown` porque el patrón aceptaba `app` + `licación` y no la palabra
  completa `aplicación`.
- Seguimiento: **60/60**.
- Confirmaciones: **48/48** tras reclasificar «sí, por favor» como afirmación
  válida (no contiene objetivo nuevo) y añadir «sí, mañana» como negativa.
- Negaciones: **25/25**.

## Límites declarados

- No hay toolchain de Flutter/Dart/Android en el entorno de trabajo. Todo se
  verificó con el workflow `Aura Flutter Quality` en GitHub Actions: formato,
  `flutter analyze`, pruebas, análisis de seguridad y pruebas nativas Python.
- El barge-in depende de que el reconocedor del sistema abra su propia pantalla.
  Al tocar el micrófono se detiene el TTS y se lanza el reconocedor; no se hace
  captura continua en segundo plano, que Android limitaría y que exigiría otro
  modelo de permisos.
- El corpus mide el parser determinista, no la calidad del modelo local. Una
  frase ambigua fuera del corpus puede seguir cayendo en `unknown`; el
  planificador local es el respaldo, no una garantía.
