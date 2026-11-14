# Plan de ejecución — Aura

**Fecha:** 2026-11-14  
**Base:** `5089d35b9764d27075ec5d67ea25cf7dcb9da4a5` en `main`  
**Spec:** [AURA_MASTER_PROMPT.md](AURA_MASTER_PROMPT.md)  
**Matriz:** [AURA_STATUS_MATRIX.md](AURA_STATUS_MATRIX.md)

La Parte 7 (robot, voz, interfaz visual) no entra en este plan. El dueño la dejó para el final y, además, esta tanda la difiere. No se abre una fase 7 hasta que él lo pida por escrito.

Cada fase se integra en `main` con commits pequeños. No se empuja si `flutter analyze` o `flutter test` fallan, ni si se rompe un workflow a propósito. No se mezclan los 11 pull requests abiertos: están atrasados respecto a `main`.

## Orden

| Fase | Spec | Objetivo | Depende de |
|---|---|---|---|
| 1 | Parte 1 | Esta auditoría. | — |
| 2 | Parte 5, más lo que impida compilar o ejecutar | Base estable: VPN que arranca, para y sobrevive al cambio de red; SecureVault sin perder datos. | Fase 1 |
| 3 | Parte 4 | Firewall real encima de esa VPN: DNS, reglas, modos. | Fase 2 |
| 4 | Parte 3 | Un solo motor de hallazgos que consuma auditoría, apps y eventos del firewall. | Fase 3 (los eventos tienen que existir) |
| 5 | Parte 2 | Cerebro local: gestor ya existente, inferencia llama.cpp de verdad, registro de herramientas y memoria. | Fases 2–4, para que las herramientas lean estado real |
| 6 | Parte 6 | Acciones e incidentes, solo con lo que las fases 3–5 ya sepan hacer. | Fase 5 |
| 8 | Parte 8 | Validación, CodeMagic, docs y el informe A–J. | Fases 2–6 |

No se adelanta la fase 3 ni la 5. El firewall sobre una VPN que no para, o una IA que “bloquea” sin motor, repetiría la simulación que la spec prohíbe.

## Por qué no se cambia el orden

La matriz no muestra un fallo de compilación en `5089d35`. El bloqueo real es de producto y de prueba física, no de Gradle. Por eso la fase 2 no es “arreglar el build” en abstracto: es cerrar el ciclo de vida de la VPN y el vault, que son la base de todo lo demás.

Poner el motor de ciberdefensa (fase 4) antes del firewall dejaría los hallazgos de red otra vez en contadores de sesión. El motor debe consolidarse cuando ya pueda guardar un evento de bloqueo real. Por eso el firewall va antes, y escribe en el motor de hallazgos que ya existe (`lib/security/`), sin crear un segundo almacén.

## Fase 2 — Base estable (Parte 5)

Hecho cuando:

- El TECNO POVA 5 confirma parada desde la consola y desde **Detener**, y el icono de VPN de Android desaparece.
- El mismo teléfono cambia Wi‑Fi ↔ datos móviles con el túnel aún arriba, y la etiqueta coincide con la red física.
- Un callback de red posterior a la parada no reabre el túnel (`userRequestedStop`).
- SecureVault: cifrado, clave incorrecta, dato alterado y migración v9→v10 sin borrar el secreto viejo antes de validar el nuevo. Si el Keystore del teléfono no puede probarse, se documenta el límite y no se finge la migración.
- `flutter analyze` y `flutter test` siguen en verde. Los tests de `tool/test_vpn_config_template.py` se actualizan si cambia el contrato, no se debilitan.

No entra en esta fase: modos de firewall, IA generativa, ni el protocolo completo de fugas. Ese protocolo se deja listo para ejecutarlo, no se marca como pasado.

## Fase 3 — Firewall (Parte 4)

Sobre `AuraVpnService`, sin una segunda VPN.

- Repositorio de reglas persistente (id, prioridad, ALLOW/BLOCK/LOG, caducidad) y evaluación determinista.
- Filtro DNS con normalización: `example.com` no bloquea `example.com.malicioso.test`. IDN y Unicode cubiertos por tests.
- Modos Desactivado, Equilibrado, Estricto y Personalizado, cada uno con reglas reales. Estricto avisa y se puede deshacer.
- Contadores leídos del motor, no de la UI.
- Límite escrito: DoH ajeno, ECH y QUIC no se “bloquean” si no se ven.
- No se ofrece bloqueo por app como si dejara a la app sin internet.

## Fase 4 — Motor de ciberdefensa (Parte 3)

Reutilizar `AuraFindingsEngine`, el escáner y el correlador. No duplicarlos.

- Un hallazgo guarda evidencia, gravedad, confianza, estado e historial.
- Se puede filtrar, buscar, marcar revisado, resolver y reabrir sin perder la evidencia.
- La reputación lleva procedencia, fecha y vigencia. Sin red se usa la caché y se dice que está vieja.
- La remediación abre Ajustes o el flujo oficial. No declara éxito hasta leer el estado de Android.
- La IA, cuando exista en la fase 5, solo consultará este motor.

## Fase 5 — Cerebro (Parte 2)

No cambiar el GGUF pinneado sin una comparación escrita.

- Carga, un token real, cancelación, descarga del modelo y recuperación si falta `libaura_llm.so`.
- El gestor de descarga ya está: hay que probarlo en el teléfono (interrupción, hash malo, borrado con el modelo cargado).
- Contexto: medir 8K, 16K, 32K y 64K en el aparato y quedarse con el máximo estable. 64K sigue siendo objetivo, no un anuncio.
- Memoria local editable y borrable. Sin contraseñas ni datos bancarios.
- El modelo propone; la política valida; el servicio ejecuta. Ningún texto del modelo entra directo a una operación.

## Fase 6 — Acciones (Parte 6)

Solo acciones que las fases anteriores ya verifican: regla de firewall, VPN, auditoría, abrir ajustes.

- Cada acción tiene riesgo, autorización, timeout y resultado.
- `CONFIRMO` no se convierte en un permiso eterno.
- WorkManager para lo periódico, respetando Doze. Sin un segundo servicio eterno.
- Historial resistente y un informe local. Rollback solo donde la acción sea reversible de verdad.

## Fase 8 — Cierre (Parte 8)

- Repetir análisis, tests Flutter, Python, JVM y el build de CodeMagic del SHA final.
- APK debug identificado como prueba. Release solo con firma de producción explícita.
- Escribir o actualizar, sin copiar los mismos párrafos: `AURA_ARCHITECTURE.md`, `AURA_SECURITY.md`, `AURA_FIREWALL.md`, `AURA_VPN.md`, `AURA_AI.md`, `AURA_TESTING.md`, más README y `ANDROID_TRAFFIC_VALIDATION.md`.
- Informe A–J. El porcentaje de A tiene que salir de una matriz actualizada, no de un número redondo.
- Lista de pasos físicos todavía no hechos. No inventar resultados para llegar al 100 %.

## Pruebas físicas (los dos teléfonos)

| Prueba | Redmi Note 15 Pro+ 5G, Android 16 | TECNO POVA 5 (teléfono actual del dueño) |
|---|---|---|
| Instalar el APK de prueba del SHA | Pendiente | Pendiente para `5089d35` |
| Arranque de la VPN | Pendiente | Hecho el 2026-11-14 en un SHA anterior; repetir en el SHA de la fase 2 |
| Parada desde Aura y desde Detener | Pendiente | Pendiente (`5089d35`) |
| Wi‑Fi ↔ datos, etiqueta correcta, túnel vivo | Pendiente | Pendiente |
| Parada y luego un cambio de red: no debe reencenderse | Pendiente | Pendiente |
| TCP, UDP, DNS, IPv4, IPv6, fugas | Pendiente | Pendiente |
| Batería, temperatura, sesión larga | Pendiente | Pendiente |
| Carga del GGUF, primer token, cancelación, 8K–64K | Pendiente | Pendiente |
| SecureVault: migración y dato corrupto | Pendiente | Pendiente |
| Reglas de firewall, modo estricto y recuperación | Pendiente hasta la fase 3 | Pendiente hasta la fase 3 |

El Redmi sigue siendo la referencia de la spec (Android 16, 8 GB). El POVA 5 es donde el dueño puede mirar cada fase. Un pase en uno no se copia al otro.

## Reglas de cada commit

- Un módulo por commit, mensaje que diga qué comportamiento cambia.
- Si un test está mal porque el contrato cambió, se reescribe el test. No se borra para poner el build en verde.
- Limitación que no se puede quitar: se documenta en la matriz (pasa a D) y en la UI con la alternativa segura.
- Nada de modelos GGUF dentro de Git ni del APK.
