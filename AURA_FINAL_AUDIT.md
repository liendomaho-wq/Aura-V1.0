# Aura Android — auditoría interna y evidencia de cierre

**Fecha:** 2026-11-08 UTC. **Dictamen: NO CERRADO / NO LISTO PARA RELEASE.**
No se certifica protección, ausencia de fugas ni compatibilidad universal. Las
comprobaciones de código, los tests aislados, CI y un teléfono son evidencias
separadas. Ninguna prueba física fue ejecutada en esta sesión.

## 1. Identidad, punto de partida y permisos

- Repositorio: `liendomaho-wq/Aura-V1.0`.
- Rama fija de esta sesión: **`arena/063013fc-aura-v1-0`**. No se creó/cambió a
  otra rama ni se hizo merge o push a `main`.
- HEAD local inicial: `92b6fcce0127d4b2520858f36dcaa9a080188ba8`, checkout limpio.
- [PR #10](https://github.com/liendomaho-wq/Aura-V1.0/pull/10), consultada antes de
  editar: **OPEN**, head `arena/623642b7-aura-v1-0`,
  **`82db8e7a8c24557f2196e0b08ab4ecb69ad92b1c`**, no el `09876be56b4c1beca4c2ef16a7cd6557e701e7b6` proporcionado
  como antecedente. La rama de sesión se adelantó a ese HEAD mediante
  `git fetch --unshallow origin arena/623642b7-aura-v1-0` y
  `git merge --ff-only FETCH_HEAD`. No se partió de `main`.
- `git ls-remote origin refs/heads/main` confirmó
  **`77617f32a016608e3869fd7144e153005c9e3b38`**, también en la comprobación
  posterior a las correcciones.
- Continuación publicada: [PR #11, DRAFT](https://github.com/liendomaho-wq/Aura-V1.0/pull/11),
  destino `main`. No autoriza merge; siguen pendientes criterios de esta auditoría.
- Último código local de esta revisión: `cfbbfbe9db12207e7a54b7b15e350f4f406c5d0a` (identidad completa registrada
  con los commits y checks). La evidencia remota que sigue identifica siempre
  el SHA efectivamente ejecutado; no se atribuye a un descendiente sin reejecución.

Comandos de identidad:

```bash
git status --short
git branch --show-current
git rev-parse HEAD
gh pr view 10 --repo liendomaho-wq/Aura-V1.0 \
  --json state,headRefName,headRefOid,baseRefName,statusCheckRollup
git ls-remote origin refs/heads/main refs/heads/arena/623642b7-aura-v1-0
```

La consulta administrativa `gh api repos/liendomaho-wq/Aura-V1.0/actions/permissions` respondió **HTTP 403:
Resource not accessible by integration**. No se cambió la política ni se intentó
sortear ese permiso. Ello **no demuestra Actions deshabilitado**: los pushes de
esta sesión sí generaron ejecuciones reales. La referencia anterior a HTTP 422
por Actions deshabilitado era histórica, no el estado observado hoy.

## 2. Entorno local y frontera de lo ejecutable

Inicialmente no había `flutter`, `dart`, `java`, `javac`, `sdkmanager`, `adb`, SDK
36 ni NDK `28.2.13676358`. Sí había Python 3.11.2 y GCC. La red permite
GitHub/PyPI/npm, pero las comprobaciones reales de los distribuidores oficiales:

```text
https://api.github.com/repos/liendomaho-wq/Aura-V1.0 -> HTTP 200
https://storage.googleapis.com/flutter_infra_release/flutter/releases/releases_linux.json
  -> URLError: TLS/SSL connection has been closed (EOF)
https://dl.google.com/android/repository/repository2-1.xml
  -> URLError: TLS/SSL connection has been closed (EOF)
```

No se instalaron SDK falsos, headers JNI sustitutos ni mocks para simular builds.
Se instaló fuera del repositorio, sin root:

```bash
python -m venv /home/user/.cache/aura-closeout-venv
/home/user/.cache/aura-closeout-venv/bin/python -m pip install \
  -r tool/requirements-train.txt jdk4py==17.0.9.2 pyyaml
npm pack kotlin-compiler@2.2.20 --ignore-scripts \
  --pack-destination /home/user/.cache/aura-kotlin
```

`jdk4py` suministró **JRE Temurin 17.0.9+9**, no un JDK completo: no hay `javac`
y `java -m jdk.compiler/com.sun.tools.javac.Main -version` respondió
`Module jdk.compiler not found`. Por eso las ocho pruebas AAB locales siguen
omitidas. No se presentan como éxito ni se las acepta omitidas en CI. El
compilador Kotlin real sí compiló las clases puras de VPN con ese JRE.
Flutter/Gradle/Android/JNI completos se delegan a CI con la toolchain real.

## 3. Defectos corregidos y justificación

### Guards VPN que impedían validar la PR

En la base `82db8e7a8c24557f2196e0b08ab4ecb69ad92b1c`, `python3 tool/test_vpn_config_template.py` reprodujo:

```text
File "tool/test_vpn_config_template.py", line 512
  text.split("private fun recoverTunnelAfterNetworkChange()", 1)[1]
IndexError: list index out of range
```

Después apareció `FAIL: VPN underlay fail-closed lifecycle is missing
recoverTunnelAfterNetworkChange()`. El método ya recibía `requestId`.
`d303ec8252ff622241bf0033c0f4b3e82e5a6540` actualiza ambas referencias y limita la extracción de
`onStartCommand` a su firma Kotlin real. **No elimina aserciones.** El guard
completo pasa localmente; su resultado no prueba tráfico Android.

### A. Recuperación con TUN retenido y worker detenido

La PR #10 ya incorporaba una corrección parcial (`025a4e8fd4e58b2bac91a3d150fd0ad46e462c13`, `2fff4bb7d1e0af96fd60e8777b6eded3db3cd150`): reintento
con TUN retenido y callback de la misma red. Se completó en **`7acedb5437b843240e1e7c77e6ec6a235c4db4cd`**:

- `stopTunnelForwardingForNetworkFailure` también libera `startRequested`.
  `handleNetworkRecoveryFailure` conserva el reset y el estado inactivo.
- Inicio explícito y callback de la misma red usan estado nativo observado mediante
  `shieldStatus`, no solo el flag `tunnelStarted`, que puede quedar obsoleto.
- Se exige descriptor válido, ausencia de aislamiento de pánico, ningún arranque
  inicial en curso y ciclo de vida abierto; nunca se crea un segundo TUN para
  recuperar una interfaz válida retenida.
- `VpnRecoveryGate` conserva la propiedad single-flight y el `requestId` capturado;
  una finalización vieja no libera una operación nueva. Éxito y error siguen la
  ruta real de reinicio JNI, handshake RFC 1929 y `VpnLifecycleGate` existente.
- Se prepararon **siete tests JVM** de política, concurrencia real de hilos,
  correlación, cierre y liberación en `finally`. Se añadieron a Codemagic y al
  comando documentado. No simulan Android ni sustituyen HEV.
- Se preservaron y ampliaron los guards: resets de ambas rutas, descriptor válido,
  estado nativo, aislamiento, correlación y propiedad del intento.

Evidencia local: guard completo PASS y compilación Kotlin pura exitosa, detallados
abajo. **Recuperación del servicio Android y fail-closed físico siguen pendientes.**

### B. ADB informativo sin romper el mapa Dart

La PR #10 (`9a2b7f34bc618eb4e407d8824e4ba04c7625bfdc`) ya retiraba ADB del veto de integridad, pero también quitaba
la clave `adbBlocked`. Se comprobó antes de cambiar que `lib/security_engine.dart`
continúa consumiendo/devolviendo **ambas** claves.

**`f94c61de44e94832d5c6d33f06164c761844f6f0`** restaura `adbBlocked=false` y conserva `adbEnabled`. Se mantienen
firma válida, depurador adjunto en builds no debug, instrumentación y fallo de
inspección de mapas; el guard exige todas esas señales y prohíbe ADB en el veredicto.
`SECURITY.md` documenta que las comprobaciones del cliente son **esquivables, no
un límite de seguridad**. No se tocaron datos, políticas biométricas ni cifrado.
La conducta real con ADB habilitado en release sigue pendiente de teléfono.

### Error real de compilación Android: descriptor de socket

El run de `f96bba05f07b89f4708241b62aa7dfe768b601a6` llegó a Gradle y falló:

```text
COMMAND: ./gradlew :app:testDebugUnitTest --no-daemon
> Task :app:compileDebugKotlin FAILED
AuraVpnService.kt:899:21 None of the following candidates is applicable:
fun bindSocket(p0: FileDescriptor!): Unit
fun bindSocket(p0: DatagramSocket!): Unit
fun bindSocket(p0: Socket!): Unit
BUILD FAILED in 3m 28s
184 actionable tasks: 183 executed, 1 up-to-date
```

Fuente: [run 42457981878 / job 128661033462](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42457981878/job/128661033462).
La anotación de `tool/ci_run.py` contiene esa salida real; no es una inferencia.

**`cfbbfbe9db12207e7a54b7b15e350f4f406c5d0a`** usa `ParcelFileDescriptor.fromFd(socketFd).use` y pasa
`descriptor.fileDescriptor` a `Network.bindSocket`. `fromFd` duplica el descriptor;
`use` cierra solo esa copia, **no el socket que pertenece a JNI**. No se usa
`adoptFd`. Se conserva `protect` previo al bind y el retorno falso ante fallo.
El guard exige tanto la sobrecarga válida como la propiedad correcta. La
compilación Android posterior aún debe confirmar la corrección.

## 4. CI, formato y errores secundarios

### Checks de la PR #10 al inicio

El SHA `82db8e7a8c24557f2196e0b08ab4ecb69ad92b1c` tenía tres checks, todos **cancelled**, no vacíos:

- [Flutter Quality 42456931744](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42456931744).
- [Android Debug 42456931730](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42456931730).
- [Model 42456931731](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42456931731).

El run Flutter anterior de `e395f556d02b6e97ecda46dcb921bd8526762d69` fallaba en `Static security regression
checks`; la anotación solo decía exit 1. El `IndexError` de la sección 3 se
reprodujo localmente, no se inventó como una línea descargada de ese log.

### Cambios de automatización

- `e4261fa7b32aa4f061161bf6e88bb6cc4accd31e`: push explícito de la rama fija, checkout del SHA head en vez del merge
  sintético, JDK 17 en Flutter Quality, dependencias Python y pytest completo,
  formato obligatorio, instalación SDK 36/NDK requerido y publicación de APK,
  identidad fuente y SHA-256 **solo si el build realmente termina**.
- El primer comando de instalación `sdkmanager` terminó con **exit 127** en
  [42457485266](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42457485266)
  (`e4261fa7b32aa4f061161bf6e88bb6cc4accd31e`). `c69183b2c70a9d3c3c7615775072de6a1719d8a0` introduce setup-android. Ese bootstrap también falló en
  [42457646823](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42457646823)
  (`c69183b2c70a9d3c3c7615775072de6a1719d8a0`); su log completo no fue descargable y no se atribuye una excepción
  no vista. Se verificó que v3 pide por defecto `tools platform-tools`, y que
  `tools` está retirado. `69a8a8f418bbf33f4f19b87e67e09a192cab0665` pide solo `platform-tools`: setup e instalación
  de SDK/NDK posteriores constan **success** en
  [42457799390](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42457799390).
- Los archivos de log de Actions redirigen a
  `results-receiver.actions.githubusercontent.com`, fuera de la red permitida:
  `gh run view ... --log-failed` termina en **EOF**. `tool/ci_run.py` conserva
  stdout/stderr y el código real; publica la cola del fallo en anotaciones,
  accesibles con `gh api repos/liendomaho-wq/Aura-V1.0/check-runs/128661033462/annotations`. Sus cuatro tests ejecutan
  subprocesos reales y verifican que un exit 17 sigue siendo exit 17.

### Formato Dart sin reimplementar el formateador

El formateador real de CI en `e4261fa7b32aa4f061161bf6e88bb6cc4accd31e` y `f96bba05f07b89f4708241b62aa7dfe768b601a6` informó:

```text
COMMAND: dart format --set-exit-if-changed .
Formatted 58 files (33 changed)
exit 1
```

La salida del diff no cabía en las anotaciones: primero se detectó truncamiento a
4096 bytes y después el límite de diez avisos por paso. Las reconstrucciones
incompletas se rechazaron (`git apply --check` o manifiesto) **y no se aplicaron**.
Los commits `0315fc5b1f45931503bb520f284cbca8b00209bc`, `7e49fc18864dccdd6cb492d65d9f5017e369de1d` y `f96bba05f07b89f4708241b62aa7dfe768b601a6` corrigen la observabilidad mediante
fragmentación UTF-8 y compresión XZ/base64, sin cambiar el resultado del comando.

En [42457981882 / job 128660976437](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42457981882/job/128660976437)
(`f96bba05f07b89f4708241b62aa7dfe768b601a6`) se recuperaron los **13 fragmentos completos**, con manifiesto:

```text
bytes=216731
SHA256=303b013b3931ca891e131063a193444946a313ca483dc3bd01ec0fba4d55c324
encoding=xz+base64
```

`96d35d77647feb8801fc03d6551b920b15ce29eb` aplica exactamente ese patch tras verificar hash, bytes y
`git apply --check`: 33 archivos, solo formato. No se quitaron aserciones ni se
rediseñó la UI. Falta exigir formato sin cambios en un run del nuevo SHA.

### Regresión documental detectada, no prueba debilitada

La reorganización del README (`1904390b53af0d8412ccc0bbe2f5637c99ccb61a`) retiró accidentalmente la tabla de
características que valida `tool/test_aura_brain.py:225`:

```text
assert readme_order == FEATURE_ORDER
AssertionError: assert [] == ['length', ...]
1 failed, 117 passed, 8 skipped, 124 subtests passed
```

`45be3a80d8ff0008b814e299e926389fd5403556` restaura la tabla ordenada original y mantiene el test íntegro. Explica
que solo los primeros seis campos pertenecen al modelo activo 3.0.0. La siguiente
suite local pasó con 118 tests y ocho omisiones AAB conocidas, no con un falso
verde completo.

## 5. Registro local reproducible

Los logs completos de trabajo están en `tool/reports/android-closeout/` (ignorado
por Git; no se suben toolchains, datasets, secretos ni artefactos grandes).

| Código / alcance | Comando real | Salida / límite |
|---|---|---|
| `82db8e7a8c24557f2196e0b08ab4ecb69ad92b1c` | `python3 tool/test_vpn_config_template.py` | `IndexError` en línea 512; log `01-vpn-guard-before.log`. |
| `d303ec8252ff622241bf0033c0f4b3e82e5a6540` y posteriores | `python3 tool/test_vpn_config_template.py` | Todos los guards PASS; sigue siendo inspección de fuente. |
| Clases de `7acedb5437b843240e1e7c77e6ec6a235c4db4cd` | Comando Kotlin completo bajo esta tabla | Kotlin 2.2.20, JRE 17.0.9+9, exit 0, JAR real de 12 KiB; **no** APK/JNI ni ejecución de JUnit. |
| `45be3a80d8ff0008b814e299e926389fd5403556` | `/home/user/.cache/aura-closeout-venv/bin/python -m pytest -q -rs` | **118 passed, 8 skipped, 124 subtests passed in 6.74s**; ocho AAB requieren javac. Log `12-pytest-45be3a8.log`. |
| `dce217bbecdad54aeafb715f109498e8ab5be149` | `python -m pytest -q tool/test_release_signing_policy.py` | **12 passed**; YAML `android-build` parseado y JDK/targets/DEBUG comprobados. No ejecuta Codemagic. |
| `b3a3bfb2b33b073390c6b6cc4d6cbfb121b4a79a` | `python3 -m py_compile tool/device_socks5_probe.py`; `python3 tool/device_socks5_probe.py --help` | Exit 0. Solo sintaxis/CLI: **no se ejecutó el probe en teléfono**. |
| Asset sin cambios | Inspección JSON + SHA-256 con Python | **3.0.0, 500 árboles, 6 campos**, digest `d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2`. No son métricas ML. |
| `cfbbfbe9db12207e7a54b7b15e350f4f406c5d0a` | `python3 tool/test_vpn_config_template.py`; `git diff --check` | PASS / exit 0 después del cambio FileDescriptor; Android pendiente de siguiente run. |

Comando exacto de la compilación Kotlin pura (cinco clases reales, sin Android):

```bash
export JAVA_HOME="$(/home/user/.cache/aura-closeout-venv/bin/python -c 'import jdk4py; print(jdk4py.JAVA_HOME)')"
/home/user/.cache/aura-kotlin/package/bin/kotlinc -jvm-target 17 \
  -d tool/reports/android-closeout/vpn-core.jar \
  android/app/src/main/kotlin/com/ciberdefensa/aura/{VpnRecoveryGate,VpnLifecycleGate,VpnStartRequestGate,AuraSocks5Credentials,Socks5AuthProtocol}.kt
```

La suite incluye pruebas C reales que compilan filtros de host con GCC y pruebas
de decisiones del script de firma con herramientas sustitutas **preexistentes**.
Estas últimas son tests aislados del flujo shell: **no verifican la firma de un
APK real**, ni se usan como evidencia de integración. No se introdujeron mocks
que sustituyan funciones de producción. Las ocho pruebas AAB usan JARs firmados
realmente, pero faltan en el resultado local por ausencia de javac.

## 6. Auditorías de alcance, sin refactor especulativo

### VPN / C / JNI

Inspección: el YAML privado comparte credenciales efímeras con el cliente y el
listener HEV; Android exige RFC 1929, no NONE; el worker verifica readiness antes
de anunciar arranque. El listener limita sesiones a 64 y espera de handshake a
5 s por E/S. JNI conserva `thread_joinable` si falla `pthread_join`, libera datos
de arranque en errores y limpia credenciales nativas al terminar; Kotlin retiene
estado de cierre no confirmado y desregistra callbacks en destrucción.

**No demostrado:** transporte TUN extremo a extremo, parada de todos los sockets/
workers en hardware, TCP/UDP/DNS/IPv4/IPv6 reales y ausencia de fugas. La política
`udp: 'tcp'`, fragmentación y cadenas IPv6 no inspeccionables requieren medidas
reales de compatibilidad. SNI no descifra ECH; listas DNS/IP/puertos no son bloqueo
universal de DoH o QUIC. No se atribuye protección a contenido cifrado invisible.

Se añadió [ANDROID_TRAFFIC_VALIDATION.md](docs/ANDROID_TRAFFIC_VALIDATION.md) y
`tool/device_socks5_probe.py`: probe contra **HEV real** con autenticación,
CONNECT, TLS válido y digest independiente; no imprime secretos ni necesita root.
El protocolo incluye tráfico desde una app normal, fallo real por reserva de
puerto, reactivación sin stopShield, callback de la misma red, aislamiento y ciclos.
**Todos esos casos permanecen pendientes de dispositivo.**

### IA y pipeline histórico

Se separan: ML local 3.0.0 (seis campos), reglas concretas, heurísticas y parser
de intenciones por reglas (**no LLM**). Assets/modelo no se modificaron. No se
promueve 3.1.0 ni se inventan métricas, datasets o evaluaciones independientes.

Del run [40599010820](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/40599010820),
SHA `41f4a77e6390278fb4098a6405880dffa7b69ded`, la API confirma que el 27-oct falló
`Train model and write held-out metrics` y después golden tests; benchmark
omitido. `gh run view 40599010820 --repo liendomaho-wq/Aura-V1.0 --log-failed` **no descargó el log** (EOF en
results-receiver). La anotación solo contiene `Process completed with exit code 1`.
**La causa precisa sigue desconocida; no se opina sobre ella sin el log real.**
El propietario debe descargar y facilitar el log de ese paso, redactando secretos.
Un nuevo entrenamiento no sustituye la evidencia del fallo histórico.

No existe aquí dataset externo verificable ni una evaluación independiente del
modelo activo. Un candidato que pase CI no queda automáticamente aprobado.

### SecureVault y formatos

`lib/secure_vault.dart` mantiene v9→v10, backup y `resetOnError=false`; conserva
secretos inválidos para evitar pérdida silenciosa. v10 usa RSA-OAEP/AES-GCM del
plugin. Los tests Robolectric siembran EncryptedSharedPreferences v9 con
AES256-SIV/AES256-GCM y verifican lectura v10 y backup interrumpido: ejecución
Android pendiente, no prueba de Keystore físico.

No confundir con el sobre de modelo v2: **AES-256-CBC + HMAC**. El código valida
estructura/tamaños y etiqueta antes de descifrar, incluida la ruta JNI. El JSON
empaquetado tiene digest y firma **RSA-2048 PKCS#1 v1.5/SHA-256** separados.
Validación de firma del modelo y firma del APK son contratos distintos.
No se alteraron algoritmos, claves, datos ni formatos para hacer pasar tests.

**Observación sin cambio autorizado:** BiometricPrompt no usa CryptoObject; es
puerta de UI, no autorización criptográfica de cada lectura. Documentado en
SECURITY.md/README; no se cambió sin autorización ni migración diseñada.

### Android y compatibilidad

Inventario, provenance, permisos y AppOps están limitados por APIs públicas,
visibilidad y concesiones reales. Declarar un permiso no demuestra uso activo;
los estados desconocidos se conservan como tales. No se añadió ejecución root,
Shizuku, Superuser ni capacidad de aislamiento arbitrario de otras apps.

Contrato declarado: minSdk 24 → target/compileSdk 36 (Android 16), JDK 17,
Gradle 8.14.3, AGP 8.13.0, Kotlin 2.2.20, NDK 28.2.13676358 y cuatro ABIs.
**Configuración no equivale a compatibilidad universal.** Redmi Note 15 Pro Plus
5G/8 GB/Android 16 y versiones intermedias/API 24 necesitan validación física.

## 7. Codemagic y acciones exactas del propietario

`codemagic.yaml` define **`android-build`**, nombre Aura Android Release Pipeline,
Flutter stable, Java 17, mac_mini_m2. Se conserva el arreglo `ce82a4918d424c10e03234dfb29d1626be7efd79`: patrones
`main`/`principal` con **`source: false`** para PRs destino. `dce217bbecdad54aeafb715f109498e8ab5be149` exige formato,
pytest completo y tests de recuperación/migración. Por defecto:
`AURA_REQUIRE_RELEASE_SIGNING=false`, artefacto **DEBUG de prueba, NO DISTRIBUIR**.

Arena informó que no ofrece conector Codemagic; no hay sesión/API/build real
accesible en este trabajo. **No se afirma ejecución ni éxito de Codemagic.**
El propietario debe:

1. Abrir la app correcta en Codemagic y elegir el workflow `android-build` sobre
   el SHA final de `arena/063013fc-aura-v1-0` / PR #11, no un main distinto.
2. Verificar que el grupo `production_keys` declarado existe; los valores se
   configuran solo en su almacén seguro. El comentario antiguo que garantizaba
   que un grupo ausente no fallaría se retiró por no estar verificado.
3. Revisar **Webhooks → Recent Deliveries**: repo correcto, evento PR/push,
   destino main, head/SHA correctos, respuesta HTTP y mensaje de rechazo si lo
   hubo. Un 2xx no prueba que un build haya terminado. Si no hay entrega/build,
   lanzar manualmente y conservar el enlace y logs completos.
4. Comprobar toolchain, formato, análisis, tests sin omisiones AAB, migración,
   JNI, APK y su hash; comparar el SHA real del build antes de instalar.
5. Proporcionar dispositivo autorizado y servidor controlado para la matriz de
   tráfico; no se puede reemplazar ese acceso desde este sandbox.

Actions sí está ejecutando en esta revisión. Solo si vuelve a responder
`Actions has been disabled for this repository`, el propietario debe ir a
**Settings → Actions → General → Allow all actions** y ejecutar manualmente
**Aura Flutter Quality** y **Aura Android Debug Build** sobre esta rama. No se
solicitan contraseñas, tokens, 2FA ni secretos en chat.

## 8. Criterios de terminado (situación antes del siguiente run)

- [ ] `flutter analyze` limpio en el SHA final.
- [ ] `flutter test` en el SHA final.
- [ ] pytest completo con **cero AAB omitidos en CI**.
- [ ] JVM: credenciales, RFC 1929, ciclo de vida, correlación, recuperación y migración.
- [ ] C/JNI compilado por NDK para el candidato.
- [ ] APK debug generado desde el SHA final, publicado y con SHA-256.
- [ ] APK instalado en dispositivo real — requiere propietario.
- [ ] VPN inicia/detiene y libera recursos en hardware.
- [ ] SOCKS5 autenticado conectado al forwarding TUN real.
- [ ] TCP/UDP/DNS/IPv4/IPv6 y fugas.
- [ ] Cambio de red y reactivación tras fallo, incluido callback de la misma red.
- [ ] IA con dataset/métricas reproducibles y evaluación independiente.
- [ ] SecureVault/migración preserva datos en hardware y suites requeridas.
- [x] Compatibilidad **documentada con límites**, no certificada universalmente.
- [x] README de producto/ingeniería y auditoría interna separados y actualizados.

No hay APK ni SHA-256 de APK atribuible aún a esta revisión. **Funciones
verificadas en dispositivo: ninguna.** No hacer merge, publicar ni declarar Aura
terminada mientras los criterios pendientes no tengan evidencia del SHA correcto.
