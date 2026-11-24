# Auditoría de producto, IA y estrategia — Aura Mobile Defens

**Fecha:** 2026-11-22
**Rama:** `arena/97c7b3bf-aura-v1-0` (base `2a22ef9`)
**Alcance:** `lib/`, `android/`, `tool/`, `docs/`, asset del modelo, CI y estado de GitHub.
**Naturaleza:** auditoría independiente de código y producto. No es una certificación de seguridad.
**Documento complementario:** [concepto visual navegable](design/aura-v2-concept.html).

---

## 0. Ficha, método y límites de esta auditoría

### Qué revisé

- 22.171 líneas Dart en `lib/` (53 archivos), 2.491 de ellas en una sola pantalla.
- 27 archivos Kotlin en `main` (37 contando pruebas), integración JNI/HEV, manifiesto y Gradle.
- El asset del modelo (`assets/model/aura_brain_model.json`, 3,0 MB) y su hash.
- 39 archivos de prueba Flutter, 21 documentos de `docs/` y la matriz de estado.
- GitHub: los 11 PR abiertos y las ejecuciones de Actions más recientes.

### Qué **no** pude ejecutar

| Comprobación | Estado | Motivo |
|---|---|---|
| `flutter analyze` / `flutter test` | **No ejecutado** | No hay SDK de Flutter ni Dart en este entorno. |
| Build Android / JNI | **No ejecutado** | Sin JDK, SDK 36 ni NDK en el entorno. |
| Pruebas en dispositivo | **No ejecutado** | No hay teléfono ni emulador conectado. |
| Evaluación del clasificador | **Ejecutada** | Reimplementada en Python y medida sobre el asset real. |
| Revisión de CI en GitHub | **Ejecutada** | Últimos runs de `main`: verdes. |
| Grokbot | **No disponible aquí** | No hay conector de Grok/xAI en esta sesión. Ver §8. |

Por la misma regla que ya usa este repositorio: **un test que no se ejecutó no es evidencia**.
Lo que sigue distingue siempre código leído, medición ejecutada y afirmación de terceros.

### Estado de GitHub observado

- Últimos runs de `main` (`2a22ef9`, "fix(vault): delete the AES key on the next start"):
  - **Aura Android Debug Build**: éxito, 22m 58s.
  - **Aura Flutter Quality**: éxito, 1m 56s.
- **11 PR abiertos**: `#1`, `#4`, `#8`, `#12`, `#13`, `#14`, `#16`, `#17`, `#19`, `#28`, `#30`.
  Cuatro no son borrador y apuntan a `main` (`#1`, `#8`, `#28`, `#30`); el resto sigue en draft.
- Versión de la app: `1.0.2+3`. `minSdk 24`, `targetSdk 36`, tres ABI.

---

## 1. Veredicto en cinco minutos

### Lo que pienso ahora de Aura

Aura **no es un juguete**. Es uno de los proyectos móviles de ciberdefensa más honestos que se
pueden auditar en código abierto-propietario: separa lo que observa de lo que infiere, exige
confirmación para acciones con efecto, falla cerrado, valida la firma del modelo y documenta sus
límites en vez de esconderlos. Eso es raro y vale mucho.

Y al mismo tiempo, **hoy no está listo para recomendarle a una persona normal que confíe su teléfono
a Aura**. No por falta de talento, sino por tres brechas concretas:

1. **El clasificador genera demasiados falsos positivos en dominios legítimos largos** (medido:
   3,55 % en el top-5000; **19,15 %** en dominios de 16–25 caracteres; 100 % por encima de 25).
2. **La interfaz no responde la pregunta que el usuario hace**: "¿estoy bien y qué hago ahora?".
   Hay 67 tamaños de texto por debajo de 12 px, siete acciones escondidas en un carrusel y un
   registro tipo syslog como contenido principal.
3. **El vector móvil dominante —un enlace en un SMS o WhatsApp— no entra en el producto**. El
   smishing es el 69,3 % del phishing móvil según Zimperium; Aura solo analiza dominios que alguien
   le escribe a mano.

### Nota global (mi estimación, con rúbrica explícita)

| Lectura | Nota |
|---|---:|
| **Como producto listo para el usuario final** | **47 / 100** |
| Como referencia de ingeniería auditable | **74 / 100** |
| **Como lo puntuaría el panel de lanzamiento de un líder** | **25–32 / 100** |
| En una revisión de consumidor tipo Malwarebytes/Bitdefender | 30–38 / 100 |
| En una due diligence técnica tipo Zimperium/Lookout | 50–58 / 100 |

No es una nota oficial: es mi estimación con la rúbrica de §5, pesos incluidos. La explicación de
por qué el panel de un líder puntúa más bajo que un ingeniero está en §5.3.

### Las cinco apuestas que cambiarían la trayectoria

1. **Aura Link Guard**: compartir un enlace desde WhatsApp/SMS y obtener un veredicto local en
   menos de un segundo, con motivos y límites. (§9.2)
2. **Postura con cobertura**: un número (p. ej. 68/100) que siempre diga qué se revisó y qué no.
   Nunca "estás seguro". (§6.4)
3. **Modo Evidencia**: informe exportable, firmado localmente, con hallazgos, límites y fechas,
   útil para periodistas, activistas y pymes. (§9.2)
4. **Arreglar la IA que ya existe antes de comprar otra**: eTLD+1, banda de revisión, calibración y
   umbral declarado. Medido y priorizado en §7.
5. **Rediseño de jerarquía, no de identidad**: tres destinos, una acción prioritaria, tipografía
   legible, una sola animación activa. (§6)

---

## 2. Qué es Aura hoy (mapa real)

| Capa | Implementación observada | Madurez |
|---|---|---|
| UI Flutter | Consola única, avatar `CustomPainter`, anillos de capacidad, constelación de intenciones, filamento de comando | Prototipo avanzado |
| Agente | Parser determinista por reglas, allowlist de herramientas, confirmación `CONFIRMO` de un uso, plazos, postcondiciones | Sólido en política |
| LLM local | DeepSeek-R1-Distill-Qwen-1.5B Q4_K_M, descarga con consentimiento, SHA-256, runtime llama.cpp, una propuesta de solo lectura | Integrado, no medido en hardware |
| Clasificador | Random forest de 500 árboles, 6 características, asset firmado, inferencia en isolate | Funcional, con sesgo medible |
| Hallazgos | Motor determinista de solo lectura, severidad y confianza separadas, UI expandible | Buen diseño |
| VPN/Escudo | `VpnService` → TUN → HEV, SOCKS5 autenticado, filtros DNS/SNI/TCP 853 | Funciona en un POVA 5 |
| Almacenamiento | SecureVault, AES + HMAC, Keystore, purga con borrado diferido de clave | Bien pensado |
| Telemetría | Opt-in, HMAC de dominios, 500 eventos | Correcto |
| Distribución | APK de depuración, sin Play Store, sin iOS, sin política pública de privacidad enlazada | Inexistente |

**Lectura:** Aura ya tiene el "cuerpo" de un producto de seguridad serio, pero todavía no tiene el
"rostro" ni el "hábito". La ingeniería se adelantó al producto.

---

## 3. Evidencia medida del motor de IA

Reproducible con:

```sh
python3 tool/audit_classifier_quality.py
python3 tool/audit_classifier_quality.py --json
```

Este script replica la extracción de las seis características de
`lib/inference/aura_ai_inference.dart` y recorre el bosque con la misma lógica que el cliente.

### 3.1 Estructura del asset

| Propiedad | Valor |
|---|---|
| Modelo | Aura Lexical Threat Forest **3.0.0** |
| Árboles | 500 |
| Profundidad máxima | 10 (media de hoja: 7,05) |
| `min_samples_leaf` | 2.048 |
| Muestras de entrenamiento | 339.279 |
| `training_status` | `heuristic_seed_with_csv` |
| `decision_threshold` declarado | **ausente** → el cliente usa 0,50 |
| SHA-256 | `d190dddf…92ba2` (coincide) |

Reparto de bifurcaciones por característica:

| Característica | Peso en el bosque |
|---|---:|
| `length` | 28,2 % |
| `shannon_entropy` | 24,3 % |
| `vowel_ratio` | 19,6 % |
| `consonant_sequence_ratio` | 15,1 % |
| `digit_ratio` | 11,6 % |
| `suspicious_tld` | **1,0 %** |

**Longitud + entropía explican más de la mitad del modelo.** El TLD sospechoso casi no participa.
Esto no es un clasificador de phishing: es un detector de "nombres raros y largos". Útil como señal,
insuficiente como veredicto.

### 3.2 Falsos positivos sobre tráfico legítimo popular

Corpus: 5.000 dominios populares empaquetados en el repo, menos los cubiertos por la allowlist
estática (4.959 hosts evaluados).

| Métrica | Resultado |
|---|---:|
| FPR global | **3,55 %** (176 hosts) |
| Hosts ≤15 caracteres | 0,38 % (4.229) |
| Hosts de 16–25 caracteres | **19,15 %** (705) |
| Hosts de 26–35 caracteres | **100 %** (25) |
| Scores exactamente 0,0 | 72,0 % del corpus |
| Scores exactamente 1,0 | 0,5 % |

Ejemplos reales marcados con 1,000 (sin allowlist): `pubmed.ncbi.nlm.nih.gov`,
`nationalarchives.gov.uk`, `thewaltdisneycompany.com`, `worldpopulationreview.com`,
`sandiegouniontribune.com`. Y `noticias.caracoltv.com` obtiene **0,834**.

Esto es exactamente lo que rompe la confianza: el usuario ve "POSIBLE AMENAZA" en un diario o en un
portal de gobierno y aprende a ignorar a Aura.

> **Contexto honesto:** el model card ya reconoce un FPR holdout de **10,72 %** y un recall de
> **75,89 %**. Mi medición no contradice ese documento; lo confirma con otro corpus. El problema no
> es que el dato esté oculto: es que el dato, con el modelo en producción, sigue siendo alto.

### 3.3 Detección sobre conjuntos sintéticos (no es una evaluación real)

| Conjunto (generado por el script) | Detección @0,50 |
|---|---:|
| DGA aleatorio | 94,6 % |
| Consonantes aleatorias | 64,3 % |
| Typosquatting / prefijos | **37,5 %** |
| Patrón de phishing (`marca-verify.tld`) | 97,7 % |

El modelo detecta bien lo que parece aleatorio y mal lo que imita una marca. Justo el caso más
frecuente en un SMS.

### 3.4 Barrido de umbral

| Umbral | FPR popular | Detección DGA sintética |
|---:|---:|---:|
| 0,3 | 5,42 % | 98,8 % |
| 0,4 | 4,54 % | 96,6 % |
| **0,5 (actual)** | **3,55 %** | **94,6 %** |
| 0,6 | 2,98 % | 92,4 % |
| 0,7 | 2,52 % | 87,4 % |
| 0,8 | 2,00 % | 78,4 % |

No existe un umbral que dé a la vez FPR bajo y recall alto con estas seis características. Subir el
umbral no arregla el problema de fondo: **lo desplaza**.

### 3.5 Ablaciones

| Variante | FPR popular | Detección DGA |
|---|---:|---:|
| Host completo (actual) | 3,55 % | 94,6 % |
| Solo dominio registrable (eTLD+1) | **3,02 %** | 94,6 % |
| Sin la característica `suspicious_tld` | 3,55 % | 92,0 % |

Dos conclusiones:

1. Puntuar el dominio registrable en lugar del host completo quita falsos positivos **sin perder
   detección** y arregla casos como `noticias.caracoltv.com` (de 0,834 a 0,000).
2. `suspicious_tld` aporta 2,6 puntos de recall y **cero** de FPR: es una característica débil, no
   el problema.

### 3.6 Prueba exploratoria: detector de "lookalike"

Antes de recomendar una capa de marcas, probé un prototipo rápido (normalización de dígitos +
prefijos/sufijos + Levenshtein contra 3.589 marcas del top-5000). Resultado: **16 % de detección con
0,09 % de FP**. Peor que el bosque en typosquatting. Lo descarté y lo dejo documentado: una capa de
marcas **necesita lista curada, índice y evaluación**, no un heurístico improvisado.

---

## 4. Hallazgos priorizados

Severidad: **P0** = bloquea uso real o confianza; **P1** = necesario para competir; **P2** = deuda.

### P0

| ID | Hallazgo | Evidencia | Acción |
|---|---|---|---|
| H-01 | FPR del clasificador en dominios legítimos largos | 3,55 % global; 19,15 % en 16–25 caracteres; 100 % en >25 | eTLD+1 + banda de revisión + popularidad; §7.3 |
| H-02 | El asset no declara `decision_threshold` ni calibración | `decision_threshold` ausente; votos ≠ probabilidad | Calibrar y firmar el umbral con el modelo |
| H-03 | Mensaje "POSIBLE AMENAZA" sin banda de confianza | `lib/ai_brain.dart:784` | Tres bandas: sin señal / revisar / prioridad alta |
| H-04 | El vector #1 móvil (smishing) no tiene superficie de entrada | Sin share intent, sin azulejo, sin portapapeles | Aura Link Guard (§9.2) |
| H-05 | Tipografía ilegible y objetivos táctiles pequeños | 67 tamaños <12 px; mínimo 6,5 px; targets 26–38 dp | §6.3 y §6.6 |
| H-06 | Una sola pantalla de 2.491 líneas sin navegación | `lib/screens/aura_core_screen.dart` | Tres pantallas: Aura / Escudo / Evidencia |

### P1

| ID | Hallazgo | Evidencia | Acción |
|---|---|---|---|
| H-07 | El modelo evalúa el host completo, no el dominio registrable | `noticias.caracoltv.com` 0,834 | Cambiar extracción y añadir features de subdominio |
| H-08 | Typosquatting débil | 37,5 % sintético | Lista curada de marcas LATAM + índice + evaluación |
| H-09 | Sin evaluación continua en CI del clasificador | No hay job con umbrales de FPR/recall | Integrar `tool/audit_classifier_quality.py` con gates |
| H-10 | Cuatro animaciones concurrentes sin presupuesto de batería | avatar 3,2 s, anillos 4 s, filamento 1,6 s, campo 26 s | Una activa; pausar en segundo plano; medir %/h |
| H-11 | Sin onboarding ni primera misión | Arranque = consola + "silencio" | Primera misión de 60 s con un enlace real |
| H-12 | LLM 1,5 B / 1,1 GB sin medición en el POVA 5 | Docs lo admiten | Medir tokens/s, RAM, primer token, batería; considerar 0,5–1 B |
| H-13 | Dos parsers y dos enums con el mismo nombre | `AuraIntentKind` vs `AuraIntent` | Unificar contrato o documentar el adaptador |
| H-14 | `QUERY_ALL_PACKAGES` sin justificación pública | Manifiesto; 9 permisos | `<queries>` específicas + declaración para Play |
| H-15 | Sin historial persistente de hallazgos ni exportación | Matriz: "solo lectura" | Modo Evidencia exportable |
| H-16 | Sin política de privacidad pública ni ficha de tienda | `docs/PRIVACY.md` es interno | Publicar y enlazar desde la app |

### P2

| ID | Hallazgo |
|---|---|
| H-17 | El agente responde con voz inconsistente (voseo, "usted", "operador", "Ingrese") |
| H-18 | `analyzeHostSecure` devuelve `true` cuando **no** es amenaza; nombre engañoso |
| H-19 | Duplicación de namespaces `com.ciberdefensa.aura` / `com.aura.cyberdefense` |
| H-20 | Guards de Python que leen el fuente no prueban comportamiento (ya reconocido en la matriz) |
| H-21 | Sin iOS, sin sincronización, sin multi-dispositivo |
| H-22 | Sin pruebas de escala de texto, TalkBack ni rotación documentadas |

---

## 5. Calificación

### 5.1 Rúbrica usada (0–100, pesos para producto de consumo)

| Dimensión | Peso | Nota | Justificación breve |
|---|---:|---:|---|
| Seguridad técnica y honestidad | 20 % | **80** | Política de confirmación, fail-closed, integridad, límites documentados |
| IA y detección | 15 % | **40** | Modelo léxico sesgado, FPR alto, sin calibración ni evaluación en CI |
| UX/UI y accesibilidad | 15 % | **50** | Identidad fuerte, jerarquía y tipografía débiles |
| Calidad y validación en dispositivos | 15 % | **35** | CI verde, un solo teléfono, matriz y batería pendientes |
| Producto y propuesta de valor | 15 % | **38** | No hay hábito, ni onboarding, ni flujo diario |
| Distribución, legal y soporte | 10 % | **15** | Sin tienda, privacidad pública, soporte ni actualizaciones |
| Negocio y sostenibilidad | 5 % | **8** | Sin modelo de ingresos definido |
| Documentación y auditabilidad | 5 % | **85** | Excelente, aunque a veces más larga que el producto |
| **Total ponderado** | **100 %** | **47** | |

### 5.2 Cómo subir de 47 a 70 en 90 días

| Movimiento | Delta estimado |
|---|---:|
| FPR ≤2 % + banda de revisión + Link Guard | +7 en IA, +4 en producto |
| Rediseño de las tres pantallas + accesibilidad | +10 en UX |
| Matriz de 5 dispositivos + batería + pruebas de accesibilidad | +8 en calidad |
| Política de privacidad, ficha de tienda, canal de soporte | +6 en distribución |
| Onboarding y primera misión | +4 en producto |

No hace falta un modelo más grande para llegar a 65. Hace falta **cerrar el bucle producto-datos**.

### 5.3 Qué nota le darían los grandes, y por qué

Los líderes no puntúan con la rúbrica de un ingeniero. Puntúan con la suya:

| Escenario | Nota estimada | Criterios que aplican |
|---|---:|---|
| **Panel de lanzamiento (CrowdStrike/Lookout/Zimperium)** | **25–32** | ¿Podemos dárselo a 10 M de dispositivos? ¿SLA? ¿SOC 2/ISO 27001? ¿matriz de dispositivos? ¿soporte 24/7? ¿telemetría de flota? Aura no tiene casi nada de eso. |
| **Revisión de consumidor (Malwarebytes/Bitdefender)** | 30–38 | FPR, claridad, precio, marca, tienda, actualizaciones. El FPR medido hunde la nota. |
| **Due diligence técnica de arquitectura** | 50–58 | Diseño de permisos, confirmaciones, integridad del modelo, separación de capas. Aquí Aura sorprende. |
| **Programa de seguridad para periodistas/ONG** | 55–65 | Privacidad local, sin cuentas, transparencia, explicabilidad. Aura encaja, con reservas por FPR. |
| **Auditoría de documentación** | 80–88 | Aquí Aura está por encima de muchos productos comerciales. |

**La brecha no es de código: es de producto, evidencia en dispositivos y confianza operativa.**
Un líder no pregunta "¿el modelo es bonito?"; pregunta "¿qué pasa cuando falla y quién responde?".

---

## 6. Rediseño visual: de consola a presencia con evidencia

**Abre primero** [`docs/design/aura-v2-concept.html`](design/aura-v2-concept.html). Es un concepto
navegable, no una captura; las cifras son de ejemplo.

### 6.1 Diagnóstico concreto (medido en el código, no impresiones)

1. **67 declaraciones de `fontSize` por debajo de 12 px**; la más pequeña es **6,5 px**
   (`aura_signal_header.dart`). En un teléfono de 6" con sol, no se lee.
2. **Siete acciones** en `AuraIntentConstellation`, en scroll horizontal, con 9 px de etiqueta.
3. **Contenido principal = `_SyslogLine`**: el usuario ve líneas de registro antes de saber si está bien.
4. **Objetivos táctiles** de 26, 30, 32, 34, 36 y 38 dp. El mínimo recomendado es 44–48.
5. **Cuatro animaciones** simultáneas con `repeat()` y sin pausa en segundo plano.
6. **Sin estado vacío útil**: `_SilentStream` no dice qué hacer.
7. **Sin navegación**: todo compite en una sola pantalla.
8. **El contraste es bueno** (cuerpo 8,3:1; cian 12:1; ámbar 12,8:1). El problema es tamaño y
   densidad, no color. **No cambies la paleta.**

### 6.2 Principios del rediseño

- **Identidad intacta:** fondo noche, cian para acción/información, violeta para voz/IA, verde para
  lo confirmado, ámbar para revisión, coral solo para crítico. El avatar sigue siendo el centro.
- **Una pregunta por pantalla:** Aura = "¿estoy bien?"; Escudo = "¿qué está haciendo?"; Evidencia =
  "¿por qué?".
- **Veredicto antes que evidencia.** La evidencia se puede expandir, no se impone.
- **Un solo siguiente paso.** Si hay tres problemas, se muestra el de mayor prioridad y se agrupa el resto.
- **La cobertura es parte del mensaje.** Ningún número sin "qué se revisó" y "qué no".
- **Movimiento con presupuesto.** Una animación activa; el resto estática; respetar reducir movimiento.

### 6.3 Sistema de diseño propuesto

| Token | Valor | Uso |
|---|---|---|
| `bg` | `#05070F` | Fondo |
| `surface` | `#0B1424` | Tarjetas |
| `line` | `#1E3350` | Bordes |
| `text` | `#EEF6FF` | Cuerpo |
| `muted` | `#93A9C7` | Secundario (7,5:1 sobre superficie) |
| `cyan` | `#39D9FF` | Acción, información |
| `violet` | `#9A6BFF` | Voz, IA, exportación |
| `green` | `#3CE6B2` | Confirmado |
| `amber` | `#FFC45E` | Revisión |
| `coral` | `#FF5F7E` | Crítico |
| Tipografía | 28/22/16/13,5/11 | Título, hero, tarjeta, cuerpo, etiqueta |
| Espaciado | 4/8/12/16/24/32 | Retícula de 4 |
| Radios | 12/16/20/26 | Consistencia |
| Movimiento | 180–260 ms, `easeOut` | Sin rebotes |

Regla dura: **ningún texto funcional por debajo de 11 px**; cuerpo mínimo 13 px; etiquetas en
mayúsculas solo ≥10 px con tracking 1,2.

### 6.4 Anatomía de la pantalla de inicio

```
┌──────────────────────────────────────────┐
│ AURA   defensa local        ● Escudo ON │
├──────────────────────────────────────────┤
│                                          │
│              [avatar + anillos]          │
│              Hola, soy Aura.             │
│   Escudo activo. Puedo revisar qué       │
│   cambió hoy.                            │
│   ● MODELO  ● CLASIFICADOR  ◐ ESCUDO     │
│                                          │
│ ┌──────────────────────────────────────┐ │
│ │ 68/100  Postura del dispositivo      │ │
│ │         4 de 6 capas revisadas       │ │
│ │ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬░░░░  (cobertura)   │ │
│ │ Una postura no certifica ausencia    │ │
│ │ de amenazas.                         │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ ┌─ SIGUIENTE PASO · prioridad media ───┐ │
│ │ Revisá 2 apps con accesibilidad      │ │
│ │ activa                               │ │
│ │ [Revisar ahora]  [Ahora no]          │ │
│ └──────────────────────────────────────┘ │
│                                          │
│ [Analizar enlace] [Escudo] [Informe]     │
│                                          │
│ HOY · 3 eventos                          │
│ ⚠ Dominio parecido a phishing  0,71      │
│ ● 534 paquetes fuera del túnel           │
│ ✓ Modelo y firma verificados             │
├──────────────────────────────────────────┤
│ Pedile algo a Aura…       [🎙]  [↑]      │
├──────────────────────────────────────────┤
│   Aura          Escudo          Evidencia│
└──────────────────────────────────────────┘
```

### 6.5 Detalle por pantalla

**Aura (inicio)**
- Hero con avatar y **una frase de estado derivada de datos reales**, no de un temporizador.
- Tarjeta de postura con **anillo de cobertura**: verde = revisado, ámbar = parcial, gris = fuera de
  alcance. El número nunca va solo.
- **Siguiente paso** con dos botones: acción y "ahora no". El "ahora no" es importante: da control.
- Tres destinos primarios: Analizar enlace, Escudo, Informe. La ayuda y la auditoría se mueven a
  ajustes y a Evidencia.
- Evidencia resumida: máximo tres eventos, lenguaje humano ("534 paquetes fuera del túnel"), no syslog.

**Escudo**
- Interruptor grande con estado verificado y explicación de una línea.
- Métricas de sesión: tiempo, tráfico, dominios filtrados, último cambio de red.
- Reglas con interruptores (DNS cifrado, bloqueos propios, avisos del clasificador **desactivados por
  defecto** para no bloquear por ML).
- **Límites conocidos en la misma pantalla**: QUIC/ECH/DoH propio no se descifran. Esto es una
  ventaja de confianza, no una debilidad que esconder.

**Evidencia**
- Filtros: Todas / Red / Apps / Postura.
- Cada hallazgo: severidad, **confianza numérica**, "por qué", alcance, fecha, acción posible.
- "Leer por qué" despliega las características que más contribuyeron y el umbral usado.
- **Exportar informe** (`.md`/`.json`) con lo revisado, lo no revisado y los límites. Sin datos
  personales por defecto.

**Conversación**
- Un solo hilo, con respuestas cortas y un botón "ver evidencia" cuando Aura cita un dato.
- Confirmaciones como tarjeta explícita con caducidad visible ("válido 60 s"), no como texto en
  medio de un párrafo.
- Voz con estado visible y opción de cancelar antes de ejecutar.

### 6.6 Accesibilidad (criterios verificables)

| Criterio | Hoy | Meta |
|---|---|---|
| Texto mínimo | 6,5 px | ≥11 px |
| Cuerpo | 10–12 px | ≥13 px |
| Objetivo táctil | 26–38 dp | ≥44 dp |
| Contraste de cuerpo | 7,5–18:1 | ≥4,5:1 (ya cumple) |
| Escala de texto al 200 % | Sin probar | Sin recortes ni solapamientos |
| TalkBack | Avatar y estados | Tarjetas, gráficos y acciones |
| Reducir movimiento | Respetado | Mantener y ampliar a todo el movimiento |
| Teclado / foco | Sin probar | Orden lógico y foco visible |

### 6.7 Plan de implementación visual (por archivos)

1. `lib/theme/aura_tokens.dart`: añadir `AuraType`, `AuraMotion`, `AuraElevation`, `AuraSpacing`.
2. Nuevo `lib/theme/aura_semantics.dart`: mapear severidad → color/icono/etiqueta (una sola fuente).
3. Nuevo `lib/screens/aura_home_screen.dart` (hero + postura + siguiente paso).
4. Nuevo `lib/screens/aura_shield_screen.dart` (mover `_CoverageAuditCard` y reglas).
5. Nuevo `lib/screens/aura_evidence_screen.dart` (mover `_FindingsCenter`, `_SyslogLine` → tarjetas).
6. `aura_core_screen.dart`: reducir a shell + navegación; objetivo <400 líneas.
7. `lib/widgets/aura_presence.dart`: quitar micro-texto, subir tamaños, simplificar anillos.
8. `lib/widgets/aura_command_filament.dart`: objetivos ≥44 dp, sin pulso permanente.
9. `lib/widgets/aura_neural_field.dart`: pausar cuando la app no está en primer plano.
10. Pruebas: widget tests por pantalla, golden tests de estado vacío, prueba de escala 200 %.

**Regla de este repositorio que conviene mantener:** no afirmar que un cambio visual está "listo"
sin `flutter analyze`, tests y una captura en dispositivo. Este documento propone; no certifica.

---

## 7. IA: arreglar la que tienes antes de comprar otra

### 7.1 Realidad actual (sin marketing)

- El **agente** es determinista: reglas + allowlist + confirmaciones. No es un LLM.
- El **clasificador** es un bosque léxico de 6 características. No ve contenido, certificados,
  redirecciones ni reputación.
- El **LLM local** (1,5 B, 1,1 GB) solo entra cuando el parser no reconoce la orden; propone una de
  tres herramientas de solo lectura o responde un turno. **Nunca ejecuta.**
- **No hay evaluación continua** del clasificador en CI, ni umbral calibrado, ni bucle de feedback
  que convierta falsos positivos en datos de mejora.

Esto está bien diseñado desde la seguridad. El problema es la **calidad medida**.

### 7.2 Lo que hay que arreglar primero (2–4 semanas, sin modelo nuevo)

**A. Puntuar el dominio registrable, no el host completo.**
Extraer eTLD+1 con una lista de sufijos empaquetada (o, como mínimo, las dos últimas etiquetas con
excepciones tipo `co.uk`, `com.ar`, `com.ve`, `gob.ve`). Medido: FPR 3,55 % → **3,02 %**, misma
detección, y se corrige `noticias.caracoltv.com`.
*Archivo:* `lib/inference/aura_ai_inference.dart`, nueva función `_registrableDomain`.

**B. Dejar de usar un veredicto binario.**
Tres bandas explícitas:

| Score | Etiqueta | Comportamiento |
|---:|---|---|
| < 0,35 | Sin señal | Se registra como "revisado sin señal" |
| 0,35–0,65 | **Revisar** | Se muestra como sospecha, no como amenaza |
| ≥ 0,65 | Prioridad alta | Se ofrece bloqueo, **nunca automático** |

Esto no mejora el modelo, pero **mejora la confianza del usuario** inmediatamente y reduce la
sensación de falsa alarma.

**C. Declarar y calibrar el umbral con el asset.**
Añadir `decision_threshold`, `calibration` (`none|platt|isotonic`), `calibration_note` y
`score_kind: "vote_share"` al JSON firmado. El cliente ya tiene un fallback a 0,50; hoy es silencioso.
Un modelo sin umbral declarado no es un modelo versionado: es una convención implícita.

**D. Gate de calidad en CI.**
Integrar `tool/audit_classifier_quality.py` y fallar si:
- FPR popular > 3,0 % (hoy 3,55 %), objetivo 2,0 %;
- FPR en 16–25 caracteres > 12 % (hoy 19,15 %);
- detección DGA sintética < 90 % (hoy 94,6 %).

Los números sintéticos no son producción, pero **sí detectan regresiones**.

**E. Popularidad antes que ML.**
Antes de puntuar, comprobar una lista de dominios populares empaquetada y versionada. Si está en la
lista, se marca "conocido" y se omite el veredicto léxico; **pero se siguen evaluando subdominios
anómalos** (un `login-seguro.paypal.com` no debe pasar por ser subdominio de un dominio popular).
Documentar el punto ciego: un sitio popular comprometido no deja de ser un riesgo.

**F. Explicación contrafactual.**
"Este dominio se marcó por longitud (28) y entropía (3,9); si midiera menos de 20 caracteres, el
score bajaría a 0,2." Es más útil que un porcentaje solo y enseña al usuario a leer el modelo.

### 7.3 Reentrenar el modelo 3.1.0 (semanas 4–8)

El repositorio ya tiene el pipeline con 18 características y splits agrupados. Recomendaciones:

1. **Subir el listón de la puerta actual.** Hoy exige FPR ≤8 % y recall ≥65 %; para consumo debería
   ser **FPR ≤3 %** en un corpus popular independiente y **recall ≥80 %** en holdout agrupado.
2. **Evaluar por fuente y por familia de marca**, no solo global. Un recall de 80 % puede esconder
   un 40 % en marcas LATAM.
3. **Calibrar** (Platt o isotonic) y publicar la curva de calibración en el model card.
4. **Medir latencia y memoria en el POVA 5**: inferencia por host, primer resultado, RAM del isolate.
5. **Añadir features de dominio registrable y de subdominio por separado**: profundidad, etiqueta
   más larga, presencia de dígitos en el SLD, guiones, palabras de marca, palabras de acción
   (`login`, `verify`, `secure`, `account`).
6. **Eliminar o reetiquetar `suspicious_tld`**: 1 % de las bifurcaciones y 0 de FPR. O se sustituye
   por reputación de TLD por fuente, o se queda como feature menor.
7. **No promocionar** el candidato sin informe reproducible, licencias, evaluación separada y
   revisión de falsos positivos.

### 7.4 NLU híbrido (semanas 4–10)

El parser por reglas es correcto para acciones que cambian el estado. Para entender al usuario:

1. **Normalización** (ya existe) + **extracción de entidades** robusta: URL con ruta, punycode,
   correo, teléfono, nombre de paquete, IP, dominio con puerto.
2. **Fuzzy matching** de verbos contra el léxico de comandos (Levenshtein ≤2 sobre palabras, no sobre
   la frase). "bloquiame", "blokea", "bloquear" deben caer en la misma intención.
3. **Preguntas de aclaración** en vez de `unknown`: "¿Querés bloquear el dominio o solo analizarlo?".
4. **Memoria de conversación** acotada: última entidad, última acción, último resultado. Persistente
   solo si el usuario lo pide; borrable.
5. **Conjunto de evaluación** de 300–500 frases en español (incluye voseo, regionalismos y errores de
   tipeo), con intención y entidades esperadas. Gate: exactitud de intención ≥90 %, F1 de entidades ≥0,85.
6. **El LLM no es el router por defecto.** Úsalo para explicar o para desambiguar cuando el parser
   falla, con gramática restringida (GBNF) al JSON de dos claves que ya valida `LlmToolProposal`.

### 7.5 LLM local: qué actualizar y qué medir

| Decisión | Recomendación |
|---|---|
| Tamaño | Antes de bajar a 1,5 B, medir. Si el POVA 5 no sostiene 1,1 GB + 8K de contexto, evaluar 0,5–1 B Q4 (≈300–700 MB) con mejor español por tamaño. |
| Salida | Gramática GBNF obligatoria para JSON de herramientas; temperatura 0; `max_tokens` corto. |
| Streaming | Sí para texto conversacional, con cancelación real y sin prometer cancelación de trabajo nativo. |
| Contexto | Mantener la política adaptativa, pero **no anunciar 64K** hasta medirlo. |
| Batería | Presupuesto: ≤2 %/h con el LLM descargado pero no cargado; descargar al salir de primer plano. |
| Seguridad | El modelo sigue siendo entrada no confiable. Sin ejecución, sin cambios de política y sin elevar severidad. |
| Evaluación | 50 prompts de seguridad + 50 de conversación; medir alucinación, fuga de instrucciones y utilidad. |

### 7.6 Grok/xAI dentro del producto (opcional y con consentimiento)

Dos roles distintos, no confundirlos:

1. **Grokbot como compañero de desarrollo** (§8). No toca el runtime de la app.
2. **Un modo remoto opcional** para razonamiento complejo. Si algún día se implementa:
   - apagado por defecto; activación explícita por consulta;
   - aviso claro de qué sale del teléfono (texto de la consulta, no dominios completos si se puede);
   - sin ejecución de herramientas desde la nube;
   - registro local de cada envío y botón de apagado total;
   - política de retención y proveedor documentados;
   - y una nota en la app de que **la nube ve la IP y el contenido enviado**.

Sin esas condiciones, Aura perdería su principal diferencial: **defensa local que no pide cuentas**.

---

## 8. Grokbot como compañero de desarrollo

### 8.1 Qué es (y qué no)

Grokbot es la propuesta de agentes de xAI: agentes con nombre, computadora en la nube, navegador,
terminal y conectores, que ejecutan tareas de extremo a extremo y vuelven con el trabajo hecho. Está
pensado para automatización delegada, no para revisar línea por línea como un IDE
([MindStudio](https://www.mindstudio.ai/blog/grokbot-xai-agent-app),
[Grok Bots](https://grok-bots.com/what-is-grok-bot)).

**No hay conector de Grok en esta sesión**, así que no puedo invocarlo. La forma correcta de usarlo es
en paralelo a mí, con el mismo estándar de evidencia de este repositorio.

### 8.2 Reparto de trabajo propuesto

| Tarea | Quién | Por qué |
|---|---|---|
| Rediseño de pantallas y tokens | **Grokbot** implementa, **yo** reviso | Trabajo visual iterativo y paralelizable |
| Tests de widget y golden | **Grokbot** propone, **CI** decide | Volumen alto, criterio mecánico |
| Dataset de 300 frases NLU en español | **Grokbot** genera, **tú** validas | Requiere criterio lingüístico local |
| Reentrenamiento y calibración | **Yo** diseño, **Grokbot** ejecuta iteraciones | Riesgo alto: revisión obligatoria |
| Seguridad del túnel, JNI, Keystore | **Solo revisión humana** | Un error aquí es un incidente, no un bug |
| Documentación y model card | **Grokbot** redacta, **yo** verifico números | Trazabilidad |
| Red team de prompts y del clasificador | **Grokbot** ataca, **yo** clasifico | Buen uso adversarial |
| Firma de release y secretos | **Nadie automatizado** | Nunca darle keystore ni tokens |

### 8.3 Reglas de seguridad para el agente

1. **Nunca** darle `key.properties`, `.jks`, `.pem`, tokens de GitHub con permisos de administración
   ni datos de usuarios reales.
2. **Nunca** push a `main`; una rama por tarea y un PR por tarea.
3. **Nunca** aceptar "listo" sin comando ejecutado + salida + CI verde.
4. **Nunca** dejar que cambie las invariantes de seguridad: confirmación explícita, fail-closed,
   "el modelo no ejecuta", límites documentados.
5. **Siempre** pedirle que distinga hipótesis de medición.
6. **Siempre** revisar sus diffs de dependencias, permisos de Android y red.

### 8.4 Contrato de tarea (pegar tal cual)

```text
CONTEXTO
Repositorio: liendomaho-wq/Aura-V1.0 (Flutter + Kotlin + C/JNI).
Lee README.md, docs/AURA_STATUS_MATRIX.md y docs/AUDITORIA_PRODUCTO_2026-11-22.md.
No cambies la identidad visual (tema oscuro, cian/violeta, avatar protagonista).

TAREA
<una sola cosa, con archivos y criterios de aceptación>

RESTRICCIONES
- Rama nueva por tarea. PR a main. Nunca push directo a main.
- No tocar firma, keystore, secretos ni permisos de Android sin justificación explícita.
- No añadir dependencias sin justificar tamaño, licencia y mantenimiento.
- No ejecutar acciones de red que cambien el estado del dispositivo.
- Mantener confirmación explícita, fail-closed y "el modelo no ejecuta herramientas".

EVIDENCIA OBLIGATORIA
- Comandos ejecutados y su salida (flutter analyze, flutter test, build si aplica).
- Si no se pudo ejecutar algo, decirlo y no presentarlo como éxito.
- Captura o descripción de la pantalla en un dispositivo o emulador.
- Lista de archivos modificados y por qué.

ENTREGA
PR con título, resumen, riesgos, capturas y limitaciones.
```

### 8.5 Tres prompts concretos para empezar

**Prompt 1 — primera rebanada visual**
```text
Implementa en Flutter la pantalla "Aura inicio" del concepto docs/design/aura-v2-concept.html.
Crea lib/theme/aura_type.dart con la escala 28/22/16/13,5/11 y lib/widgets/aura_posture_card.dart.
No modifiques todavía la navegación ni el agente. Añade widget tests para: estado vacío, cobertura
parcial y escala de texto al 200 %. Entrega PR con capturas y salida de flutter test.
```

**Prompt 2 — evaluación del NLU**
```text
Genera tool/eval/intents_es.jsonl con 300 frases en español (voseo y tuteo, errores de tipeo,
regionalismos de Venezuela y Colombia) etiquetadas con intención y entidades para el parser de
lib/agent/aura_intent_parser.dart. No inventes intenciones que el parser no soporte. Incluye 50
casos negativos (frases con dos intenciones, inyección de instrucciones y confirmaciones negadas).
Escribe un test Dart que mida exactitud de intención y F1 de entidades. No cambies el parser.
```

**Prompt 3 — red team del clasificador**
```text
Analiza el clasificador léxico con tool/audit_classifier_quality.py. Propón 100 dominios
benignos reales difíciles (gobierno, prensa, bancos de LATAM, CDN, educación) y 100 maliciosos
plausibles (typosquatting de marcas LATAM, subdominios en hosting gratuito). Mide FPR y detección.
No modifiques el modelo ni el asset firmado. Entrega tabla, ejemplos y recomendaciones priorizadas.
```

### 8.6 Errores que hay que evitar con Grokbot

- Pedirle "mejora la IA" sin métrica: producirá cambios plausibles sin evidencia.
- Dejar que rediseñe toda la app en un PR: imposible de revisar.
- Confiar en su resumen sin ver el diff.
- Darle acceso al teléfono o a datos personales para "probar".
- Usarlo para saltarse CI o firmar artefactos.

**Regla simple:** Grokbot multiplica manos, no criterio. El criterio (y la responsabilidad) siguen
siendo tuyos y de quien revise.

---

## 9. Competencia y posicionamiento

### 9.1 Dónde están los grandes

| Referente | Fortaleza | Punto débil para tu usuario | Hueco que Aura puede ocupar |
|---|---|---|---|
| **Lookout** | Telemetría móvil masiva, phishing fuerte, integraciones SOC | Precio por dispositivo, venta enterprise, nube | Usuario individual sin MDM ni cuenta |
| **Zimperium** | Detección on-device profunda, amenazas dirigidas | Complejidad enterprise, coste | Simplicidad local, sin flota |
| **Check Point Harmony Mobile** | App, red y SO; anti-phishing; consola unificada | Mejor dentro del ecosistema Check Point | Independencia total |
| **Microsoft Defender for Endpoint** | Integración Intune/M365, precio incluido | Requiere ecosistema Microsoft | Android puro, sin licencias |
| **Jamf** | Excelente para Apple | Android limitado | Android primero |
| **SentinelOne Singularity Mobile** | Detección con analítica cloud | Consola y despliegue de flota | Sin nube, sin consola |
| **Malwarebytes / Bitdefender** | Marca, tienda, facilidad | Nube, suscripción, poca explicabilidad | Transparencia y evidencia local |
| **AdGuard / Blokada** | Bloqueo DNS eficaz y barato | Sin postura de dispositivo ni explicación de IA | Defensa + explicación + evidencia |
| **Cloudflare Gateway / Zscaler** | Control de red empresarial | Configuración y cuenta, orientado a empresa | Cero configuración, cero cuenta |

Fuentes de contexto MTD: comparativas de [CyberPress](https://cyberpress.org/mobile-threat-defense-by-business-size/),
[GBHackers](https://gbhackers.com/best-mobile-threat-defense-compared/) y
[Guideflow](https://www.guideflow.com/blog/mobile-data-security). Los precios son cotizados y el
foco es enterprise/BYOD con UEM.

### 9.2 El espacio que nadie cubre bien

**"Ciberdefensa personal, local y en español, con evidencia que se puede mostrar."**

Cinco apuestas concretas:

**1. Aura Link Guard (la más importante).**
Compartir un enlace desde WhatsApp/SMS/navegador → análisis local → veredicto con motivos, límites y
opción de abrir igualmente. Sin nube, sin cuenta, sin abrir la página. Responde al vector dominante:
Zimperium reporta smishing en el **69,3 %** del phishing móvil, con crecimiento del 22 % anual
([Zimperium](https://zimperium.com/resources/mobile-becomes-the-chosen-attack-vector-for-enterprises-zimperium-researchers-find)).
Verizon observó que en casi 4 de cada 10 empresas que hicieron simulaciones, hasta la mitad del
personal hizo clic ([compilación de estadísticas](https://nhimg.org/mobile-threat-statistics-guide)).
*Implementación Android:* `ACTION_SEND` + `intent-filter` para `text/plain`, `SEND`/`VIEW`,
`<queries>` acotadas, azulejo de Ajustes rápidos y atajo. Nada de accesibilidad ni de leer SMS sin
permiso explícito.

**2. Postura con cobertura.**
Un número honesto que diga "4 de 6 capas". Comprime semanas de incertidumbre en una cifra y educa al
usuario en los límites. Ningún competidor consumer lo hace bien.

**3. Modo Evidencia.**
Informe exportable (`md`/`json`) con hallazgos, fechas, motor, versión, confianza, alcance y límites,
firmado localmente. Para periodistas, activistas, abogados y pymes que necesitan **mostrar** por qué
tomaron una decisión. Es también una herramienta de rendición de cuentas del propio Aura.

**4. Eficiencia como característica.**
Presupuesto público: ≤2 % de batería por hora con el Escudo, veredicto p95 ≤400 ms, sin escaneos en
segundo plano no solicitados, modelo descargable y borrable. "No te come la batería" es una promesa
medible y hoy nadie la cumple bien en esta categoría.

**5. Aura para equipos pequeños (después).**
5–50 dispositivos sin MDM: cada persona conserva sus datos; el administrador solo ve agregados
(dispositivos actualizados, escudo activo, hallazgos críticos sin resolver). Es el puente comercial
natural, sin traicionar la promesa local.

### 9.3 Posicionamiento en una frase

> **Aura es la defensa móvil que trabaja en tu teléfono, te explica lo que ve y te muestra lo que no
> puede ver. Sin cuentas, sin nube y sin promesas absolutas.**

### 9.4 Qué la haría *necesaria* (no solo interesante)

- **Hábito:** share sheet, azulejo, widget y notificación con acciones. Que analizar un enlace cueste
  dos toques desde WhatsApp.
- **Confianza:** cero falsos positivos en sitios populares (objetivo ≤2 %) y explicación en lenguaje
  humano cuando se equivoca.
- **Utilidad demostrable:** primera misión de 60 segundos que termine en un hallazgo real o en un
  "revisado, sin señal".
- **Prueba social:** informes de evidencia que el usuario pueda compartir; casos de estudio con
  periodistas y pymes de LATAM.
- **Continuidad:** actualizaciones de reglas firmadas y offline; el producto no debe morir si no hay
  red.

---

## 10. Roadmap 30 / 60 / 90 y métricas

### 10.1 Primeros 30 días — confianza y legibilidad

| Semana | Entregable | Criterio de aceptación |
|---|---|---|
| 1 | eTLD+1 + banda de revisión + copy "revisar" | FPR popular ≤3,0 %; 0 cambios en detección DGA |
| 1 | `audit_classifier_quality.py` en CI con gates | Job falla si FPR >3,0 % o DGA <90 % |
| 2 | Rediseño de inicio y Evidencia (sin tocar agente) | Texto mínimo 11 px, targets ≥44 dp, 3 destinos |
| 2 | Onboarding de 3 pasos + primera misión | Un usuario nuevo analiza un enlace en <60 s |
| 3 | Link Guard v0 (share intent + pantalla de resultado) | Funciona desde WhatsApp en un dispositivo real |
| 3 | Política de privacidad pública + ficha de tienda interna | Enlazada desde ajustes |
| 4 | Matriz de 3 dispositivos + prueba de batería | Datos publicados, aunque sean malos |

### 10.2 Días 31–60 — calidad medible

- Reentrenar 3.1.0 con 18 features, splits agrupados y calibración; puerta FPR ≤3 %, recall ≥80 %.
- Evaluación NLU de 300 frases + fuzzy matching + aclaraciones.
- Postura con cobertura y exportación de informe.
- Reducir animaciones a una activa; medir consumo.
- Accesibilidad: escala 200 %, TalkBack, foco y contraste de todos los estados.

### 10.3 Días 61–90 — producto y distribución

- LLM: decidir tamaño con datos del POVA 5; gramática GBNF; streaming; presupuesto de batería.
- Modo Evidencia v1 firmado; plantilla para ONG/periodistas.
- Beta cerrada con 20–50 usuarios reales en Venezuela/Colombia; instrumentación opt-in mínima.
- Play Store interno (closed testing) con `QUERY_ALL_PACKAGES` justificado o eliminado.
- Plan comercial: núcleo gratis + "Evidencia Pro"/equipos; nunca venta de datos.

### 10.4 Métricas norte

| Área | Métrica | Objetivo 90 días |
|---|---|---|
| Activación | % que analiza un enlace en 24 h | ≥55 % |
| Hábito | Retención D7 / D30 | ≥25 % / ≥12 % |
| Confianza | FPR en dominios populares | ≤2 % |
| Confianza | % de sesiones con queja de falso positivo | <5 % |
| Utilidad | Hallazgos abiertos y resueltos por usuario | ≥30 % resueltos |
| Rendimiento | Veredicto p95 | ≤400 ms |
| Batería | Consumo con Escudo | ≤2 %/h |
| Estabilidad | Crash-free sessions | ≥99,5 % |
| Cobertura | Dispositivos validados | ≥5 modelos, 2 versiones de Android |
| Transparencia | Hallazgos con evidencia + límites | 100 % |

### 10.5 Gates: no lanzar si…

- FPR popular >5 % o sin medición.
- No hay política de privacidad pública enlazada.
- No hay matriz mínima de 5 dispositivos (incluido el POVA 5).
- No se probó la desinstalación/purga y la clave de la bóveda.
- Alguna acción con efecto puede ejecutarse sin confirmación explícita.
- Se anuncia "antivirus", "protección total" o "IA que ejecuta por ti".

---

## 11. Anexos

### A. Cómo reproducir la medición

```sh
python3 tool/audit_classifier_quality.py
python3 tool/audit_classifier_quality.py --json > /tmp/aura-classifier.json
```

El script no modifica el modelo ni requiere dependencias externas. Lee el asset y la lista de
dominios del propio repositorio.

### B. Salida resumida de esta ejecución

```text
Modelo: Aura Lexical Threat Forest 3.0.0
Estado de entrenamiento: heuristic_seed_with_csv
Umbral declarado en el asset: None (efectivo 0.50)
Bosque: 500 árboles, profundidad de hoja máxima 10, media 7.05
Uso de características:
  length                        28.2%
  shannon_entropy               24.3%
  digit_ratio                   11.6%
  vowel_ratio                   19.6%
  consonant_sequence_ratio      15.1%
  suspicious_tld                 1.0%
Votos de amenaza en hojas: 64.7%

Corpus legítimo (top-5000, sin allowlist): 4959 hosts, FPR 3.55% (176 marcados)
  longitud <=15  n=4229 FPR   0.38% score medio 0.010
  longitud 16-25 n= 705 FPR  19.15% score medio 0.236
  longitud 26-35 n=  25 FPR 100.00% score medio 0.968

Conjuntos sintéticos (no equivalen a una evaluación real):
  dga_synthetic                    detección  94.6% score medio 0.893
  consonant_random_synthetic       detección  64.3% score medio 0.613
  typosquat_synthetic              detección  37.5% score medio 0.465
  phishing_pattern_synthetic       detección  97.7% score medio 0.961

Barrido de umbral (FPR popular / detección DGA sintética):
  0.3 ->  5.42% /  98.8%
  0.4 ->  4.54% /  96.6%
  0.5 ->  3.55% /  94.6%
  0.6 ->  2.98% /  92.4%
  0.7 ->  2.52% /  87.4%
  0.8 ->  2.00% /  78.4%

Ablación:
  full_host                FPR  3.55% detección  94.6%
  etld1_only               FPR  3.02% detección  94.6%
  full_host_no_tld_feature FPR  3.55% detección  92.0%
```

### C. Checklist de auditoría visual

- [ ] ¿Se entiende el estado sin leer micro-texto?
- [ ] ¿Hay una sola acción prioritaria visible?
- [ ] ¿Cada número tiene cobertura o contexto?
- [ ] ¿Todo texto funcional mide ≥11 px y el cuerpo ≥13 px?
- [ ] ¿Los objetivos táctiles miden ≥44 dp?
- [ ] ¿La app funciona al 200 % de escala de texto?
- [ ] ¿TalkBack describe tarjetas y gráficos?
- [ ] ¿Los estados vacíos dicen qué hacer?
- [ ] ¿Hay una sola animación activa y se pausa en segundo plano?
- [ ] ¿Se ve claro qué se revisó y qué no?

### D. Glosario breve

- **eTLD+1 / dominio registrable:** `noticias.caracoltv.com` → `caracoltv.com`.
- **FPR:** proporción de casos legítimos marcados como amenaza.
- **Calibración:** convertir votos del bosque en probabilidades comparables.
- **GBNF:** gramática que restringe la salida de un LLM a un formato válido.
- **MTD:** Mobile Threat Defense, categoría enterprise de los líderes citados.

---

**Cierre.** Aura ya tiene lo más difícil: criterio de seguridad y honestidad. Lo que falta es
traducirlo en una experiencia que la gente use todos los días y en números que resistan una auditoría
externa. Si tuviera que elegir una sola cosa para los próximos 30 días, elegiría **Link Guard con el
clasificador corregido**: es el puente entre el motor que ya existe y el gesto que convierte a Aura en
necesaria.
