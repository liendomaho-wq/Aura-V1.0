# Model Card de Aura

## Uso previsto

El clasificador local estima si un nombre de dominio debe tratarse como `safe` o `threat`. Aura calcula características léxicas del dominio y evalúa un bosque de decisión local. El resultado apoya el filtrado DNS de la aplicación; no es una garantía de que un dominio sea seguro o malicioso.

## Versiones y esquema

- **Modelo publicado:** versión `3.0.0`, tipo `random_forest`, 500 árboles, profundidad máxima 10 y `min_samples_leaf` 2048. Usa las seis características históricas.
- **Candidato del entrenador:** versión `3.1.0`, configurada con `feature_order` explícito y 18 características (seis históricas y doce añadidas). El entrenamiento y la calibración de este candidato están pendientes; no sustituye automáticamente al modelo publicado.
- **Estado de la evaluación 3.1.0:** pendiente de reentrenamiento real. Las cifras de la sección siguiente son únicamente las métricas previas del candidato móvil 3.0.0; no describen v3.1.0.

Las características describen señales de dominio —por ejemplo, longitud, entropía, proporción de dígitos, TLD, distancia de edición, n-gramas, estructura e indicadores IDN—, no contenido de páginas web. Los votos del bosque no son probabilidades calibradas.

## Evaluación

Las cifras siguientes son las métricas holdout del preset móvil documentadas en el README. Precision, recall, F1 y FPR corresponden a la clase `threat`. La matriz presenta filas reales y columnas predichas `[safe, threat]`.

| Métrica | Resultado |
|---|---:|
| Accuracy | 0.786501 |
| Precision | 0.964630 |
| Recall | 0.758888 |
| F1 | 0.849479 |
| FPR | 0.107160 |
| Matriz de confusión | `[[13381, 1606], [13916, 43800]]` |

Estas métricas describen esa evaluación y no garantizan el mismo rendimiento en otros datos o dispositivos. No se presentan como una evaluación independiente del asset publicado `3.0.0`.

## Datos de entrenamiento documentados

El manifiesto del dataset registra 484,685 dominios: 384,775 `threat` y 99,910 `safe`. Los splits deterministas usan semilla 42: train 339,279; val 72,703; test 72,703. Las fuentes documentadas son Phishing.Database (MIT) para amenazas y Majestic Million (CC BY 3.0) como baseline seguro. Las listas crudas y los splits son artefactos regenerables, no datos versionados en el repositorio.

## Estado de producción y puerta de calidad

El modelo publicado 3.0.0 es un clasificador léxico acotado, no una IA general ni un detector integral de malware. Su evaluación documentada no justifica presentarlo como protección completa: el falso positivo de 10,72 % puede afectar navegación legítima y el recall de 75,89 % implica que una fracción relevante de amenazas etiquetadas no se detectó en ese conjunto. Por tanto, se considera una línea base heredada, no una certificación de seguridad.

El candidato 3.1.0 se entrena desde cero con un conjunto etiquetado reconstruible y 18 características, y no sustituye al modelo activo automáticamente. El pipeline rechaza un candidato si no cumple todos estos mínimos en conjuntos separados:

- Holdout real, no conjunto semilla: tasa de falsos positivos ≤ 8 % y recall de amenazas ≥ 65 %.
- Prueba adversarial separada: tasa de falsos positivos ≤ 15 % y recall de amenazas ≥ 60 %.
- Ambas clases presentes en la prueba adversarial.

Estos límites son puertas mínimas de ingeniería, no una garantía de rendimiento de producción. El modelo candidato no se promoverá sin revisar el informe, medir rendimiento y tamaño en Android, validar integridad y firma de publicación, y completar pruebas en dispositivo. Los assets firmados actuales no se eliminan ni sustituyen sin una firma válida y una ruta de reversión.

## Limitaciones

- El modelo clasifica nombres de dominio; no inspecciona contenido, formularios ni reputación completa de páginas, y no es un detector de phishing basado en contenido.
- Las puntuaciones representan votos del bosque, no probabilidades calibradas.
- No hay un filtro UDP por puerto ni una regla TCP/853 verificada; QUIC/DoQ y DoT no se presentan como bloqueados. El parser y callback existentes propagan una señal para ECH, que no se descifra ni tiene una política configurable de bloqueo. ECH y resolutores no conocidos pueden reducir la detección de red.
- Las métricas holdout no garantizan el rendimiento en producción ni sustituyen una revisión humana.
- La visibilidad y el bloqueo dependen de Android, del consentimiento y del alcance observable del `VpnService`.

## Reproducción

Los comandos reproducibles documentados en la sección 4 del README son:

```sh
python -m pip install -r tool/requirements-train.txt
python tool/dataset/build_dataset.py --sources phishing_database
python tool/train_max_aura_brain.py
python tool/train_max_aura_brain.py --preset mobile
python tool/bench_aura_brain.py
python -m pytest tool/test_aura_brain.py -q
```

El README enumera seis comandos (incluidos los dos modos de entrenamiento); aquí se conservan todos. El entrenamiento requiere las fuentes seleccionadas y sus condiciones de licencia. CI no firma candidatos automáticamente.

## Licencias y atribución

- Código Aura: licencia propietaria del repositorio.
- Phishing.Database: MIT.
- Majestic Million: CC BY 3.0, con atribución.
- URLhaus es opt-in y está sujeto a sus términos; Tranco está deshabilitado como fuente de entrenamiento por las condiciones mixtas de proveedores.

Consulta las licencias de las fuentes antes de regenerar o redistribuir datasets.
