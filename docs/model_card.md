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

Estas cifras históricas proceden de una evaluación anterior con splits por fila, que podrían contener subdominios relacionados en distintos conjuntos. No validan el nuevo método agrupado, no garantizan el mismo rendimiento en otros datos o dispositivos y no se presentan como una evaluación independiente del asset publicado `3.0.0`.

## Datos de entrenamiento documentados

Un manifiesto histórico documenta 484,685 dominios: 384,775 `threat` y 99,910 `safe`. Sus splits anteriores por fila usaban semilla 42: train 339,279; val 72,703; test 72,703. No son resultados del nuevo reparto agrupado. Las fuentes documentadas son Phishing.Database (MIT) para amenazas y Majestic Million (CC BY 3.0) como baseline seguro. Las listas crudas y los splits son artefactos regenerables, no datos versionados en el repositorio.

## Estado de producción y puerta de calidad

El modelo publicado 3.0.0 es un clasificador léxico acotado, no una IA general ni un detector integral de malware. Su evaluación documentada no justifica presentarlo como protección completa: el falso positivo de 10,72 % puede afectar navegación legítima y el recall de 75,89 % implica que una fracción relevante de amenazas etiquetadas no se detectó en ese conjunto. Por tanto, se considera una línea base heredada, no una certificación de seguridad.

El candidato 3.1.0 se entrena desde cero con un conjunto etiquetado reconstruible y 18 características, y no sustituye al modelo activo automáticamente. El pipeline rechaza un candidato si no cumple todos estos mínimos en conjuntos separados:

- Holdout real, no conjunto semilla: tasa de falsos positivos ≤ 8 % y recall de amenazas ≥ 65 %.
- Prueba adversarial separada: tasa de falsos positivos ≤ 15 % y recall de amenazas ≥ 60 %.
- Al menos 500 filas de cada clase en cada partición real y en la prueba adversarial.

El nuevo pipeline asigna todos los subdominios del mismo dominio registrable
ICANN al mismo conjunto mediante un hash determinista con semilla 42. Usa la
lista de sufijos incluida en `tldextract==5.3.0`, sin descarga automática, y
registra su SHA-256. Para sufijos desconocidos agrupa por las dos últimas
etiquetas; las reglas privadas se excluyen deliberadamente para agrupar de forma
conservadora, por ejemplo, los sitios de `github.io`. Rechaza particiones con
menos de 500 filas por clase o con una desviación de más de cinco puntos
porcentuales por clase respecto a las proporciones objetivo 70/15/15. Es un
reparto agrupado con controles de balance, **no estratificación exacta**.

Antes de entrenar, se rechazan duplicados y grupos compartidos entre train,
validación y test. El conjunto adversarial no puede compartir grupos con train ni
validación; puede compartir grupos con el test real, pero cualquier host exacto
reutilizado debe ser seguro en ambos. Esto reduce la fuga por subdominios, pero
no elimina correlaciones por fecha, fuente, familias de marcas o similitud
léxica. La lista fija de dominios populares también se utiliza para extraer
características; no debe interpretarse como una evaluación totalmente ciega a
esos nombres. Sigue faltando evaluación temporal y por fuente con datos reales.

Estos límites son puertas mínimas de ingeniería, no una garantía de rendimiento de producción. El modelo candidato no se promoverá sin revisar el informe, medir rendimiento y tamaño en Android, validar integridad y firma de publicación, y completar pruebas en dispositivo. Los assets firmados actuales no se eliminan ni sustituyen sin una firma válida y una ruta de reversión.

## Limitaciones

- El modelo clasifica nombres de dominio; no inspecciona contenido, formularios ni reputación completa de páginas, y no es un detector de phishing basado en contenido.
- Las puntuaciones representan votos del bosque, no probabilidades calibradas.
- El código del túnel incluye filtros selectivos para TCP/853, UDP/853 y UDP/443 hacia resolutores conocidos, además de inspección SNI en sesiones TCP. Las pruebas nativas no demuestran cobertura universal ni sustituyen la validación de tráfico real en Android. ECH no se descifra; QUIC, DoH no identificado y fragmentación pueden reducir la cobertura.
- Las métricas holdout no garantizan el rendimiento en producción ni sustituyen una revisión humana.
- La visibilidad y el bloqueo dependen de Android, del consentimiento y del alcance observable del `VpnService`.

## Reproducción

Los comandos reproducibles documentados en la sección 4 del README son:

```sh
python -m pip install -r tool/requirements-train.txt
python tool/dataset/build_dataset.py --sources phishing_database
python tool/dataset/build_adversarial_splits.py
python tool/train_max_aura_brain.py
python tool/train_max_aura_brain.py --preset mobile
python tool/bench_aura_brain.py
python -m pytest tool/test_aura_brain.py -q
```

El entrenamiento requiere las fuentes seleccionadas, las condiciones de sus licencias y conjuntos adversariales generados por separado. CI no firma candidatos automáticamente.

## Licencias y atribución

- Código Aura: licencia propietaria del repositorio.
- Phishing.Database: MIT.
- Majestic Million: CC BY 3.0, con atribución.
- URLhaus es opt-in y está sujeto a sus términos; Tranco está deshabilitado como fuente de entrenamiento por las condiciones mixtas de proveedores.

Consulta las licencias de las fuentes antes de regenerar o redistribuir datasets.
