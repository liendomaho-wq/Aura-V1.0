# Aura Mobile Defens

«Defens» es ortografía intencional del producto; no corregir.

Reporta vulnerabilidades en [SECURITY.md](SECURITY.md).

## Índice

- [1. Arquitectura](#1-arquitectura)
  - [Estado de los cinco pilares de defensa](#estado-de-los-cinco-pilares-de-defensa)
  - [Contrato de características](#contrato-de-características)
  - [Blocklists de dominios](#blocklists-de-dominios)
  - [Telemetría opcional de clasificación](#telemetría-opcional-de-clasificación)
- [2. Incisiones integradas](#2-incisiones-integradas)
  - [Inspección de DoH/DoQ e IPv6](#inspección-de-dohdoq-e-ipv6)
- [3. Brain v2](#3-brain-v2)
  - [Rendimiento en dispositivo](#rendimiento-en-dispositivo)
- [Configuración de Codemagic para Producción](#configuración-de-codemagic-para-producción)
- [4. Pipeline de datos](#4-pipeline-de-datos)
- [5. Firma y seguridad Android](#5-firma-y-seguridad-android)
  - [Permisos y justificación](#permisos-y-justificación)
- [6. GitHub Actions](#6-github-actions)
- [7. Codemagic](#7-codemagic)
- [8. Estructura del repositorio](#8-estructura-del-repositorio)
- [9. Build y validación](#9-build-y-validación)
- [10. Licencias y atribución](#10-licencias-y-atribución)
- [11. Roadmap](#11-roadmap)
- [12. Código crítico auditado](#12-código-crítico-auditado)

**Versión de la aplicación:** `1.0.0+1` · **Versión del modelo:** `3.0.0` · **Estado:** En desarrollo

Aura Mobile Defens es una aplicación Android de ciberdefensa local construida con Flutter/Dart y componentes nativos Kotlin, JNI y C. Su núcleo combina un `VpnService` autorizado por la persona usuaria, un túnel TUN basado en `hev-socks5-tunnel`, inspección DNS/SNI, una allowlist y un clasificador local de dominios. No requiere root. No es una solución certificada ni garantiza cobertura integral: el alcance depende del dispositivo, permisos, conectividad y protocolos observables.

![Build de release signing](https://img.shields.io/github/actions/workflow/status/yojamm16-boop/Aura-V1.0/release-signing-integrity.yml?branch=main&label=release%20signing)
![Cobertura](https://img.shields.io/badge/cobertura-no%20medida-lightgrey)
![Modelo](https://img.shields.io/badge/modelo-3.0.0-blue)

El estado se marca **En desarrollo**: el repositorio tiene workflows de validación y artefactos del modelo publicados en GitHub Pages, pero este README no afirma que exista una release Android distribuida. La insignia de cobertura indica que no hay un porcentaje de cobertura medido y versionado.

## 1. Arquitectura

```text
┌──────────────────────────────────── Android ────────────────────────────────────┐
│ Operador → consola autenticada → control de defensa VPN                         │
│                                           │ MainActivity solicita consentimiento │
│                                           ▼                                       │
│                           AuraVpnService (Kotlin, VpnService) → TUN               │
│                                           ▼                                       │
│                              motor hev-socks5-tunnel (C)                          │
│                         ┌─────────────┴──────────────┐                            │
│                         │ DNS / SNI / firewall C     │                            │
│                         └─────────────┬──────────────┘                            │
│                                       │ JNI / MethodChannel / EventChannel         │
└───────────────────────────────────────┼──────────────────────────────────────────┘
                                        ▼
┌──────────────────────────────── Flutter / Dart ─────────────────────────────────┐
│ AuraAIInference ← AuraAIBrain / AuraTools ← AgentController / AuraIntentParser   │
│        │                         │                                                │
│        ├─ Isolate.run           ├─ valida RSA-2048 y SHA-256 del modelo remoto   │
│        └─ bosque JSON local     └─ cifra e instala tras validar                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

Flujo de análisis: tras autenticar la consola, `AuraNetworkAuditor` escucha el EventChannel nativo. Los eventos `BLOCKED`, `DGA_ALERT` y `SNI_OBSERVED` pueden iniciar `DNS/SNI → motor C → JNI/EventChannel → Dart → AuraAIBrain → AuraAIInference en isolate → bosque serializado`; si el modelo confirma una amenaza, Aura solicita una regla DNS y registra si el motor la confirmó. La allowlist se consulta antes del bosque. El clasificador da votos binarios por mayoría; esos votos no son probabilidades calibradas.

| Componente | Responsabilidad observada |
|---|---|
| `MainActivity` | Expone el control de defensa VPN, solicita el consentimiento del sistema y comunica el resultado del servicio a Flutter. |
| `AuraVpnService` | Mantiene la interfaz VPN foreground y coordina el túnel mientras está activo. |
| `hev-socks5-tunnel` | Procesa tráfico encaminado por TUN; incluye la ruta DNS mapeada y código C/JNI. |
| Firewall C / SNI | Reglas nativas de red y reporte de hosts/eventos al lado Flutter. |
| `AuraNetworkAuditor` | Escucha eventos DNS tras autenticar la consola, mantiene una bitácora acotada y solicita inferencia para eventos bloqueados o DGA. |
| `AuraAIInference` | Extrae hosts, calcula las 18 características y evalúa el bosque en `Isolate.run`. |
| `AuraAIBrain` | Carga/valida el modelo local y coordina inferencia, cachés y reglas seguras. |
| `AgentController` | Coordina órdenes, eventos y herramientas disponibles para la consola. |
| `AuraTools` | Acciones como actualizar defensas, bloquear un dominio o solicitar aislamiento nativo. |

### Estado de los cinco pilares de defensa

| Pilar | Capacidades integradas | Alcance y limitaciones |
|---|---|---|
| 1. Entorno hostil | Detecciones nativas de root, gestores como Magisk/KernelSU, instrumentación, emuladores y señales de integridad. | Son heurísticas de defensa en dispositivo; no constituyen garantía contra evasión o manipulación del sistema. |
| 2. Inventario de apps | `AuraAppGenomeScanner` evalúa aplicaciones instaladas, permisos sensibles, firmas y señales de ofuscación. | La visibilidad de paquetes depende de las políticas de visibilidad de Android y permisos disponibles. |
| 3. Clasificación ML | Vector sincronizado Python/Dart de 18 características: seis valores históricos sin reescalar y doce características nuevas normalizadas, incluyendo typosquatting, n-gramas, estructura e indicadores IDN. | El modelo publicado (`3.0.0`) conserva el esquema entrenado de seis características. El reentrenamiento `3.1.0` con threshold calibrado y evaluación adversarial está pendiente; no se atribuyen cifras nuevas. |
| 4. Red | Rutas TUN IPv4/IPv6; inspección TCP SNI; descarte en el camino TUN de TCP/853 (DoT), UDP/853 (DoQ) y UDP/443 hacia una lista fija de resolutores DoH conocidos; eventos de auditoría antes del descarte. | DoH sobre TCP/443 no se identifica de forma general; UDP/443 solo cubre direcciones incluidas en la lista. No se inspecciona el contenido TLS, no se descifra ECH y las conexiones directas por IP no quedan resueltas por SNI. Fragmentación, extensiones IPv6, cambios de red y fugas requieren pruebas adicionales en dispositivos físicos. |
| 5. Cadena de suministro | Workflow de SBOM CycloneDX y generación de provenance SLSA firmada mediante OIDC para artefactos Android. | El generador genérico de provenance no demuestra por sí solo todos los requisitos de construcción y fuente necesarios para afirmar conformidad SLSA Level 3 integral. |

### Contrato de características

El vector mejorado contiene 18 valores. Los primeros seis conservan sin reescalar el orden, valores y significado originales; las doce características añadidas están normalizadas a `[0, 1]`. Los modelos 3.x siguen usando sus seis valores históricos. Python (`extract_enhanced_features`) y Dart (`AuraAIInference.extractEnhancedFeatures`) comparten el orden siguiente:

| Índice | Campo JSON | Cálculo |
|---:|---|---|
| 0 | `length` | Longitud original del host, sin reescalar. |
| 1 | `shannon_entropy` | Entropía de Shannon original del host, sin reescalar. |
| 2 | `digit_ratio` | Dígitos ASCII divididos por la longitud. |
| 3 | `vowel_ratio` | Vocales ASCII (`a,e,i,o,u`) divididas por letras. |
| 4 | `consonant_sequence_ratio` | Caracteres de rachas consonánticas de longitud ≥3, divididos por letras. |
| 5 | `suspicious_tld` | `1.0` si el TLD pertenece al conjunto sospechoso del entrenador; si no, `0.0`. |
| 6 | `min_normalized_levenshtein` | Menor distancia de Levenshtein frente al snapshot Majestic Million Top 5.000 incluido, dividida por la longitud del host y limitada a `[0, 1]`. |
| 7 | `bigram_repeat_ratio` | N-gramas de dos caracteres repetidos, más allá de su primera aparición, divididos por el total de bigramas. |
| 8 | `trigram_repeat_ratio` | N-gramas de tres caracteres repetidos, más allá de su primera aparición, divididos por el total de trigramas. |
| 9 | `subdomain_depth` | Cantidad de puntos del host dividida por 126. |
| 10 | `tld_length_ratio` | Longitud del TLD dividida por 63. |
| 11 | `idn_homograph_indicator` | Número de caracteres cirílicos confusables (`а`, `е`, `о`, `р`, `с`, `у`, `х`) dividido por 2 y limitado a 1. |
| 12 | `non_ascii_ratio` | Caracteres no ASCII divididos por la longitud del host. |
| 13 | `consecutive_digits_indicator` | Indicador binario de dos o más dígitos contiguos. |
| 14 | `conditional_entropy` | Entropía media de las etiquetas, ponderada por caracteres, dividida por `log2(36)` y limitada a 1. |
| 15 | `rare_character_ratio` | `q`, `x`, `z` y `k` divididos por el total de letras ASCII. |
| 16 | `longest_label_length_ratio` | Longitud de la etiqueta más larga dividida por 63. |
| 17 | `suspicious_keyword_indicator` | Indicador binario de `free`, `reward`, `update`, `system`, `unlock`, `premium` o `crack` en el host. |

La función `detect_idn_homoglyphs` en Python y `AuraAIInference.detectIdnHomoglyphs` en Dart usan el mismo mapa de siete confusables cirílicos. El valor es un indicador limitado a 1 (`confusables / 2`); las etiquetas Punycode ASCII no se decodifican en esta característica.

Para typosquatting, `levenshtein_distance_to_top_domains` en Python y `AuraAIInference.levenshteinDistanceToTopDomains` en Dart retornan la mínima distancia de edición dividida por la longitud del host y limitada a 1 (`0.0` idéntico). Ambos usan exactamente el snapshot de 5.000 dominios citado arriba. `is_probable_typosquatting` / `AuraAIInference.isProbableTyposquatting` aplica el umbral de 1–2 ediciones; dominios idénticos no se clasifican como typosquatting. Ejemplo: `goggle.com` obtiene `0.1` frente a `google.com` y activa el umbral.

Majestic Million (CC BY 3.0) Top 5.000, descargado el 18/10/2026 desde `https://downloads.majestic.com/majestic_million.csv`, normalizado en `tool/domain_lists/majestic_top_5000_20261018.txt` e incorporado a Dart desde `lib/inference/aura_common_domains.dart`. Los modelos identifican su orden mediante `feature_order`: las inferencias mantienen el vector legado para el modelo publicado y seleccionan el nuevo vector solo para un modelo entrenado con las 18 características.

### Declaración QUERY_ALL_PACKAGES para Google Play

Justificación para el formulario de Google Play: “Aura Mobile Defens necesita consultar el inventario de aplicaciones instaladas para ejecutar un escáner de seguridad on-device que identifica permisos sensibles, servicios activos, firmas y señales de ofuscación. El inventario se procesa localmente, no sale del teléfono ni se utiliza para publicidad o analítica.”

La visibilidad de paquetes está sujeta a Android y puede ser limitada incluso con la declaración. Aura avisa cuando ve menos de cinco aplicaciones en Android 11/API 30 o posterior; ese resultado no se presenta como inventario completo.

### Endurecimiento aplicado (red-team)

| # | Vector | Corrección / estado |
|---:|---|---|
| 1 | Órdenes `toggle_defenses` y ayuda en consola | **Cerrado en iteración anterior:** comandos de activación y ayuda en español. |
| 2 | Estado visible de defensa | **Cerrado en iteración anterior:** píldora `DEFENSA: ON/OFF`. |
| 3 | Estado operativo | **Cerrado en iteración anterior:** barra de estado y chips rápidos. |
| 4 | Privacidad de sesión e interfaz | **Cerrado en iteración anterior:** telemetría LOCAL, sin radar, sin cierre automático de consola y `feature_order`. |
| 5 | QUIC/HTTP3 y UDP | **Pendiente:** el transporte actual no ofrece un filtro aplicado por puerto antes del reenvío; el contador no equivale a un descarte confirmado. |
| 6 | DoH por SNI | **Parcial:** endpoints conocidos añadidos al bloqueo SNI; DoT/TCP 853 y el conteo integral aún requieren una regla de transporte verificable. |
| 7 | Umbral ML y rollback | El runtime lee y aplica el umbral del JSON (fallback `0.50`); el rollback semver inferior a `3.0.0` se rechaza. La calibración 3.1.0 está pendiente de evaluación y firma. |
| 8 | Visibilidad de paquetes | Aviso ante inventarios con menos de cinco apps en Android 11/API 30+. |
| 9 | Revocación VPN | Broadcast crítico, evento en consola y notificación persistente al revocarse. |
| 10 | Órdenes/historial no acotados | Historial limitado a 400; la consola recorta órdenes a 240 caracteres y avisa. |
| 11 | ECH | El parser devuelve `AURA_TLS_SNI_ECH` y escribe una marca que llega por el callback SNI existente; Kotlin la convierte en señal visible. La política configurable de bloqueo sigue pendiente. |
| 12 | IP directa y accesibilidad | El adaptador Kotlin puede mapear una llamada con SNI vacío y destino IP a una señal, pero esa ruta no está demostrada en el callback protegido; aviso de accesibilidad implementado. Política IP y prueba nativa pendientes. |

El entrenamiento v3.1.0 usa un set adversarial determinista con semilla 42, pero no se publican métricas ni se sustituye el modelo 3.0.0 hasta completar y verificar el run real, la firma y `verifyModelIntegrity()`.

## Blocklists de dominios

En Android, `AuraBlocklistService` consulta URLhaus, PhishTank y OpenPhish antes de ejecutar el bosque. Las actualizaciones se programan con WorkManager a intervalos de 24 horas y se validan contra un manifiesto HTTPS del backend Aura con este esquema:

```json
{
  "feeds": {
    "urlhaus": { "sha256": "<sha256 del feed>" },
    "phishtank": { "sha256": "<sha256 del feed>" },
    "openphish": { "sha256": "<sha256 del feed>" }
  }
}
```

El build Android requiere `AURA_BLOCKLIST_MANIFEST_URL` (URL HTTPS del manifiesto) y `PHISHTANK_APP_KEY` como variables de entorno de Gradle. No se programan actualizaciones hasta configurar ambos valores. La app key compilada en `BuildConfig` puede extraerse del APK; en producción, se recomienda que el backend Aura consulte PhishTank y no distribuya una credencial reutilizable en el cliente.

Las generaciones verificadas se guardan bajo `files/blocklists/` en el sandbox privado de la app y se activan mediante un puntero atómico. Si falla una descarga o no coincide un hash, se conserva la generación cacheada anterior; sin ninguna generación verificada, la consulta se reporta como error y Aura no continúa al ML. El SHA-256 comprueba igualdad con los digests publicados por el backend; la autenticidad del manifiesto se basa en HTTPS y la confianza del servidor, no en una firma asimétrica del manifiesto.

## Telemetría opcional de clasificación

Cuando no hay endpoint, la consola usa telemetría local: registra auditorías de red, dominios bloqueados y marcas de tiempo en `SharedPreferences` del dispositivo y los muestra en el panel **TELEMETRÍA LOCAL**. El switch permanece disponible como **TELEMETRÍA: LOCAL** y los eventos no salen del teléfono. En Android, cuando hay un endpoint HTTPS configurado, el switch ofrece **TELEMETRÍA: REMOTA**; el envío requiere consentimiento explícito. El usuario puede retirar ese consentimiento desde el mismo lugar. Al desactivarlo, Aura cancela el trabajo de envío activo o programado y borra la cola remota pendiente.

Para habilitar el switch, configura un endpoint HTTPS real durante el build. También puedes especificar la versión efectiva del modelo; el valor predeterminado es `3.0.0`.

```sh
AURA_TELEMETRY_ENDPOINT="https://telemetry.example.org/v1/events" \
AURA_MODEL_VERSION="4.0.0" \
flutter build apk
```

No se incluye una URL de producción en el código. Si el endpoint falta o no es HTTPS, solo se usa el registro local; no se transmite telemetría. El endpoint remoto debe aceptar `POST` HTTPS y responder con un estado HTTP exitoso; se rechazan redirecciones. El cuerpo tiene esta forma:

```json
{
  "events": [
    {
      "hash": "<sha256 del dominio normalizado>",
      "outcome": "blocked",
      "source": "ml",
      "model_version": "4.0.0",
      "app_version": "1.0.0",
      "ts": 1791835200000
    }
  ]
}
```

`outcome` es `blocked` o `allowed`; `source` es `ml`, `blocklist` o `allowlist`. `ts` es la hora Unix en milisegundos. El hash se calcula en Android antes de persistir el evento; el dominio en claro no se añade a la cola ni al payload. La cola local usa `SharedPreferences`; se programan lotes de hasta 50 eventos cada cinco minutos o cuando se alcanza ese tamaño. El servicio encola como máximo un evento por segundo. Si una petición falla, WorkManager reintenta con backoff exponencial y mantiene los eventos mientras el opt-in siga activo.

**Consideraciones de privacidad y métricas:** el payload no contiene dominio en claro, IP, ID de dispositivo ni ubicación, pero una conexión HTTPS necesariamente expone la IP al servidor y a intermediarios de red. El operador del endpoint debe minimizar o desactivar los logs de IP y evitar añadir identificadores en sus propios sistemas. SHA-256 no es anonimización irreversible: los dominios comunes pueden recuperarse mediante diccionarios. `outcome` registra la clasificación prevista, no confirma que se haya aplicado correctamente una regla DNS ni constituye una etiqueta de verdad de referencia. Por sí sola, esta telemetría no calcula Recall; medirlo requiere comparar predicciones con etiquetas verificadas y diseñar esa correlación preservando la privacidad.

## 2. Incisiones integradas

### Inspección de DoH/DoQ e IPv6

`AuraVpnService` instala rutas predeterminadas para IPv4 (`0.0.0.0/0`) e IPv6 (`::/0`), así que TCP y UDP atraviesan la interfaz TUN; `VpnService.Builder` no ofrece `addAllowedProtocol()`. Se instalan reglas SNI para los nombres conocidos de resolutores cifrados y la lista nativa los clasifica como bloqueables. La implementación actual no demuestra un filtro por puerto UDP, ni una regla completa de denegación para TCP/853: no se afirma que QUIC/HTTP3 o DoT queden bloqueados. El contador QUIC solo refleja eventos de descarte recibidos; no hay hoy una ruta que genere ese evento al reenviar UDP sin filtrar.

El parser C detecta la extensión TLS `encrypted_client_hello`, devuelve `AURA_TLS_SNI_ECH` y escribe una marca que el camino observado del callback SNI propaga; Kotlin la convierte en `SNI_ENCRYPTED`. No descifra ECH y no hay una política configurable de bloqueo. La señal de conexión IP directa está preparada en el adaptador de eventos cuando recibe un SNI vacío con destino literal, pero el callback nativo descarta nombres vacíos; esa ruta no genera hoy la señal. No se afirma que la señal IP directa ni una política configurable sean efectivas en el túnel. Las direcciones IP se normalizan en Dart para el registro, pero no se puntúan como nombres de dominio en el modelo ML.

El transporte HEV procesa ambos tipos de paquete IP, prefiere resolver destinos mediante `AF_INET6` y recurre a `AF_INET` si no hay resultado IPv6. El feed de bloqueo y el filtro nativo admiten direcciones IPv4 e IPv6. El firewall es userspace sobre paquetes TUN; no invoca `iptables`/`ip6tables`, que requieren privilegios de sistema y no forman parte de un `VpnService` ordinario. SNI observado desde destinos IPv6 conserva la dirección IPv6 numérica en el evento. Las direcciones IP se normalizan en Dart para el registro, pero no se puntúan como nombres de dominio en el modelo ML.

La numeración de incisiones no está representada por tags Git. La tabla relaciona las etiquetas solicitadas con grupos de commits y merges que sí aparecen en el historial de `main`; para #4/#4b, la asignación se basa en la secuencia de commits, no en refs Git llamadas así.

| Incisión | Objetivo y archivos principales | Commits verificables | Estado |
|---|---|---|---|
| #1 | Integridad del firmado Android: `android/app/build.gradle`, `tool/compile_aura.sh`, `.github/workflows/release-signing-integrity.yml`, `codemagic.yaml`, README. | `0b329180c6ac3d75ea5826bb2e132f38537fd20c` (credenciales), `0a7c74a37cb1dab6f47004b982e65682e423de95` (guard end-to-end), merge `1a6a5749adbbccc88342558285c685baa24c7e59`. | Mergeada en `main` (`5b33743`). |
| #2 | Pipeline reproducible de datos/modelo: `tool/dataset/*`, `tool/train_max_aura_brain.py`, benchmark, tests, dependencias, `.github/workflows/model-training.yml`, `.gitignore`, README. | `67df3b39b177ef0a8c7a3a4408679ea2d0404784`, merge `83f102359978f13fb30742550a3c2876fafb94de`. | Mergeada en `main` (`5b33743`). |
| #4 | Robustez Codemagic y formatos de artefacto: `codemagic.yaml`, `tool/compile_aura.sh`, README. | `da8c138d3dbea6b3431a2a12acb7d25239928b8c`, merge `b9ab2d33384329acd8999b913c2b4d648bdeb2c4`. | Mergeada en `main` (`5b33743`). |
| #4b | Compatibilidad Base64 macOS/BSD de Codemagic: `tool/compile_aura.sh`. | `70780d03493ecfa481b9f406130cd35be63653ad`. | Mergeada en `main` (`5b33743`). |
| #5 | Brain v2, preset móvil firmado y benchmark: trainer, benchmark, tests, asset/sidecar/firma y README. | `23613194b33d963bdbcad669f6e82f1b063a0635`, `bb1b99b316291f9d25f74a55d7819cf31bced9e6`, merge `a82ff9f22c708b69033b375436529f92be6f6425`. | Mergeada en `main`. |

Merges posteriores también están en `main`: arreglo de `hashFiles()` inválido, `532b4be2e4351e8bebb12acb26abb9bcd95e72da`; URL del modelo y clave pública, `60d1f501cf905ff9965599c51c8faddf22632208`; merge final, `ba9ccacf5770e75a327298b3730fc9b0796398cb`. Historial: `git log --oneline --all --graph`.

## 3. Brain v2

Asset publicado: [`assets/model/aura_brain_model.json`](assets/model/aura_brain_model.json). Esquema actual: `random_forest`, clases `safe`/`threat` y seis características originales. El nuevo vector de 18 campos está listo para el próximo entrenamiento; el asset publicado no se regenera sin los splits de entrenamiento versionados.

El entrenador genera candidatos `4.0.0` con `feature_order` y `metadata` (`version`, `feature_count`, `feature_names`, `trained_at`) para las 18 características. El preset móvil cuantiza los umbrales a cuatro decimales y solo selecciona modelos de menos de 4 MiB; además, exige al menos 500 filas por clase en cada split, incluido test. El asset publicado seguirá en `3.0.0` hasta que se ejecute el entrenamiento con los splits disponibles y se publique el candidato firmado.

Consulta la [Model Card en español](docs/model_card.md) o su [copia pública en GitHub Pages](https://yojamm16-boop.github.io/Aura-V1.0/model-card.md) para el uso previsto, evaluación, datos y limitaciones.

Para cada veredicto ML no incluido en la allowlist, la consola conserva una explicación en memoria con las señales calculadas, la versión y el SHA-256. La tarjeta distingue entre dominio bloqueado y considerado seguro. En el modelo publicado `3.0.0`, la distancia de edición no pertenece al vector de seis características; si se muestra, la tarjeta la identifica explícitamente como señal auxiliar y no como causa del voto del bosque. La tarjeta no envía esos datos ni los reportes locales de falso positivo a la telemetría. El panel de auditoría resume eventos y resolutores observados durante la sesión, sin generar tráfico de prueba.

| Propiedad | Valor real |
|---|---:|
| Versión JSON | `3.0.0` |
| Tamaño | 3,004,068 bytes (≈2.86 MiB; ≈3 MB decimal) |
| Árboles | 500 |
| Profundidad máxima | 10 |
| `min_samples_leaf` | 2048 |
| Muestras de entrenamiento | 339,279 |
| Cuantización de umbrales | 4 decimales |
| SHA-256 del JSON | `d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2` |

Métricas del preset móvil sobre test holdout; precision, recall, F1 y FPR son para `threat`. La matriz usa filas reales y columnas predichas `[safe, threat]`.

| Accuracy | Precision | Recall | F1 | FPR |
|---:|---:|---:|---:|---:|
| 0.786501 | 0.964630 | 0.758888 | 0.849479 | 0.107160 |

Matriz de confusión: `[[13381, 1606], [13916, 43800]]`.

### Rendimiento en dispositivo

Pendiente de medición en un dispositivo Android real; no se publican cifras de dispositivo hasta ejecutar el benchmark allí.

| Modo | Muestras | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| Inferencia local (test de referencia) | 1,000 | Pendiente de medición en dispositivo real | Pendiente de medición en dispositivo real | Pendiente de medición en dispositivo real |

Conecta un dispositivo Android y ejecuta `flutter test --run-skipped --device-id <ID> test/aura_inference_benchmark_test.dart --reporter expanded`. El test usa `integration_test`, está omitido por defecto en CI y vuelca los percentiles en la salida; anota los resultados del dispositivo junto con su modelo y versión de Android.

### Benchmark de runner

Runner Linux `x86_64`, kernel `6.8.0-1064-azure`, glibc 2.39, 2 CPUs lógicas. No representa rendimiento en teléfono.

| Modo | Muestras | p50 | p95 | p99 | Throughput |
|---|---:|---:|---:|---:|---:|
| Warm, modelo residente | 10,000 | 1.980 ms | 4.085 ms | 7.300 ms | 434.22 dominios/s |
| Cold, incluye recarga JSON | 500 | 56.011 ms | 97.569 ms | 136.403 ms | 16.08 dominios/s |

La orden `actualizar` descarga el JSON, el sidecar `.sha256` y la firma `.sig` desde <https://yojamm16-boop.github.io/Aura-V1.0/model/>. La firma se verificó localmente con RSA-2048, PKCS#1 v1.5 y SHA-256. El cliente valida firma y digest antes de cifrar/instalar; un fallo activa reglas conservadoras sin bloqueo automático.

## Configuración de Codemagic para Producción

### Variables del grupo `production_keys`

Configura estas variables en Codemagic → Environment groups → `production_keys`:

| Variable | Tipo | Descripción |
|---|---|---|
| `AURA_PUBLIC_KEY_ENV` | Secure | Clave pública RSA Base64 DER (ver abajo) |
| `AURA_KEYSTORE_FILE` | File | Archivo `.jks` de tu keystore de producción |
| `AURA_STORE_PASSWORD` | Secure | Contraseña del keystore |
| `AURA_KEY_ALIAS` | Secure | Alias de la clave (ej: `aura-release`) |
| `AURA_KEY_PASSWORD` | Secure | Contraseña de la clave |
| `AURA_BUILD_FORMAT` | Secure | `apk` (predeterminado) o `aab` |

### Clave pública RSA Base64 DER

Copia este valor exacto para `AURA_PUBLIC_KEY_ENV` en una sola línea, sin comillas, espacios ni saltos de línea:

```text
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuG7nFF0UbTjT6Y8Ju0p31nVPiqx3aq6yg7+g/JtRJ+Y9WDAY504WdCnACplCVwju/5tnJhkvD3kWbsmfX45t9ZqMyCBo4stXbvRdbpe2WwMmxR/9ZHGGQQ1vjKyE4klsQ03aC836GW8l5y1IV/jknU4C03GRRMjfhkwTKpMjqq3kZAgQ62Yo2Prw0fB2c7b/2RjN5yiUZLtjh8FEQBhe8aW+4lrxEVkRJZxPrkbYdQoqBQKm2hQq1AUHurXx+HwHqDplb6mTcNttbnFtrkS0IDqXrhDSAHjaMLY8k6zyCutL7kTPBrAb44KaYvTRhMRBeUyOXHIb9YfxgAA0cCNs5wIDAQAB
```

La clave pública no es secreta y debe corresponder a la clave privada que firma el modelo. Protege como secretos `AURA_STORE_PASSWORD`, `AURA_KEY_PASSWORD` y cualquier keystore privado. En el `codemagic.yaml` actual, `AURA_BUILD_FORMAT` tiene un valor de entorno predeterminado `apk`; configura el override de formato según la política del proyecto.

## 4. Pipeline de datos

- Amenazas: [Phishing.Database](https://github.com/mitchellkrogza/Phishing.Database), MIT.
- Dominios seguros: [Majestic Million](https://majestic.com/reports/majestic-million), CC BY 3.0; [licencia](https://creativecommons.org/licenses/by/3.0/).
- Manifiesto: 484,685 dominios, 384,775 `threat` y 99,910 `safe`.
- Splits deterministas (semilla 42): train 339,279; val 72,703; test 72,703.
- Normalización: minúsculas, punto final eliminado, A-label IDNA2003; rechaza IPs y hosts inválidos, deduplica y excluye conflictos.
- La allowlist estática excluye coincidencias de threat. El manifiesto registra URLs/licencias, hashes de entradas crudas, conteos y timestamp.
- Majestic es el baseline seguro obligatorio. URLhaus requiere opt-in/licencia; Tranco está deshabilitado.
- Constructor: `tool/dataset/build_dataset.py`; splits y crudos son artefactos regenerables ignorados por Git.

Reproducción: `python -m pip install -r tool/requirements-train.txt`, `python tool/dataset/build_dataset.py --sources phishing_database`, `python tool/train_max_aura_brain.py`, `python tool/train_max_aura_brain.py --preset mobile`, `python tool/bench_aura_brain.py`, `python -m pytest tool/test_aura_brain.py -q`. CI no firma candidatos automáticamente.

## 5. Firma y seguridad Android

La configuración Android usa `compileSdk 36`, `targetSdk 36` y NDK `28.2.13676358`, alineado con Flutter stable y los plugins Android actuales.

### Permisos y justificación

- `RECORD_AUDIO`: el reconocimiento de voz se inicia desde la consola; Android solicita este permiso al invocar `startListening` y abre `RecognizerIntent.ACTION_RECOGNIZE_SPEECH` en español. Aura recibe el primer texto reconocido. El código del repositorio no confirma cómo procesa el audio el proveedor de reconocimiento instalado, por lo que no se afirma que el audio permanezca en el dispositivo ni que no se envíe a servidores. `lib/voice_engine.dart` reproduce respuestas con TTS; no captura audio.
- `QUERY_ALL_PACKAGES`: permite que `AuraAppGenomeScanner` consulte aplicaciones instaladas y analice permisos, servicios, firmas y señales de ofuscación para el pilar 2 (inventario de apps). Es un permiso restringido por Google Play: para publicar allí se requiere declararlo y justificar su necesidad. Una alternativa futura es migrar a `<queries>` con paquetes específicos, si el alcance funcional lo permite.
- `FOREGROUND_SERVICE` y `FOREGROUND_SERVICE_SPECIAL_USE`: se declaran para el `VpnService` y para el servicio de notificaciones persistentes asociados al escudo VPN autorizado por la persona usuaria.

La aplicación no requiere root.

### Mecanismo de Fallback Controlado (Desarrollo/CI)
Para garantizar la continuidad del pipeline de CI/CD sin exponer secretos en repositorios públicos, el sistema implementa un **fallback controlado**: si las variables de entorno de producción (`AURA_KEYSTORE_PATH`, etc.) no están presentes, el build utiliza automáticamente `signingConfigs.debug`.

Cuando esto ocurre:
1. El artefacto se compila exitosamente para fines de prueba.
2. Se inyecta `BuildConfig.IS_DEBUG_FALLBACK = true`, permitiendo que la aplicación limite funcionalidades de alto riesgo en tiempo de ejecución.
3. Se registra una advertencia clara en los logs de compilación.
4. **En ramas `main` o `principal`, el fallback está prohibido** y el build falla explícitamente.

### Modo Producción (Recomendado para distribución)
Cuando las variables de producción están configuradas, Gradle firma con `signingConfigs.release`. `tool/compile_aura.sh` valida con `keytool`, registra el fingerprint SHA-256 y verifica que el sujeto no sea `Android Debug`. `AURA_ALLOWED_CERT_SHA256` se genera dinámicamente con el certificado activo.

## 6. GitHub Actions

| Workflow | Propósito | Triggers |
|---|---|---|
| `release-signing-integrity.yml` | Verifica firma de release y genera `sbom.json` CycloneDX con Syft para Dart (`pubspec.lock`), Android (lockfile Gradle) y Python (`tool/requirements*.txt`); publica el SBOM como artefacto `aura-cyclonedx-sbom`. | PR/push a `main` cuando cambian archivos Gradle, `pubspec.*`, requirements o el workflow; `workflow_dispatch`. |
| `android-release.yml` | Compila y verifica APK/AAB, genera provenance SLSA firmada por OIDC (`.intoto.jsonl`) y publica APK/AAB más provenance en Releases para tags `v*`; conserva un artefacto combinado. | Push a `main`/`principal`, tags `v*` o `workflow_dispatch`. |
| `model-training.yml` | Instala Python, construye dataset, entrena, benchmark, pytest y publica reportes de CI. | PR y push a `main` para cambios `tool/**`, `data/**` o workflow; `workflow_dispatch`. |
| `deploy-model-pages.yml` | Publica JSON, SHA-256, firma y Model Card en Pages. | Push a `main` al cambiar workflow, Model Card o los tres assets; `workflow_dispatch`. |

El job `slsa-provenance` usa el generador genérico SLSA v1.2.2: el builder aislado firma el digest SHA-256 del artefacto con identidad OIDC y publica la attestation `.intoto.jsonl`. Para tags `v*`, la provenance y el APK/AAB se adjuntan a GitHub Release; en `workflow_dispatch` se puede elegir APK/AAB y opcionalmente indicar un tag de Release ya existente. Este generador produce provenance de nivel SLSA 3, pero es provenance-only: por sí solo no certifica todos los requisitos de fuente y construcción de un sistema SLSA Level 3 completo.

## 7. Codemagic

`codemagic.yaml` define `android-build`, grupo protegido `production_keys`, Flutter stable y Java 17. Trigger push a `main` o `principal`; APK predeterminado. `AURA_BUILD_FORMAT` admite `apk`, `aab` o `appbundle`. Keystore mediante `AURA_KEYSTORE_PATH`, `AURA_KEYSTORE_BASE64` temporal o file variable `AURA_KEYSTORE_FILE`, que se resuelve a path vía `CM_ENV`.

Variables protegidas: `AURA_STORE_PASSWORD`, `AURA_KEY_ALIAS`, `AURA_KEY_PASSWORD` y una modalidad de keystore. `AURA_PUBLIC_KEY_ENV` contiene la clave pública DER Base64. El preflight falla antes del build si falta configuración.

En Codemagic, configura `AURA_PUBLIC_KEY_ENV` en el grupo `production_keys` con este valor completo, sin comillas, prefijo ni saltos de línea. La variable del grupo prevalece sobre el fallback local de `tool/compile_aura.sh`:

```text
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuG7nFF0UbTjT6Y8Ju0p31nVPiqx3aq6yg7+g/JtRJ+Y9WDAY504WdCnACplCVwju/5tnJhkvD3kWbsmfX45t9ZqMyCBo4stXbvRdbpe2WwMmxR/9ZHGGQQ1vjKyE4klsQ03aC836GW8l5y1IV/jknU4C03GRRMjfhkwTKpMjqq3kZAgQ62Yo2Prw0fB2c7b/2RjN5yiUZLtjh8FEQBhe8aW+4lrxEVkRJZxPrkbYdQoqBQKm2hQq1AUHurXx+HwHqDplb6mTcNttbnFtrkS0IDqXrhDSAHjaMLY8k6zyCutL7kTPBrAb44KaYvTRhMRBeUyOXHIb9YfxgAA0cCNs5wIDAQAB
```

## 8. Estructura del repositorio

```text
assets/model/          modelo JSON, SHA-256 y firma
lib/                   Flutter/Dart: agent, crypto, inference, providers, screens, services, theme
android/app/           Gradle, manifest, Kotlin/Java, JNI y C
  src/main/cpp/        aura_crypto_secure, aura_sni_firewall, hev-socks5-tunnel
tool/                  dataset, snapshot Majestic, entrenamiento, benchmark, firma, build y pruebas
  dataset/             fuentes licenciadas, parser y fixture offline
  domain_lists/        snapshot Majestic Million Top 5.000 versionado
  reports/             métricas locales ignoradas por Git
.github/workflows/     release-signing-integrity, model-training, deploy-model-pages
data/                  fuentes crudas, CSV, manifiesto y splits (NO versionado; regenerable con tool/dataset/build_dataset.py)
 test/                 pruebas Flutter/Dart
```

Archivos Dart versionados:

```text
lib/agent/agent_controller.dart
lib/agent/agent_event.dart
lib/agent/aura_crypto_layer.dart
lib/agent/aura_intent_parser.dart
lib/agent/aura_tools.dart
lib/agent/aura_whitelist.dart
lib/ai_brain.dart
lib/crypto/aura_crypto_layer.dart
lib/inference/aura_ai_inference.dart
lib/infrastructure/agent/aura_intent_parser.dart
lib/infrastructure/security/aura_dynamic_whitelist.dart
lib/main.dart
lib/models/aura_ai_brain.dart
lib/network_auditor.dart
lib/providers/aura_state_provider.dart
lib/screens/aura_core_screen.dart
lib/screens/splash_screen.dart
lib/secure_memory.dart
lib/secure_vault.dart
lib/security/shannon_entropy.dart
lib/security_engine.dart
lib/services/ai_brain.dart
lib/services/aura_core.dart
lib/theme/aura_tokens.dart
lib/voice_engine.dart
```

Fuentes nativos propios y artefactos versionados:

```text
android/app/src/main/AndroidManifest.xml
android/app/src/main/java/hev/htproxy/TProxyService.java
android/app/src/main/kotlin/com/aura/cyberdefense/AuraCryptoSecure.kt
android/app/src/main/kotlin/com/aura/cyberdefense/AuraNotificationService.kt
android/app/src/main/kotlin/com/ciberdefensa/aura/AuraAppGenomeScanner.kt
android/app/src/main/kotlin/com/ciberdefensa/aura/AuraBlocklistService.kt
android/app/src/main/kotlin/com/ciberdefensa/aura/AuraHostileEnvironment.kt
android/app/src/main/kotlin/com/ciberdefensa/aura/AuraNetworkStream.kt
android/app/src/main/kotlin/com/ciberdefensa/aura/AuraTelemetryService.kt
android/app/src/main/kotlin/com/ciberdefensa/aura/AuraUpdateWorker.kt
android/app/src/main/kotlin/com/ciberdefensa/aura/AuraVpnService.kt
android/app/src/main/kotlin/com/ciberdefensa/aura/MainActivity.kt
android/app/src/main/cpp/aura_crypto_secure.c
android/app/src/main/cpp/aura_sni_firewall.c
android/app/src/main/cpp/aura_sni_firewall.h
assets/images/aura_emblem.svg
assets/model/aura_brain_model.json
assets/model/aura_brain_model.json.sha256
assets/model/aura_brain_model.json.sig
```

Conviven dos namespaces Kotlin por legado: `com.aura.cyberdefense` (`AuraCryptoSecure`, `AuraNotificationService`) y `com.ciberdefensa.aura` (resto). Su unificación está pendiente y requiere revisar referencias de manifest, JNI y MethodChannel.

Herramientas versionadas:

```text
tool/bench_aura_brain.py
tool/compile_aura.sh
tool/dataset/build_dataset.py
tool/dataset/fixtures/sample.csv
tool/dataset/sources.py
tool/install_flutter_env.sh
tool/requirements-train.txt
tool/setup_env_fix.sh
tool/sign_model.py
tool/test_aura_brain.py
tool/train_max_aura_brain.py
```

`hev-socks5-tunnel` es código C/JNI de terceros dentro de `android/app/src/main/cpp/hev-socks5-tunnel/`; se omite su inventario exhaustivo en este mapa. Componentes Dart centrales: `AuraTools`, `AgentController`, `AuraAIInference`, `AuraAIBrain`, `AuraCryptoLayer`, `AuraCoreScreen` y `AuraDynamicWhitelist`.

## 9. Build y validación

Para un build local se requiere Flutter stable, JDK 17, Android SDK Platform 36, Build Tools 36.0.0, NDK 28.2.13676358 y CMake 3.22.1. El build debug no necesita credenciales de release. Instala los componentes Android con `sdkmanager` y ejecuta:

```sh
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358" "cmake;3.22.1"
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

El build debug se verificó con las cuatro ABI configuradas (`armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64`). El proyecto usa AndroidX con Jetifier desactivado.

La compilación release del pipeline se ejecuta con `bash tool/compile_aura.sh`. Esta ruta compila el APK, verifica su firma y usa Gradle/R8 con un heap de 3 GB. El proyecto fija NDK `28.2.13676358` para mantenerlo alineado con Flutter stable y sus plugins Android. Las correcciones de compilación incluyen el límite de direcciones en el puente JNI y compatibilidad del scanner y del servicio de blocklist con Kotlin 2.2.

Validación local completada: `bash tool/compile_aura.sh`, `bash tool/compile_aura.sh --verify-artifact`, `flutter analyze` y `flutter test` (63 pruebas pasaron y una fue omitida). Codemagic recoge la APK de `build/app/outputs/flutter-apk/*.apk` y los AAB de `build/app/outputs/bundle/release/*.aab`. La firma de producción tiene prioridad cuando se configuran sus credenciales; sin ellas, el script permite fallback a firma Android Debug para pruebas, no para distribución.

- En CI (Codemagic y GitHub Actions), si faltan claves de producción, el build continúa con la clave Android Debug de la máquina (generada si no existe); el artefacto es **solo de prueba** y no debe distribuirse ni publicarse.
- Define `AURA_REQUIRE_RELEASE_SIGNING=true` para exigir claves de producción y abortar si faltan; este modo estricto es recomendable cuando se publica.
- Configura `AURA_KEYSTORE_PATH` o `AURA_KEYSTORE_BASE64`, junto con `AURA_STORE_PASSWORD`, `AURA_KEY_ALIAS` y `AURA_KEY_PASSWORD`, para que el script firme automáticamente con el keystore de producción.

Un build release directo de Gradle sin variables de firmado produce un artefacto sin firma, solo apto para diagnóstico local:

```sh
flutter build apk --release
```

Para producir y verificar una release distribuible, configura el keystore y las cuatro variables `AURA_KEYSTORE_PATH`, `AURA_STORE_PASSWORD`, `AURA_KEY_ALIAS` y `AURA_KEY_PASSWORD`, y usa el preflight:

```sh
bash tool/compile_aura.sh --check-signing
bash tool/compile_aura.sh
bash tool/compile_aura.sh --verify-artifact
```

AAB: `AURA_BUILD_FORMAT=aab bash tool/compile_aura.sh`. Comprueba `CERT_SHA256`, compara con el fingerprint de release esperado y verifica que el sujeto no sea `Android Debug`. Codemagic configura `production_keys`, inicia `android-build` y revisa el preflight/fingerprint. Pruebas del modelo: `python -m pytest tool/test_aura_brain.py -q`. Cobertura porcentual: no medida/publicada.

## 10. Licencias y atribución

- Código Aura: licencia propietaria en [`LICENSE`](LICENSE). Permite visualización/revisión/auditoría bajo sus términos; modificación y distribución requieren autorización escrita del titular.
- Phishing.Database: MIT; [repositorio y licencia](https://github.com/mitchellkrogza/Phishing.Database).
- Majestic Million: CC BY 3.0; atribución bajo [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/).
- URLhaus: opt-in y sujeto a [términos de abuse.ch](https://abuse.ch/terms-of-use/); confirma entitlement comercial antes de usarlo.
- Tranco está deshabilitado por condiciones mixtas de proveedores.

## 11. Roadmap

Estado de seguimiento (2026-10-30):

- Fase 1: experiencia conversacional y avatar local implementados; se añadieron etiquetas semánticas para estados disponible/analizando y respeto de la preferencia Android de reducir animaciones. Las nuevas pruebas widget deben confirmarse en Codemagic y el comportamiento debe validarse en dispositivos físicos.
- Fase 2: VPN local opcional, captura IPv4/IPv6, inspección SNI, reglas dinámicas y feed IP HTTPS acotado presentes en el código. La suite nativa de SNI amplía cobertura de allowlist, límites de dominio, ClientHello incompleto y extensiones malformadas; su ejecución CI debe confirmarse.
- Pendiente de red: filtrado real y validado de DoT/TCP 853; estrategia para DoH/DoQ; tratamiento explícito de QUIC/HTTP3; política ECH; señalización de conexiones IP directas; pruebas de fugas, reconexión y estabilidad en dispositivos.
- Incisión #6: Aura Agéntica (registro de herramientas, política central de permisos, planificación y verificación de acciones).
- Incisión #7: evolución visual del avatar; cualquier efecto 3D debe priorizar rendimiento, accesibilidad y consumo.
- Revisar permisos y manifiesto para Android 14+ y APIs 34/36; el build actual declara `compileSdk 36` y `targetSdk 36`.
- Entrenar y evaluar el modelo candidato de 18 características; el asset móvil publicado continúa en versión 3.0.0 hasta completar el proceso reproducible y la validación.
- Refactor de nombres de `AuraAIInference` y clases relacionadas manteniendo contratos y pruebas.
- Añadir cobertura reproducible y benchmarks en dispositivos Android reales.

## 12. Código crítico auditado

> Sincronizado con el estado de `main` a fecha de hoy. Si modificas estos archivos, regenera esta sección o sustitúyela por permalinks al commit.

### `android/app/build.gradle` (completo)
```groovy
import java.security.KeyStore
import java.security.MessageDigest

plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

def blocklistManifestUrl = System.getenv("AURA_BLOCKLIST_MANIFEST_URL") ?: ""
def phishTankAppKey = System.getenv("PHISHTANK_APP_KEY") ?: ""
def telemetryEndpoint = System.getenv("AURA_TELEMETRY_ENDPOINT") ?: ""
def modelVersion = System.getenv("AURA_MODEL_VERSION") ?: "3.0.0"
def buildConfigString = { value ->
    '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
}

android {
    namespace "com.ciberdefensa.aura"
    compileSdk 36

    // Keep the app, Flutter plugins, and Flutter stable SDK on the same NDK version.
    ndkVersion "28.2.13676358"

    buildFeatures {
        buildConfig true
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = '17'
    }

    defaultConfig {
        applicationId "com.ciberdefensa.aura"
        minSdk 24
        targetSdk 36
        versionCode 1
        versionName "1.0.0"
        buildConfigField(
            "String",
            "AURA_BLOCKLIST_MANIFEST_URL",
            buildConfigString(blocklistManifestUrl),
        )
        buildConfigField(
            "String",
            "PHISHTANK_APP_KEY",
            buildConfigString(phishTankAppKey),
        )
        buildConfigField(
            "String",
            "AURA_TELEMETRY_ENDPOINT",
            buildConfigString(telemetryEndpoint),
        )
        buildConfigField(
            "String",
            "AURA_MODEL_VERSION",
            buildConfigString(modelVersion),
        )

        ndk {
            abiFilters "armeabi-v7a", "arm64-v8a", "x86", "x86_64"
        }
    }

    signingConfigs {
        release {
            def keystorePath = System.getenv("AURA_KEYSTORE_PATH")
            storeFile = keystorePath ? project.file(keystorePath).absoluteFile : null
            storePassword = System.getenv("AURA_STORE_PASSWORD")
            keyAlias = System.getenv("AURA_KEY_ALIAS")
            keyPassword = System.getenv("AURA_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            // Verificar si tenemos todas las variables de producción
            def hasReleaseSigning = System.getenv("AURA_KEYSTORE_PATH") != null &&
                                    System.getenv("AURA_STORE_PASSWORD") != null &&
                                    System.getenv("AURA_KEY_ALIAS") != null &&
                                    System.getenv("AURA_KEY_PASSWORD") != null

            def keystoreFile = hasReleaseSigning ? project.file(System.getenv("AURA_KEYSTORE_PATH")).absoluteFile : null
            def isDebugFallback = !hasReleaseSigning || keystoreFile == null || !keystoreFile.isFile()

            // Aplicar la configuración de firma (fallback a debug si es necesario)
            signingConfig isDebugFallback ? signingConfigs.debug : signingConfigs.release

            // ✅ FASE 1: Inyectar bandera para que Dart sepa su postura de seguridad
            buildConfigField "boolean", "IS_DEBUG_FALLBACK", String.valueOf(isDebugFallback)

            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }

}

dependencies {
    implementation "androidx.biometric:biometric:1.1.0"
    implementation "androidx.work:work-runtime-ktx:2.10.1"
    implementation "androidx.core:core-ktx:1.16.0"
    implementation "com.squareup.okhttp3:okhttp:4.12.0"
}

def signingCertificateSha256 = { signingConfig ->
    def keystoreFile = signingConfig.storeFile
    def storePassword = signingConfig.storePassword
    def keyAlias = signingConfig.keyAlias
    if (keystoreFile == null || !keystoreFile.isFile() ||
        storePassword == null || storePassword.trim().isEmpty() ||
        keyAlias == null || keyAlias.trim().isEmpty()) {
        return null
    }

    def keyStore = null
    Exception lastLoadError = null
    [signingConfig.storeType, "JKS", "PKCS12"].findAll { it != null }.unique().each { type ->
        if (keyStore == null) {
            try {
                def candidate = KeyStore.getInstance(type)
                keystoreFile.withInputStream { stream ->
                    candidate.load(stream, storePassword.toCharArray())
                }
                keyStore = candidate
            } catch (Exception exception) {
                lastLoadError = exception
            }
        }
    }

    if (keyStore == null) {
        throw new GradleException("Could not read signing keystore '${keystoreFile}'.", lastLoadError)
    }

    def certificate = keyStore.getCertificate(keyAlias)
    if (certificate == null) {
        throw new GradleException("Alias '${keyAlias}' has no signing certificate in '${keystoreFile}'.")
    }

    MessageDigest.getInstance("SHA-256").digest(certificate.encoded)
        .collect { String.format("%02X", it & 0xff) }
        .join()
}

android.buildTypes.each { buildType ->
    def activeSigningConfig = buildType.signingConfig
    def activeCertificateSha256 = activeSigningConfig == null
        ? null
        : signingCertificateSha256(activeSigningConfig)
    buildType.buildConfigField(
        "String",
        "AURA_ALLOWED_CERT_SHA256",
        "\"${activeCertificateSha256 ?: ''}\"",
    )
}

tasks.register("printReleaseSigning") {
    group = "verification"
    description = "Prints the configured release signing identity without exposing credentials."
    doLast {
        def releaseSigningConfig = android.buildTypes.getByName("release").signingConfig
        println "STORE_FILE=${releaseSigningConfig?.storeFile?.absolutePath ?: ''}"
        println "KEY_ALIAS=${releaseSigningConfig?.keyAlias ?: ''}"
        println "IS_DEBUG_SIGNING=${releaseSigningConfig == android.signingConfigs.debug}"
    }
}

flutter {
    source '../..'
}

def hevSourceDir = file("src/main/cpp/hev-socks5-tunnel")
def hevBuildDir = layout.buildDirectory.dir("generated/hev-tun2socks")
def hevJniLibsDir = hevBuildDir.map { it.dir("jniLibs") }

android.sourceSets.main.jniLibs.srcDir(hevJniLibsDir)

tasks.register("buildHevSocks5Tunnel", Exec) {
    inputs.dir(hevSourceDir)
    inputs.files(
        file("src/main/cpp/aura_crypto_secure.c"),
        file("src/main/cpp/aura_sni_firewall.c"),
        file("src/main/cpp/aura_sni_firewall.h"),
    )
    outputs.dir(hevJniLibsDir)

    doFirst {
        hevBuildDir.get().asFile.mkdirs()
        hevJniLibsDir.get().asFile.mkdirs()
    }

    commandLine(
        file("${android.sdkDirectory}/ndk/${android.ndkVersion}/ndk-build").absolutePath,
        "NDK_PROJECT_PATH=null",
        "APP_BUILD_SCRIPT=${new File(hevSourceDir, 'Android.mk').absolutePath}",
        "NDK_APPLICATION_MK=${new File(hevSourceDir, 'Application.mk').absolutePath}",
        "NDK_OUT=${hevBuildDir.get().dir('obj').asFile.absolutePath}",
        "NDK_LIBS_OUT=${hevJniLibsDir.get().asFile.absolutePath}",
    )
}

tasks.named("preBuild").configure {
    dependsOn("buildHevSocks5Tunnel")
}
```

### `codemagic.yaml` (completo)
```yaml
workflows:
  android-build:
    name: Aura Android Release Pipeline
    max_build_duration: 60
    instance_type: mac_mini_m1
    environment:
      groups:
        - production_keys # Puedes dejarlo o quitarlo, ya no fallará si está vacío
      vars:
        # applicationId real definido en android/app/build.gradle: com.ciberdefensa.aura
        AURA_BUILD_FORMAT: "apk"
      flutter: stable
      java: 17
    triggering:
      events:
        - push
      branch_patterns:
        - pattern: 'main'
        - pattern: 'principal'
    scripts:
      - name: Resolve Codemagic keystore file variable (Optional)
        script: |
          set -euo pipefail
          if [[ -n "${AURA_KEYSTORE_FILE:-}" && -z "${AURA_KEYSTORE_PATH:-}" ]]; then
            if [[ -f "$AURA_KEYSTORE_FILE" && -n "${CM_ENV:-}" ]]; then
              printf 'AURA_KEYSTORE_PATH=%s\n' "$AURA_KEYSTORE_FILE" >> "$CM_ENV"
            else
              echo '[AURA-PREFLIGHT][WARNING] AURA_KEYSTORE_FILE missing. Falling back to debug signing.'
            fi
          fi
      - name: Build Android Release artifact
        script: |
          set -euo pipefail
          cd "${CM_BUILD_DIR:?CM_BUILD_DIR is required}"
          bash tool/compile_aura.sh
      - name: Verify Android Release artifact signer
        script: |
          set -euo pipefail
          cd "${CM_BUILD_DIR:?CM_BUILD_DIR is required}"
          bash tool/compile_aura.sh --verify-artifact
    artifacts:
      - build/app/outputs/flutter-apk/*.apk
      - build/app/outputs/bundle/release/*.aab
          fi
```

### `tool/compile_aura.sh` (completo)
```bash
#!/usr/bin/env bash
# Release builds default to APK; set AURA_BUILD_FORMAT=appbundle for an AAB.
set -euo pipefail

log() {
    printf '[AURA-BUILD] %s\n' "$*"
}

fail() {
    printf '[AURA-BUILD][ERROR] %s\n' "$*" >&2
    exit 1
}

# --- FASE 1: Detección de fallback y protección de rama principal ---
USE_DEBUG_SIGNING=false
if [[ -z "${AURA_KEYSTORE_PATH:-}" && -z "${AURA_KEYSTORE_BASE64:-}" ]]; then
    log "WARNING: Production signing variables missing. Falling back to DEBUG signing configuration."
    USE_DEBUG_SIGNING=true

    # Proteger la rama principal: el fallback solo es para desarrollo
    if [[ "${CM_BRANCH:-}" == "main" || "${CM_BRANCH:-}" == "principal" || "${GITHUB_REF:-}" == "refs/heads/main" ]]; then
        fail "CRITICAL: Production signing variables are strictly required for main/principal branches. Debug fallback is not allowed."
    fi
fi

mode="build"
case "${1:-}" in
    --check-signing)
        mode="check-signing"
        shift
        ;;
    --verify-artifact)
        mode="verify-artifact"
        shift
        ;;
    --help|-h)
        printf '%s\n' \
            'Usage: compile_aura.sh [--check-signing|--verify-artifact]' \
            '  --check-signing    Resolve and validate the keystore; print its SHA-256 certificate fingerprint.' \
            '  --verify-artifact  Verify the configured release artifact without rebuilding.'
        exit 0
        ;;
esac
[[ "$#" -eq 0 ]] || fail "Unsupported argument. Use --check-signing or --verify-artifact."

temporary_files=()
cleanup_temporary_files() {
    local temporary_file
    for temporary_file in "${temporary_files[@]}"; do
        rm -f -- "$temporary_file"
    done
}
trap cleanup_temporary_files EXIT

resolve_keystore() {
    if [[ -n "${AURA_KEYSTORE_PATH:-}" ]]; then
        if [[ -f "$AURA_KEYSTORE_PATH" && -r "$AURA_KEYSTORE_PATH" ]]; then
            export AURA_KEYSTORE_PATH
            return
        fi
        [[ -n "${AURA_KEYSTORE_BASE64:-}" ]] ||
            fail "AURA_KEYSTORE_PATH must reference an existing readable file, or set AURA_KEYSTORE_BASE64."
    fi
    [[ -n "${AURA_KEYSTORE_BASE64:-}" ]] ||
        fail "Missing release keystore: set AURA_KEYSTORE_PATH or AURA_KEYSTORE_BASE64."
    local keystore_file
    keystore_file="$(mktemp "${TMPDIR:-/tmp}/aura-release-keystore.XXXXXX")"
    temporary_files+=("$keystore_file")
    chmod 0600 "$keystore_file" 2>/dev/null ||
        fail "Could not secure the temporary Base64 keystore."
    if [[ "$(uname -s)" == "Darwin" ]]; then
        if ! printf '%s' "$AURA_KEYSTORE_BASE64" | base64 -D > "$keystore_file" 2>/dev/null; then
            fail "AURA_KEYSTORE_BASE64 is not valid Base64 keystore data."
        fi
    elif ! printf '%s' "$AURA_KEYSTORE_BASE64" | base64 --decode > "$keystore_file" 2>/dev/null; then
        fail "AURA_KEYSTORE_BASE64 is not valid Base64 keystore data."
    fi
    [[ -s "$keystore_file" ]] || fail "AURA_KEYSTORE_BASE64 decoded to an empty keystore."
    export AURA_KEYSTORE_PATH="$keystore_file"
}

validate_signing_credentials() {
    local missing_variables=()
    local variable
    for variable in AURA_STORE_PASSWORD AURA_KEY_ALIAS AURA_KEY_PASSWORD; do
        [[ -n "${!variable:-}" ]] || missing_variables+=("$variable")
    done
    ((${#missing_variables[@]} == 0)) ||
        fail "Missing release signing variable(s): ${missing_variables[*]}"
    command -v keytool >/dev/null 2>&1 || fail "keytool is required to validate release signing."
}

keytool_certificate_info() {
    local keytool_output
    if ! keytool_output="$(keytool -list -v \
        -keystore "$AURA_KEYSTORE_PATH" \
        -alias "$AURA_KEY_ALIAS" \
        -storepass:env AURA_STORE_PASSWORD \
        -keypass:env AURA_KEY_PASSWORD 2>/dev/null)"; then
        fail "keytool could not validate the release keystore; check AURA_KEYSTORE_PATH, AURA_STORE_PASSWORD, AURA_KEY_ALIAS and AURA_KEY_PASSWORD."
    fi

    local fingerprint
    fingerprint="$(printf '%s\n' "$keytool_output" | awk '
        /SHA-?256:/ { sub(/^.*SHA-?256:[[:space:]]*/, ""); print; exit }
        /SHA256:/ { sub(/^.*SHA256:[[:space:]]*/, ""); print; exit }
    ' | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')"
    [[ "$fingerprint" =~ ^[[:xdigit:]]{64}$ ]] ||
        fail "keytool did not return a valid SHA-256 certificate fingerprint."

    local subject
    subject="$(printf '%s\n' "$keytool_output" | awk -F': ' '/^[[:space:]]*Owner:/ {print $2; exit}')"
    if grep -Fqi 'Android Debug' <<< "$subject"; then
        fail "Release signing certificate is the public Android Debug certificate."
    fi
    printf '%s\n' "$fingerprint"
}

verify_release_signer() {
    local artifact="$1"
    local extension="${artifact##*.}"
    local certificate_output=""
    local certificate_subject=""
    local certificate_fingerprint=""
    local apksigner_binary="$(command -v apksigner || true)"
    local android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
    local candidate

    if [[ -z "$apksigner_binary" && -n "$android_sdk" ]]; then
        for candidate in "$android_sdk"/build-tools/*/apksigner; do
            [[ -x "$candidate" ]] && apksigner_binary="$candidate"
        done
    fi

    if [[ "$extension" == "apk" && -n "$apksigner_binary" ]]; then
        if ! certificate_output="$("$apksigner_binary" verify --print-certs "$artifact" 2>/dev/null)"; then
            fail "apksigner rejected the release APK."
        fi
        certificate_fingerprint="$(printf '%s\n' "$certificate_output" | awk -F': ' 'tolower($0) ~ /certificate sha-256 digest:/ {print $2; exit}' | tr -d ':[:space:]' | tr '[:lower:]' '[:upper:]')"
        certificate_subject="$(printf '%s\n' "$certificate_output" | awk -F': ' 'tolower($0) ~ /certificate dn:/ {print $2; exit}')"
        [[ "$certificate_fingerprint" =~ ^[[:xdigit:]]{64}$ ]] ||
            fail "apksigner did not return a valid SHA-256 certificate fingerprint."
        log "APK signer verification used apksigner."
    elif [[ "$USE_DEBUG_SIGNING" == "true" ]]; then
        log "WARNING: keytool signature validation skipped in DEBUG fallback mode."
        certificate_fingerprint="DEBUG_FALLBACK"
        certificate_subject="Android Debug (fallback)"
    else
        if [[ "$extension" == "apk" ]]; then
            log "apksigner unavailable; using keytool keystore-certificate fallback (does not inspect APK bytes)."
        else
            log "AAB signer verification uses the configured keytool certificate."
        fi
        certificate_fingerprint="$(keytool_certificate_info)"
        certificate_subject="$(keytool -list -v \
            -keystore "$AURA_KEYSTORE_PATH" \
            -alias "$AURA_KEY_ALIAS" \
            -storepass:env AURA_STORE_PASSWORD \
            -keypass:env AURA_KEY_PASSWORD 2>/dev/null |
            awk -F': ' '/^[[:space:]]*Owner:/ {print $2; exit}')"
    fi

    if grep -Fqi 'Android Debug' <<< "$certificate_subject"; then
        if [[ "$USE_DEBUG_SIGNING" == "true" ]]; then
            log "WARNING: Artifact is signed with Android Debug certificate (Fallback mode active)."
        else
            fail "Release artifact is signed with the public Android Debug certificate."
        fi
    fi
    printf 'CERT_SHA256=%s\n' "$certificate_fingerprint"
}

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
android_dir="$project_root/android"
local_properties="$android_dir/local.properties"

if [[ "$USE_DEBUG_SIGNING" == "false" ]]; then
    resolve_keystore
    validate_signing_credentials
    signing_fingerprint="$(keytool_certificate_info)"
else
    signing_fingerprint="DEBUG_FALLBACK"
fi
build_format="${AURA_BUILD_FORMAT:-apk}"
case "$build_format" in
    apk) ;;
    aab) build_format="appbundle" ;;
    appbundle) ;;
    *) fail "AURA_BUILD_FORMAT must be 'apk', 'aab' or 'appbundle'." ;;
esac
if [[ "$mode" == "check-signing" ]]; then
    printf 'CERT_SHA256=%s\n' "$signing_fingerprint"
    exit 0
fi

if [[ "$mode" == "verify-artifact" ]]; then
    if [[ "$build_format" == "apk" ]]; then
        release_artifact="$project_root/build/app/outputs/flutter-apk/app-release.apk"
    else
        release_artifact="$project_root/build/app/outputs/bundle/release/app-release.aab"
    fi
    [[ -f "$release_artifact" ]] || fail "Configured release artifact is missing."
    verify_release_signer "$release_artifact"
    exit 0
fi

property_value() {
    local key="$1"
    local file="$2"
    if [[ -f "$file" ]]; then
        awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); value = $0} END {print value}' "$file"
    fi
}

flutter_root="${FLUTTER_ROOT:-}"
if [[ -z "$flutter_root" || ! -x "$flutter_root/bin/flutter" ]]; then
    flutter_root="$(property_value flutter.sdk "$local_properties")"
fi
if [[ -z "$flutter_root" || ! -x "$flutter_root/bin/flutter" ]]; then
    flutter_binary="$(command -v flutter || true)"
    if [[ -n "$flutter_binary" ]]; then
        flutter_root="$(cd "$(dirname "$flutter_binary")/.." && pwd -P)"
    fi
fi
if [[ -z "$flutter_root" || ! -x "$flutter_root/bin/flutter" ]]; then
    for candidate in \
        "$HOME/development/flutter" \
        "$HOME/.flutter_sdk/flutter" \
        /opt/flutter \
        /usr/local/flutter
    do
        if [[ -x "$candidate/bin/flutter" ]]; then
            flutter_root="$candidate"
            break
        fi
    done
fi
[[ -n "$flutter_root" && -x "$flutter_root/bin/flutter" ]] ||
    fail "Flutter SDK not found. Set FLUTTER_ROOT to an installed stable Flutter SDK."
export FLUTTER_ROOT="$(cd "$flutter_root" && pwd -P)"
export PATH="$FLUTTER_ROOT/bin:$PATH"

if [[ -z "${AURA_PUBLIC_KEY_ENV:-}" ]]; then
    AURA_PUBLIC_KEY_ENV='MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuG7nFF0UbTjT6Y8Ju0p31nVPiqx3aq6yg7+g/JtRJ+Y9WDAY504WdCnACplCVwju/5tnJhkvD3kWbsmfX45t9ZqMyCBo4stXbvRdbpe2WwMmxR/9ZHGGQQ1vjKyE4klsQ03aC836GW8l5y1IV/jknU4C03GRRMjfhkwTKpMjqq3kZAgQ62Yo2Prw0fB2c7b/2RjN5yiUZLtjh8FEQBhe8aW+4lrxEVkRJZxPrkbYdQoqBQKm2hQq1AUHurXx+HwHqDplb6mTcNttbnFtrkS0IDqXrhDSAHjaMLY8k6zyCutL7kTPBrAb44KaYvTRhMRBeUyOXHIb9YfxgAA0cCNs5wIDAQAB'
    public_key_source="build-only fallback"
    log "WARNING: AURA_PUBLIC_KEY_ENV is empty; using the build-only fallback key."
else
    public_key_source="production"
fi
[[ "$AURA_PUBLIC_KEY_ENV" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] ||
    fail "AURA_PUBLIC_KEY_ENV must be the Base64 DER body without PEM delimiters or whitespace."

key_file="$(mktemp "${TMPDIR:-/tmp}/aura-public-key.XXXXXX")"
temporary_files+=("$key_file")
python3 - "$AURA_PUBLIC_KEY_ENV" "$key_file" <<'PY'
import base64
import sys

try:
    der = base64.b64decode(sys.argv[1], validate=True)
except (ValueError, base64.binascii.Error) as error:
    raise SystemExit(f"AURA_PUBLIC_KEY_ENV is not valid Base64: {error}")
if not der:
    raise SystemExit("AURA_PUBLIC_KEY_ENV decoded to an empty public key.")
with open(sys.argv[2], "wb") as key_file:
    key_file.write(der)
PY
openssl pkey -pubin -inform DER -in "$key_file" -noout
rm -f "$key_file"

log "Selecting JDK 17 and mapping the installed Android SDK/NDK."
source "$project_root/tool/setup_env_fix.sh"
trap cleanup_temporary_files EXIT
[[ -x "$JAVA_HOME/bin/java" ]] ||
    fail "The JDK 17 setup did not provide JAVA_HOME/bin/java."

java_version="$("$JAVA_HOME/bin/java" -version 2>&1 | awk -F '"' '/version/ {print $2; exit}')"
[[ "$java_version" == 17.* ]] ||
    fail "Expected Java 17 at JAVA_HOME, found '${java_version:-unknown}'."
export PATH="$JAVA_HOME/bin:$PATH"
export GRADLE_OPTS="${GRADLE_OPTS:+$GRADLE_OPTS }-Dorg.gradle.java.home=$JAVA_HOME"
log "Gradle Java: $("$JAVA_HOME/bin/java" -version 2>&1 | head -n 1)"

gradle_version_output="$(
    cd "$android_dir"
    ./gradlew --version
)"
gradle_java_major="$(
    printf '%s\n' "$gradle_version_output" |
        awk '/^(Launcher )?JVM:/ {version = $NF; sub(/\..*/, "", version); print version; exit}'
)"
[[ "$gradle_java_major" == "17" ]] ||
    fail "Gradle reports Java ${gradle_java_major:-unknown}; Java 17 is required."

properties_tmp="$(mktemp "$local_properties.XXXXXX")"
temporary_files+=("$properties_tmp")
if [[ -f "$local_properties" ]]; then
    awk -F= '$1 != "flutter.sdk" {print}' "$local_properties" > "$properties_tmp"
fi
printf 'flutter.sdk=%s\n' "$FLUTTER_ROOT" >> "$properties_tmp"
mv "$properties_tmp" "$local_properties"

if [[ -n "${CM_ENV:-}" ]]; then
    printf 'FLUTTER_ROOT=%s\n' "$FLUTTER_ROOT" >> "$CM_ENV"
fi

cd "$project_root"
if [[ "$build_format" == "apk" ]]; then
    if [[ "$USE_DEBUG_SIGNING" == "true" ]]; then
        log "Building the release APK with DEBUG signing (production keys missing)."
    else
        log "Building the release APK with the ${public_key_source} RSA public key."
    fi
    "$FLUTTER_ROOT/bin/flutter" build apk --release \
        --dart-define="AURA_PUBLIC_KEY=$AURA_PUBLIC_KEY_ENV"
    release_artifact="$project_root/build/app/outputs/flutter-apk/app-release.apk"
else
    if [[ "$USE_DEBUG_SIGNING" == "true" ]]; then
        log "Building the release app bundle with DEBUG signing (production keys missing)."
    else
        log "Building the release app bundle with the ${public_key_source} RSA public key."
    fi
    "$FLUTTER_ROOT/bin/flutter" build appbundle --release \
        --dart-define="AURA_PUBLIC_KEY=$AURA_PUBLIC_KEY_ENV"
    release_artifact="$project_root/build/app/outputs/bundle/release/app-release.aab"
fi
[[ -f "$release_artifact" ]] || fail "Release artifact was not created."
verify_release_signer "$release_artifact"
log "Release artifact signature verified."
```

### `.github/workflows/deploy-model-pages.yml` (completo)
```yaml
name: Deploy model to GitHub Pages

on:
  push:
    branches:
      - main
    paths:
      - '.github/workflows/deploy-model-pages.yml'
      - 'docs/model_card.md'
      - 'assets/model/aura_brain_model.json'
      - 'assets/model/aura_brain_model.json.sha256'
      - 'assets/model/aura_brain_model.json.sig'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: github-pages
  cancel-in-progress: true

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v5
      - name: Prepare model-only site
        run: |
          mkdir -p _site/model
          cp assets/model/aura_brain_model.json _site/model/
          cp assets/model/aura_brain_model.json.sha256 _site/model/
          cp assets/model/aura_brain_model.json.sig _site/model/
          cp docs/model_card.md _site/model-card.md
      - uses: actions/upload-pages-artifact@v3
        with:
          path: _site
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

### `tool/train_max_aura_brain.py` (extractor activo y legado)

El siguiente extracto literal contiene el extractor activo de 18 características y el extractor de compatibilidad para los modelos históricos de seis características.

```python
def extract_enhanced_features(domain):
    return extract_maximum_features(domain)


def extract_maximum_features(domain):
    host = normalize_domain(domain)
    length = len(host)
    if length == 0:
        return [0.0] * 18

    labels = host.split(".")
    tld = labels[-1]
    ascii_letters = [character for character in host if character.isascii() and character.isalpha()]
    digits = sum(character.isascii() and character.isdigit() for character in host)
    vowels = sum(character in "aeiou" for character in ascii_letters)
    consonant_sequence_characters = 0
    run_length = 0
    for character in host:
        if character.isascii() and character.isalpha() and character not in "aeiou":
            run_length += 1
        else:
            if run_length >= 3:
                consonant_sequence_characters += run_length
            run_length = 0
    if run_length >= 3:
        consonant_sequence_characters += run_length
    consecutive_digits = any(
        host[index].isascii()
        and host[index].isdigit()
        and host[index + 1].isascii()
        and host[index + 1].isdigit()
        for index in range(length - 1)
    )
    rare_characters = sum(character in _RARE_CHARACTERS for character in host)

    return [
        float(length),
        calculate_shannon_entropy(host),
        digits / length,
        vowels / len(ascii_letters) if ascii_letters else 0.0,
        (
            consonant_sequence_characters / len(ascii_letters)
            if ascii_letters
            else 0.0
        ),
        float(tld in SUSPICIOUS_TLDS),
        min(levenshtein_distance_to_top_domains(host), 1.0),
        calculate_bigram_repeat_ratio(host),
        calculate_trigram_repeat_ratio(host),
        min(host.count(".") / 126.0, 1.0),
        min(len(tld) / 63.0, 1.0),
        detect_idn_homoglyphs(host),
        sum(not character.isascii() for character in host) / length,
        float(consecutive_digits),
        calculate_conditional_entropy(host),
        rare_characters / len(ascii_letters) if ascii_letters else 0.0,
        min(max(map(len, labels), default=0) / 63.0, 1.0),
        float(any(keyword in host for keyword in SUSPICIOUS_KEYWORDS)),
    ]


def extract_legacy_features(domain):
    host = normalize_domain(domain)
    length = len(host)
    if not length:
        return [0.0] * len(LEGACY_FEATURE_ORDER)

    letters = [
        character
        for character in host
        if character.isascii() and character.isalpha()
    ]
    digits = sum(character.isascii() and character.isdigit() for character in host)
    vowels = sum(character in "aeiou" for character in letters)
    consonant_sequence_characters = 0
    run_length = 0
    for character in host:
        if character.isascii() and character.isalpha() and character not in "aeiou":
            run_length += 1
        else:
            if run_length >= 3:
                consonant_sequence_characters += run_length
            run_length = 0
    if run_length >= 3:
        consonant_sequence_characters += run_length
    tld = host.rsplit(".", 1)[-1]
    return [
        float(length),
        calculate_shannon_entropy(host),
        digits / length,
        vowels / len(letters) if letters else 0.0,
        consonant_sequence_characters / len(letters) if letters else 0.0,
        float(tld in SUSPICIOUS_TLDS),
    ]
```

El resto valida al menos 500 filas por clase en cada split. El modo `full` ajusta 500 árboles y escribe candidato/métricas en `tool/reports/`. `--preset mobile` conserva 500 árboles, busca poda/profundidad bajo 4 MiB, cuantiza umbrales a cuatro decimales y mide el JSON serializado contra test/val; no reemplaza automáticamente el asset.

### `tool/dataset/build_dataset.py` (normalización y preparación)
```python
#!/usr/bin/env python3
"""Download licensed domain sources and build deterministic Aura CSV splits."""

from __future__ import annotations

import argparse
import csv
import hashlib
import ipaddress
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

from sklearn.model_selection import train_test_split

from sources import DEFAULT_SAFE_SOURCE, SOURCES, SourceDefinition, iter_source_domains

ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = ROOT / "data"
RAW_DIR = DATA_DIR / "raw"
OUTPUT_CSV = DATA_DIR / "aura_dataset.csv"
SPLIT_DIR = DATA_DIR / "splits"
MANIFEST_PATH = DATA_DIR / "dataset_manifest.json"
SPLIT_SEED = 42
NORMALIZATION_VERSION = "aura-domain-idna2003-v1"
CSV_FIELDS = ["domain", "label", "source", "license", "retrieved_at"]
STATIC_ALLOWLIST = {
    "google.com", "apple.com", "microsoft.com", "amazonaws.com",
    "cloudflare.com", "akamaiedge.net", "android.com", "github.com",
    "whatsapp.net", "googleapis.com", "gstatic.com", "googleusercontent.com",
    "apple-dns.net", "icloud.com", "microsoftonline.com", "windows.net",
    "amazon.com", "awsstatic.com", "akamaized.net", "fastly.net",
}
HOST_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


class DatasetBuildError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def normalize_domain(value: str) -> str | None:
    candidate = value.strip()
    if not candidate or any(ord(char) < 0x20 for char in candidate):
        return None
    try:
        if "://" in candidate:
            parsed = urlsplit(candidate)
            if parsed.scheme.lower() not in {"http", "https"} or parsed.username or parsed.password:
                return None
            candidate = parsed.hostname or ""
        else:
            parsed = urlsplit("//" + candidate.lstrip("/"))
            if parsed.username or parsed.password:
                return None
            candidate = parsed.hostname or ""
    except ValueError:
        return None

    candidate = candidate.rstrip(".").lower()
    if not candidate:
        return None
    try:
        candidate = candidate.encode("idna").decode("ascii").lower()
        ipaddress.ip_address(candidate)
        return None
    except ValueError:
        pass
    except UnicodeError:
        return None

    if len(candidate) > 253 or "." not in candidate:
        return None
    labels = candidate.split(".")
    if any(len(label) > 63 or not HOST_LABEL.fullmatch(label) for label in labels):
        return None
    return candidate


def is_allowlisted(domain: str) -> bool:
    return any(domain == suffix or domain.endswith("." + suffix) for suffix in STATIC_ALLOWLIST)


def parse_acceptance(raw_value: str) -> tuple[str, str]:
    source_name, separator, license_id = raw_value.partition(":")
    if not separator or not source_name or not license_id:
        raise argparse.ArgumentTypeError(
            "license acceptance must be formatted as <source>:<SPDX-id>"
        )
    return source_name, license_id


def download_source(source: SourceDefinition, raw_dir: Path) -> tuple[Path, str, int, str]:
    raw_dir.mkdir(parents=True, exist_ok=True)
    suffix = {
        "threat-urls-zip": ".zip",
        "threat-domain-lines": ".txt",
        "safe-domains-gzip-csv": ".csv.gz",
        "safe-domains-zip-csv": ".zip",
    }[source.kind]
    destination = raw_dir / f"{source.name}{suffix}"
    digest = hashlib.sha256()
    byte_count = 0
    retrieved_at = utc_now()
    request = urllib.request.Request(
        source.url,
        headers={"User-Agent": "Aura-Dataset-Pipeline/1.0 (+https://github.com/)"},
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response, tempfile.NamedTemporaryFile(
            mode="wb", dir=raw_dir, prefix=f".{source.name}.", suffix=".download", delete=False
        ) as temporary:
            temporary_path = Path(temporary.name)
            while chunk := response.read(1024 * 1024):
                temporary.write(chunk)
                digest.update(chunk)
                byte_count += len(chunk)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, destination)
    except (OSError, urllib.error.URLError) as error:
        try:
            temporary_path.unlink(missing_ok=True)
        except (UnboundLocalError, OSError):
            pass
        raise DatasetBuildError(f"Download failed for {source.name} ({source.url}): {error}") from error
    return destination, digest.hexdigest(), byte_count, retrieved_at


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=CSV_FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def class_counts(rows: list[dict[str, object]]) -> dict[str, int]:
    labels = Counter(int(row["label"]) for row in rows)
    return {"safe": labels.get(0, 0), "threat": labels.get(1, 0)}
```

El resto descarga las fuentes seleccionadas, registra licencia/hash/timestamp, normaliza y valida dominios, elimina duplicados/conflictos, crea splits estratificados con semilla fija y escribe CSV/manifiesto. Majestic es el baseline seguro obligatorio. No uses `--allow-seed-only` para afirmar evaluación holdout.
