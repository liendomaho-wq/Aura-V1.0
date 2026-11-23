# Link Guard, actividad real y endurecimiento (2026-11-22)

Esta entrega implementa la primera rebanada acordada: corregir el veredicto del
clasificador léxico, mostrar cada proceso real de Aura y cerrar dos vectores de
captura de toques. No hay datos simulados ni progreso artificial.

## 1. Link Guard: dos observaciones, tres bandas

El modelo 3.0.0 puntúa el **host completo**. La auditoría reproducible
(`tool/audit_classifier_quality.py`) mostró que eso castiga subdominios largos y
legítimos: `pubmed.ncbi.nlm.nih.gov` y `thewaltdisneycompany.com` reciben 1.000,
y el 19,15 % de los hosts legítimos de 16–25 caracteres se marcaban como
amenaza.

La corrección no toca el bosque entrenado. Añade una segunda observación y una
política explícita:

| Observación | Cómo se obtiene | Qué mide |
| --- | --- | --- |
| Host | El bosque sobre el host observado | Rareza léxica del nombre completo |
| Dominio registrable | El mismo bosque sobre el eTLD+1 | Rareza del dominio que la persona reconoce |

`AuraHostPolicy` (`lib/inference/aura_host_policy.dart`) define:

- `reviewFloor = 0.35`: por debajo no se muestra ninguna señal.
- `highFloor = 0.65`: **prioridad alta solo si host y eTLD+1 la alcanzan**.
- Si una sola observación supera 0.35, la banda es **revisión**: se explica, no
  se bloquea y no se eleva el estado del Escudo.
- Una puntuación fuera de `[0, 1]` o no finita lanza `ArgumentError`; no se
  recorta en silencio.

El eTLD+1 se calcula sin red y sin Public Suffix List completa: hay una lista
conservadora de sufijos de dos niveles (`com.ar`, `com.ve`, `co.uk`, …). Los
sufijos privados (`github.io`) se excluyen a propósito.

### Efecto medido (modelo 3.0.0, corpus de 4.959 dominios legítimos)

| Métrica | Antes | Ahora |
| --- | --- | --- |
| Falso positivo con umbral 0.50 | 3,55 % | 3,55 % (el modelo no cambió) |
| Falso positivo en banda **prioridad alta** | 3,55 % | **2,28 %** (113/4.959) |
| Cobertura de banda revisión o alta en legítimos | — | 5,04 % |
| DGA sintético detectado en banda alta | — | **90,8 %** |
| Phishing sintético detectado en banda alta | — | **96,7 %** |

La banda alta reduce el falso positivo un 36 % relativo sin perder cobertura
DGA. La banda revisión añade 137 dominios legítimos (2,76 %) que antes se
presentaban como amenaza y ahora se presentan como revisión.

### Puerta de calidad en CI

`tool/ci_classifier_gate.py` ejecuta la auditoría y falla si se degrada:

```
FPR legítimo ≤ 4,50 %      FPR banda alta ≤ 3,00 %
DGA ≥ 92 %                 DGA banda alta ≥ 88 %
Phishing ≥ 96 %
```

Está conectada en `.github/workflows/flutter-quality.yml`. El paso es real: si
el modelo o la política empeoran, el job falla.

### Límite declarado

El asset del modelo **no declara** `decision_threshold`; el cliente aplica 0,50
(`AuraAIInference.decisionThresholdForModel`). La puerta lo imprime como aviso.
La banda de revisión no depende de ese valor, pero declararlo sigue pendiente.

## 2. Actividad de Aura: un registro, no una animación

`lib/agent/aura_activity.dart` es una función pura que fusiona:

- los eventos del `AgentController` (`history` y `events`), con `phase`
  explícita (`started` / `completed`) y `operation_id`;
- la auditoría cifrada de operaciones (`readSecureOperationAudit()`);
- los eventos de red que el Escudo ya entrega (`NetworkAuditEvent`).

Reglas:

- Una operación iniciada y sin resultado se muestra **en curso**. No se inventa
  un porcentaje ni se avanza una barra.
- Un resultado con `ok: false` se muestra **falló**, con el error acotado.
- Los argumentos se reducen a sus **nombres**; nunca se guardan valores ni
  contenido de páginas.
- La etiqueta `PENSANDO...` se descarta: era una simulación de progreso.
- La lista se ordena por hora real, se limita a 200 entradas y se puede filtrar
  por motor, red o incidencias.

La superficie es una hoja inferior (`lib/screens/aura_activity_sheet.dart`) que
se abre desde un glifo de baja énfasis en la cabecera. Es de solo lectura: no
pausa el agente ni el Escudo. El texto de cierre lo dice de forma explícita:
«Una operación sigue “en curso” hasta que el motor informa su resultado; no hay
progreso simulado.»

## 3. Endurecimiento

- **Tapjacking**: `window.decorView.filterTouchesWhenObscured = true` en
  `MainActivity.onCreate`. Android descarta los toques marcados como
  «obscured» cuando otra ventana tapa la actividad; una superposición ya no
  puede activar el Escudo, confirmar una purga ni abrir una hoja.
- **Miniaturas de recientes**: `setRecentsScreenshotEnabled(false)` desde
  Android 13. La vista de recientes ya no conserva dominios, hallazgos ni
  estado del dispositivo. No se aplica `FLAG_SECURE` porque impediría las
  capturas que el usuario sí controla.
- **Telemetría honesta**: una detección de blocklist sin bloqueo ya no se envía
  al canal nativo como si fuera un bloqueo. Se guarda localmente y se omite el
  envío remoto; el contrato nativo solo admite `blocked` y `allowed`.
- **Sin esperas teatrales**: el arranque espera al siguiente frame real
  (`endOfFrame`) en vez de dos `Future.delayed(350 ms)`.

## 4. Cómo verificar

Local, sin emulador:

```bash
python3 tool/audit_classifier_quality.py            # métricas completas
python3 tool/ci_classifier_gate.py                  # puerta de calidad
python3 -m pytest -q tool/test_audit_classifier_quality.py
```

En CI (`Aura Flutter Quality`): `dart format`, `flutter analyze`,
`flutter test`, la puerta de calidad y la suite Python.

En un dispositivo Android (TECNO POVA 5, Android 14):

1. Abrir Aura y pulsar el glifo de actividad de la cabecera.
2. Ejecutar «audita el dispositivo» y observar la entrada pasar de **en curso**
   a **confirmado** o **falló** con su hora y duración.
3. Con una app de superposición activa, intentar pulsar el Escudo: el toque se
   descarta y el estado no cambia.
4. En Recientes, comprobar que la miniatura de Aura no muestra el contenido.

## 5. Lo que no se ejecutó aquí

No hay toolchain de Flutter/Dart/Android en este entorno. `dart format`,
`flutter analyze`, `flutter test` y la compilación Kotlin se verifican en CI; no
se afirman como ejecutados localmente. La parte Python sí se ejecutó: auditoría,
puerta y 3 pruebas de contrato.
