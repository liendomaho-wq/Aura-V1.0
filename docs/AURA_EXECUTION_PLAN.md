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

`5089d35` y `6318277` no compilaban. La fase 2 empieza por dejar el build Android en verde, porque sin APK no hay prueba física de la parada. Ese arreglo de compilación (quitar `underlyingNetworks`) es previo a la fase 2 y no la abre: no añade firewall, IA ni acciones nuevas.

`c0dadfe` rompió `compileDebugKotlin` ([43649867051](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43649867051)). `466f164` lo corrigió y [43652803857](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43652803857) terminó en verde, con el job de Keystore ejecutado. Gradle vuelve a A por ese run. Una política de wrapper verde no sustituye esa compilación.

Después de ese verde, la fase 2 sigue siendo el ciclo de vida de la VPN y SecureVault. El bloqueo que queda es de producto y de prueba en el POVA 5 (API 34).

Poner el motor de ciberdefensa (fase 4) antes del firewall dejaría los hallazgos de red otra vez en contadores de sesión. El motor debe consolidarse cuando ya pueda guardar un evento de bloqueo real. Por eso el firewall va antes, y escribe en el motor de hallazgos que ya existe (`lib/security/`), sin crear un segundo almacén.

## Fase 2 — Base estable (Parte 5)

No empieza hasta que QA acepte esta corrección. El primer paso, cuando haya luz verde, es comprobar que el Android Debug Build y el job de Keystore del SHA corregido están en verde. Eso no es el resto de la fase.

Hecho cuando:

- El TECNO POVA 5 (8 GB, Android 14, API 34) confirma parada desde la consola y desde **Detener**, y el icono de VPN de Android desaparece. Un emulador Android 16 no cuenta.
- El mismo teléfono cambia Wi‑Fi ↔ datos móviles con el túnel aún arriba, y la etiqueta coincide con la red física.
- Un callback de red posterior a la parada no reabre el túnel (`userRequestedStop`).
- SecureVault: cifrado, clave incorrecta y dato alterado. No hay rotación: sustituir la clave sin re-cifrar dejaría el modelo y los hashes ilegibles. No es una migración v9→v10 del teléfono: conservar los datos al actualizar solo vale si el APK nuevo lleva la misma firma. Hasta que el dueño cree el keystore de `docs/FASE_2_PRUEBAS_POVA5.md`, cada APK puede obligar a desinstalar y borrar la bóveda. El `applicationId` no se toca. No se exige StrongBox ni autenticación de usuario: el Escudo y el HMAC no pueden esperar a que el usuario esté delante. La purga borra los datos en el momento y marca la clave AES. Al siguiente arranque, antes de abrir el plugin, se borran los alias del Keystore, `FlutterSecureKeyStorage` y los valores escritos después de la purga, y se reescriben los marcadores. Borrarla en caliente dejaría ilegible lo escrito en esa sesión.
- Un rearranque por VPN siempre activa o por bloqueo, después de una parada del usuario, no llama a `performUserStop` en silencio. El bloqueo vuelve a iniciar el Escudo y lo dice. Always-on sin bloqueo avisa y lo deja apagado.
- `releaseTunnel` y `pthread_join` no corren en el hilo principal. El join nativo tiene un tope de 3 s y, si falla, el hilo sigue siendo joinable.
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

El teléfono del dueño es un **TECNO POVA 5 con 8 GB y Android 14 (API 34)**. El Redmi Note 15 Pro+ (Android 16) sigue siendo la segunda referencia de la spec. No se copian cifras de uno al otro. `5089d35` no generó APK. El primer SHA posterior que volvió a compilar es `eef52b0`, run [43646707387](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43646707387).

**Aviso de firma:** mientras no estén los secretos `AURA_DEBUG_KEYSTORE_BASE64`, `AURA_DEBUG_STORE_PASSWORD`, `AURA_DEBUG_KEY_ALIAS` y `AURA_DEBUG_KEY_PASSWORD`, cada APK de prueba puede salir con otro certificado. Instalarlo encima falla y desinstalar borra SecureVault. Los pasos están en `docs/FASE_2_PRUEBAS_POVA5.md`. No se cambia `com.ciberdefensa.aura`.

| Prueba | Redmi Note 15 Pro+ 5G, Android 16 | TECNO POVA 5, 8 GB, Android 14 (API 34) |
|---|---|---|
| Instalar el APK de prueba del SHA | Pendiente | `5089d35` no se pudo instalar. El APK de `eef52b0` ya compiló; falta instalarlo en el teléfono. |
| Arranque de la VPN | Pendiente | Hecho el 2026-11-14 en un SHA anterior a la rotura; repetir en API 34 con el SHA verde |
| Parada desde Aura y desde Detener | Pendiente | Pendiente. El código está, pero `5089d35` no se pudo instalar. |
| Wi‑Fi ↔ datos, etiqueta correcta, túnel vivo | Pendiente | Pendiente |
| Parada y luego un cambio de red: no debe reencenderse | Pendiente | Pendiente |
| TCP, UDP, DNS, IPv4, IPv6, fugas | Pendiente | Pendiente |
| Batería, temperatura, sesión larga | Pendiente | Pendiente |
| Carga del GGUF, primer token, cancelación, 8K–64K | Pendiente | Pendiente |
| SecureVault: migración y dato corrupto | Pendiente | Pendiente |
| Reglas de firewall, modo estricto y recuperación | Pendiente hasta la fase 3 | Pendiente hasta la fase 3 |

El Redmi sigue siendo la referencia de la spec (Android 16, 8 GB). El POVA 5 es donde el dueño puede mirar cada fase. Un pase en uno no se copia al otro.

## Decisiones abiertas para la fase 2

No se implementan aquí. Recomendación de quien implementa, para que el dueño las confirme.

1. **¿La VPN es solo local o sale a un servidor remoto?** Recomendación: solo local. El túnel termina en un SOCKS5 de `127.0.0.1` dentro del teléfono (`AuraVpnService`). No hay servidor VPN de Aura. Un salto remoto sería otro producto y otra promesa de privacidad.
2. **¿Qué resolver DNS usa?** Recomendación: el que ya está. Dentro del túnel, el DNS es el `mapdns` local `10.0.0.3`. La resolución hacia fuera usa la red física (`resolveHostOnUnderlyingNetwork`), no un DoH propio de Aura. No anunciar un resolver público.
3. **¿Bloquear un dominio bloquea también sus subdominios?** Recomendación: sí, con límite de etiqueta. `domain_matches_rule` en `aura_sni_firewall.c` acepta el nombre exacto o un sufijo separado por punto: `ejemplo.com` cubre `a.ejemplo.com` y no cubre `ejemplo.com.otro.test`. Mantener esa regla y escribirla en la UI cuando exista el firewall. No pasar a “contiene la cadena”.
4. **SecureVault no tiene pantalla.** Recomendación: no inventar un gestor de secretos en la fase 2. La purga sigue detrás de `CONFIRMO`. Una pantalla de solo lectura (“qué queda en el teléfono”) cabe en la fase 6, no en el arreglo del build.
5. **Marca en la UI.** Recomendación: en la consola, “Escudo”. “VPN” solo donde Android obliga a decirlo (permiso del sistema, `VpnService`, texto de notificación que el sistema asocia al túnel). No mezclar las dos palabras en el mismo botón.

## Reglas de cada commit

- Un módulo por commit, mensaje que diga qué comportamiento cambia.
- Si un test está mal porque el contrato cambió, se reescribe el test. No se borra para poner el build en verde.
- Limitación que no se puede quitar: se documenta en la matriz (pasa a D) y en la UI con la alternativa segura.
- Nada de modelos GGUF dentro de Git ni del APK.
