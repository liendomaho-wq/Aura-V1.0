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
- Esta auditoría distingue el **SHA realmente ejecutado** del código posterior.
  Las instantáneas remotas se atribuyen abajo a su SHA y comando, sin heredar
  resultados de una revisión anterior. El resumen de PR #11 conserva la
  reejecución del candidato final sin un bucle de pushes sólo documentales. El HEAD final
  se obtiene con `git rev-parse HEAD` y con `SOURCE_COMMIT.txt` del artefacto.

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
compilación de producción y de tests Kotlin **sí terminó** en `ca2c10a`,
`50349c2`, `622b459` y en el build/APK real de `e8b2db7` descrito abajo.

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
  accesibles con `gh api repos/liendomaho-wq/Aura-V1.0/check-runs/128661033462/annotations?per_page=100`.
  Sus seis tests incluyen subprocesos reales: un exit 17 sigue siendo exit 17,
  las colas largas se reconstruyen sin truncar UTF-8 y los resúmenes positivos
  contienen solamente líneas realmente emitidas, no contadores inferidos.

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
rediseñó la UI. El formato sin cambios ya consta **success** en `ca2c10a`,
`50349c2`, `622b459` y `e8b2db7`; la nueva corrección de fixture también debe
pasar el comando real en su propio SHA.

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

### Fallos completos recuperados, no suposiciones

- **`ca2c10a` y `50349c2`:** pub get, formato, guards, las pruebas AAB con JDK,
  pytest completo y `flutter analyze` terminaron con éxito. Flutter terminó con
  **189 passed / 1 failed / 1 skipped**. La omisión ya existente es el benchmark
  que requiere dispositivo/entorno local, no una prueba AAB omitida.
  [Quality `50349c2`, job 128664476522](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42459146789/job/128664476522)
  recuperó el error real: **Found 0 widgets with type "AuraCoreScreen"** en
  `compact unsecured access reaches a core without layout errors`. No era una
  excepción demostrada de overflow.
- [Android `50349c2`, job 128664476675](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42459146842/job/128664476675)
  compiló producción/tests Kotlin y ejecutó **21 tests JVM, 2 fallidos**. La
  primera excepción JUnit XML recuperada íntegra fue:

  ```text
  SecureStorageMigrationTest.restartsAnInterruptedBackupAndStillMigratesVersion9Secret
  java.security.KeyStoreException: AndroidKeyStore not found
    at java.security.KeyStore.getInstance(KeyStore.java:877)
    at androidx.security.crypto.MasterKeys.keyExists(MasterKeys.java:155)
    at androidx.security.crypto.MasterKeys.getOrCreate(MasterKeys.java:99)
    at androidx.security.crypto.MasterKey$Builder$Api23Impl.build(MasterKey.java:380)
    at SecureStorageMigrationTest.seedVersion9EncryptedSharedPreferences(SecureStorageMigrationTest.java:103)
  Caused by: java.security.NoSuchAlgorithmException: AndroidKeyStore KeyStore not available
  ```

  `f7c4c9b` mueve **las dos pruebas y todas sus aserciones originales** a
  `androidTest`/AndroidJUnit4; no añade un proveedor Keystore sustituto. La
  variante `storageMigration` usa `com.ciberdefensa.aura.vaultmigrationtest`
  (otro UID) y preferencias namespaced. El test rechaza otro paquete **antes**
  de limpiar nada. Esto también aísla el alias ESP que v10 fija por defecto;
  sólo un namespace de preferencias no habría aislado ese alias.
- [Android `622b459`, job 128727819933](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42479398575/job/128727819933):
  las **19 pruebas JVM restantes** y el guard VPN pasaron. La prueba real
  instrumentada no se ejecutó: el runner no tiene acceso KVM sin privilegios.
  El error se mantiene y no se usa sudo/root, un proveedor falso ni
  `continue-on-error`. `09051a9` separa ese job de la generación del APK; una
  compilación correcta **no convierte la migración pendiente en aprobada**.
- [Quality `622b459`, job 128727820075](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42479398591/job/128727820075)
  dejó visible el estado del fallo: **ACCESO LOCAL VALIDADO; INICIALIZANDO
  BÓVEDA SEGURA...**. Se comprobó el código real de Dart: los listeners tardíos
  de un Future se programan en su zona de origen. La cola estática retenía un
  Future completado de un scheduler de boot/test ya terminado.
  `79cc0a9` libera la cola al quedar inactiva, conserva la reserva del siguiente
  solicitante, la serialización entre instancias, la propagación de errores y
  el borrado de buffers. No cambia algoritmos, claves ni formatos guardados.
- [Quality `e8b2db7`, job 128730479788](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42480272282/job/128730479788)
  pasó formato, guards, Python/JDK y análisis. Flutter: **192 passed / 2 failed /
  1 skipped**. Las cuatro regresiones nuevas de cola pasaron; los dos tests de
  boot posteriores se detuvieron ahora en **VALIDANDO MODELO LOCAL E
  INTEGRIDAD...**. Se fortaleció el test de credencial para exigir navegación
  completa y no quedarse en el mensaje intermedio que antes aceptaba.
  Flutter `CachingAssetBundle` conserva un `Future<String>` del digest entre
  tests. `361a8fc` evicta **sólo esa caché de fixture** entre schedulers: el
  loader, JSON, digest y firma reales siguen ejecutándose, sin bundle falso,
  ampliación de timeout ni bypass. Su validación remota posterior no se da por
  hecha en esta instantánea.

### Primer APK real y firma/SBOM comprobados

[Build `e8b2db7`, run 42480272489 / job 128730480572](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42480272489/job/128730480572):
**success, 7m52s**. Pasaron JVM, guard VPN, `flutter build apk --debug`, existencia,
SHA-256 y upload. El preBuild real incluye `buildHevSocks5Tunnel` con NDK
`28.2.13676358`; esto es compilación/artefacto, no ejecución de JNI en teléfono.

```text
SOURCE_COMMIT=e8b2db7554355d3eecd10f196a49b2ea47c38abe
APK SHA256=d35246748ac6e32f9a8e5fa5947a7b64b08bd2626a27039a88afd1438f40c4a0
artifact=aura-debug-e8b2db7554355d3eecd10f196a49b2ea47c38abe
artifact_id=13617676231
artifact ZIP size=86004454 bytes
artifact ZIP digest=sha256:b707e20cf4124cfd50b6b9f765237b6c3aed9594d522f026cda103edcb704d92
```

[Descarga del artefacto](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42480272489/artifacts/13617676231)
(según permisos de GitHub). El digest del **ZIP de Actions no es el hash del
APK**. No se afirma que este APK incluya cambios posteriores a `e8b2db7`, ni que
sus pruebas Flutter hayan pasado: los dos fallos anteriores siguen registrados.

[El job de migración del mismo run](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42480272489/job/128732371325)
terminó **failure, 8s**, antes de SDK/test por el requisito KVM, con:

```text
This runner has no unprivileged KVM access. Provide a KVM-enabled runner;
no root/device bypass is used.
```

[Release signing integrity `e8b2db7`, run 42480272339](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42480272339)
tuvo **los tres jobs success**: guard 2m27s, positivo 2m43s, SBOM 3m15s. La
verificación positiva usa una clave efímera de CI, **no** la identidad de
producción del propietario ni la firma de publicación del APK debug.
`e8b2db7` corrigió el viejo awk que rechazaba incluso el ternario de fallback
**ya existente y opt-in**. El script anterior se reprodujo localmente: exit 1,
`Missing release block or debug signing reference found in it.`. Se conservan
la prueba negativa real de credenciales ausentes y la positiva real que exige
`IS_DEBUG_SIGNING=false`, certificado/alias esperados; la suite completa exige
el default-deny de producción. No se relajó el código de firma productiva.
Los fallos previos SBOM/positivo de `622b459` sólo tenían detalle genérico/timeout;
no se les inventa una causa retrospectiva.

`c893108` añade colas **reales** de éxito en anotaciones, contadores leídos de
JUnit XML, comprobación del ELF HEV empaquetado de las cuatro ABIs y comparación
byte a byte del modelo/digest/firma del APK con el checkout; además el hash usa
un nombre portable. `f840951` exige compilar los APKs aislados de instrumentación
antes de publicarlos como código compilable. **Su ejecución Android y la
inspección de un APK posterior siguen pendientes de su propio CI.**

### Reejecución `f1e2e1b`: contadores positivos y siguientes errores reales

[Quality run 42481253389 / job 128733462079](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42481253389/job/128733462079)
publicó ahora la salida real de los comandos correctos:

```text
dart format --set-exit-if-changed .
Formatted 58 files (0 changed) in 0.28 seconds.
python3 tool/test_verify_aab.py
Ran 8 tests in 1.960s
OK
python3 -m pytest -q -rs
133 passed, 124 subtests passed in 9.37s
flutter analyze --no-pub
No issues found! (ran in 9.1s)
```

No hubo AAB/Python omitidos. Flutter mejoró a **193 passed / 1 failed / 1
skipped**: ambos boots completaron carga y navegación, y la prueba de credencial
más estricta pasó. El error siguiente fue real, no inferido por el nombre:

```text
Expected: null
Actual: FlutterError:<A RenderFlex overflowed by 212 pixels on the bottom.>
aura_splash_auth_test.dart:180
compact unsecured access reaches a core without layout errors
```

`80b3d59` hace desplazable únicamente el overview/features/warnings mediante
slivers; conserva la barra VPN y entrada/acciones fijadas, el ListView/controller
de eventos y los colores/avatar. El test mantiene la aserción de ausencia de
excepciones y añade scroll y límites visibles de los controles. No se oculta ni
recorta la excepción, ni se rediseña el producto. Validación posterior pendiente.

[Android run 42481253396 / job 128733462399](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42481253396/job/128733462399)
reportó desde **XML JUnit real**:

```text
tests=19, failures=0, errors=0, skipped=0
AuraSocks5CredentialsTest: 1; Socks5AuthProtocolTest: 3;
VpnLifecycleGateTest: 3; VpnRecoveryGateTest: 7; VpnStartRequestGateTest: 5
```

La compilación de los APKs aislados encontró después el primer error de
`androidTest` antes inaccesible por KVM:

```text
Execution failed for task ':app:processStorageMigrationAndroidTestManifest'.
Could not resolve androidx.test:runner:1.7.0.
Constraint: androidx.test:runner:{strictly 1.3.0}
version resolved in ':app:storageMigrationRuntimeClasspath' by consistent resolution
```

`1e2d067` alinea runner/JUnit en las dos classpaths **sólo de la app aislada**;
no desactiva la consistencia de AGP, modifica el runtime productivo ni cambia
aserciones/proveedor. No se generó/publicó un APK nuevo desde `f1e2e1b`: el fallo
anterior detuvo correctamente ese build. El APK `e8b2db7` sigue siendo evidencia
histórica, no se atribuye al nuevo código.

[Signing/SBOM run 42481253416](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42481253416)
volvió a pasar los tres jobs: guard 1m52s, positivo 3m07s, SBOM 3m30s. El modelo
[run 42481253401](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42481253401)
terminó **failure, 10m04s**, por el mismo presupuesto de 4 MiB; golden tests y
upload de reportes pasaron. El rechazo no se silenció ni cambió el asset 3.0.0.

### `3e56b23`: APKs aislados compilados y ELF/modelo verificados

[Android run 42482115637 / job 128736106014](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42482115637/job/128736106014)
terminó **success, 8m05s**. La alineación de dependencias resolvió el error real:

```text
./gradlew :app:assembleStorageMigration :app:assembleStorageMigrationAndroidTest --no-daemon
BUILD SUCCESSFUL in 1m 53s
275 actionable tasks: 269 executed, 6 up-to-date
flutter build apk --debug
Running Gradle task 'assembleDebug'... 72.2s
Built build/app/outputs/flutter-apk/app-debug.apk
APK SHA256=704ced641255d00e558a86ae366491afaed8ba61c96187848ecbcbed42835637
```

La compilación de AndroidJUnit4 es ahora evidencia real, **no ejecución** de
migración. Los XML JVM volvieron a dar 19/0 fallos/0 errores/0 omitidos. La
inspección del APK real validó encabezados ELF/clase/máquina y obtuvo:

| `libhev-socks5-tunnel.so` | Bytes | SHA-256 |
|---|---:|---|
| armeabi-v7a | 245872 | `ff06fc993971522f91693f3de33c5d305456cf6bfaa357da96102d2447e7ebfb` |
| arm64-v8a | 360552 | `069579db22fcfef2ba9af48080a0958efec34e941da786d93afc16d9661adfcc` |
| x86 | 346744 | `c7a58ae0155678d66c5f3665428a326858121d156eaaa1fd57bee88258ee5f71` |
| x86_64 | 360440 | `9b5111143384b223b85e457457e0a75f763e78e76587369caf5da62311f9a093` |

Modelo, digest y firma dentro del APK coinciden **byte a byte** con el checkout;
el SHA del modelo sigue siendo `d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2`.
Esto no demuestra llamadas JNI, hardware 16 KiB, tráfico ni compatibilidad Flutter
universal en esas cuatro ABIs.

Artefacto [13617898982](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42482115637/artifacts/13617898982),
`aura-debug-3e56b23ffe360a5996cb2e242ec8074e6e4aa769`, ZIP 86006887 bytes,
digest ZIP `8de59aecb60547a062954d4682c5fb9317a06c4b94d1c6e20f5e9c56ea00fe8d`.
Incluye `SOURCE_COMMIT.txt` y `SHA256SUMS` portable para `app-debug.apk`. Su hash
APK está arriba: no confundirlo con el ZIP. Su migración instrumentada volvió a
fallar antes de ejecutar por KVM en
[job 128737977048](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42482115637/job/128737977048).

[Quality run 42482115606](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42482115606/job/128736106255)
se detuvo correctamente en el formateador: 58 archivos, 2 cambiados. Por tanto
**no se atribuye una ejecución de widgets a `3e56b23`**. `3f3ffa5` aplica exactamente
su salida, con manifiesto verificado: 9153 bytes, un fragmento XZ/base64, SHA-256
`dd803e65709cf8ee23267528ff3c2de86b9bcdd707e7c53a4b1261fc1f92b8b6`;
`git apply --check`, guards y 24 tests locales pasaron. Es sólo formato.
Firma/SBOM de `3e56b23` también pasó en sus tres jobs; el candidato ML volvió a
ser rechazado por tamaño (run 42482115764, 6m47s). No se canceló ni maquilló ese
resultado para publicar la corrección.

La próxima reejecución debe validar el layout ya formateado. Para evitar atribuir
el futuro a este documento inmutable, el resultado exacto del HEAD posterior se
consulta en [checks de PR #11](https://github.com/liendomaho-wq/Aura-V1.0/pull/11/checks),
sus anotaciones de comandos reales y los manifiestos del artefacto
`aura-debug-<SHA>`. El resumen final de la PR identifica explícitamente esos
resultados, incluido cualquier criterio todavía fallido.

### `1844ec8` / `64167f8`: overflow resuelto; navegación del overview pendiente

El [quality de `1844ec8`](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42482843454/job/128738342663)
confirmó formato 58/0, análisis limpio, **134 pytest + 124 subtests, cero
omisiones**, ocho pruebas AAB directas y la prueba compacta 320×568 **pasando**,
con desplazamiento y controles fijados. Su suite Flutter siguió en
**193 pasan / 1 falla / 1 benchmark de dispositivo omitido**; no era ya el
overflow. Android volvió a compilar ambos APKs de migración, 19 JVM y el debug;
KVM siguió fallando. El candidato ML volvió a rechazarse en 10m32s
(run 42482843323), sin promover ni alterar el modelo base.

La cola de 60 líneas del comando no contenía la primera excepción, desplazada
por los tests que sí pasaban. `64167f8` conserva además el primer grupo fallido
**real** del reporter de Flutter, sin alterar salida completa ni exit code.
Su regresión usa un proceso hijo real que sale 9 tras 100 líneas posteriores;
la excepción se conserva y el fallo sigue siendo fallo. El full pytest local
fue 127/8 omitidas/124 subtests (`21-first-failure-preservation-local-python.log`),
no una validación AAB local.

El [quality de `64167f8`](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42483753574/job/128741044975)
ejecutó de verdad **135 pytest + 124 subtests / cero omisiones**, ocho AAB
directas en 3.262s, formato 58/0 y análisis limpio (6.1s). Flutter repitió
193/1/1 y recuperó íntegra esta primera excepción:

```text
flutter test --no-pub
activates and stops VPN through the native shield channel (failed)
Expected: exactly one matching candidate
Actual: Found 0 widgets with text "Hola, soy Aura."
file:///home/runner/work/Aura-V1.0/Aura-V1.0/test/aura_core_screen_test.dart:149:5
```

Después de llevar el panel de telemetría a pantalla, el overview queda fuera del
viewport. Se coordina ahora cabecera/consola con `NestedScrollView` y su
controlador interno primario, en vez de scrollables independientes. Se conserva
la imagen inicial del avatar; los nuevos eventos continúan desplazando la
consola. La regresión original **añade un gesto real de regreso desde la consola**
antes de sus aserciones originales de saludo/avatar/estado: no se borran ni
relajan, ni se usa `skipOffstage: false`. Barra VPN y entrada siguen fuera del
área desplazable; ni el protocolo nativo ni datos/criptografía cambian.

La corrección posterior sólo tiene guards y 25 políticas/wrapper locales
verificados al escribir este punto (`22-coordinated-scroll-vpn-guards.log`).
Su formateo y ejecución Flutter reales aún deben confirmarse en el siguiente CI;
la excepción anterior no se convierte retroactivamente en éxito.

## 5. Registro local reproducible

Los logs de trabajo se escriben en `tool/reports/android-closeout/`, ignorado
por Git. Los archivos ignorados/cachés no garantizan persistencia entre sandboxes;
los IDs, comandos y extractos esenciales se conservan aquí. En esta continuación
se regeneraron realmente `14-instrumentation-policy-tests.log`,
`15-full-python-suite.log`, `16-original-release-static-guard.log` y
`17-full-python-with-evidence.log`. No se suben toolchains, datasets, secretos ni
artefactos grandes al repositorio. Los APK/SBOM quedan en artefactos de Actions.

| Código / alcance | Comando real | Salida / límite |
|---|---|---|
| `82db8e7a8c24557f2196e0b08ab4ecb69ad92b1c` | `python3 tool/test_vpn_config_template.py` | `IndexError` en línea 512; log `01-vpn-guard-before.log`. |
| `d303ec8252ff622241bf0033c0f4b3e82e5a6540` y posteriores | `python3 tool/test_vpn_config_template.py` | Todos los guards PASS; sigue siendo inspección de fuente. |
| Clases de `7acedb5437b843240e1e7c77e6ec6a235c4db4cd` | Comando Kotlin completo bajo esta tabla | Kotlin 2.2.20, JRE 17.0.9+9, exit 0, JAR real de 12 KiB; **no** APK/JNI ni ejecución de JUnit. |
| `45be3a80d8ff0008b814e299e926389fd5403556` | `/home/user/.cache/aura-closeout-venv/bin/python -m pytest -q -rs` | **118 passed, 8 skipped, 124 subtests passed in 6.74s**; ocho AAB requieren javac. Log `12-pytest-45be3a8.log`. |
| `dce217bbecdad54aeafb715f109498e8ab5be149` | `python -m pytest -q tool/test_release_signing_policy.py` | **12 passed**; YAML `android-build` parseado y JDK/targets/DEBUG comprobados. No ejecuta Codemagic. |
| `b3a3bfb2b33b073390c6b6cc4d6cbfb121b4a79a` | `python3 -m py_compile tool/device_socks5_probe.py`; `python3 tool/device_socks5_probe.py --help` | Exit 0. Solo sintaxis/CLI: **no se ejecutó el probe en teléfono**. |
| Asset sin cambios | Inspección JSON + SHA-256 con Python | **3.0.0, 500 árboles, 6 campos**, digest `d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2`. No son métricas ML. |
| `cfbbfbe9db12207e7a54b7b15e350f4f406c5d0a` | `python3 tool/test_vpn_config_template.py`; `git diff --check` | PASS / exit 0; compilación Android ya confirmada posteriormente, ver sección 4. |
| `f7c4c9b` | pytest de políticas de firma/instrumentación y wrapper | **21 passed in 0.15s**; todas las aserciones originales Java conservadas verbatim; YAML/AST válidos. Sólo fuente/wrapper, no Keystore. |
| Código de `c893108` | `/home/user/.cache/aura-closeout-venv/bin/python -m pytest -q -rs` | **125 passed, 8 skipped, 124 subtests passed in 6.21s**, log 17. Omisiones locales AAB por javac ausente; no se heredan a CI. |
| Workflows actuales | PyYAML + `ast.parse` de los scripts Python inline; `git diff --check` | Cinco YAML/AST válidos y diff limpio. No simula un APK ni una ejecución Android. |

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

Sí se recuperó un **fallo nuevo real**, sin atribuírselo al 27-oct:
[model `622b459`, job 128727819816](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42479398566/job/128727819816),
y volvió a observarse en [model `e8b2db7`, job 128730479644](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42480272202/job/128730479644).
Los pasos de dataset/splits y golden tests terminaron; el entrenamiento del
candidato fue rechazado por **el presupuesto de tamaño**, no un verde fingido:

```text
Training Aura mobile forest: 500 trees, max_depth=10, min_samples_leaf=512,
train=334761, val=64327, test=88219.
MOBILE_TRIAL trees=500 max_depth=10 observed_depth=10 min_samples_leaf=512
leaves=76255 bytes=7207922
Mobile preset still exceeds 4194304 bytes at max_depth=8 with aggressive pruning;
see tool/reports/mobile_size_trials.json. No base asset was changed.
```

Son contadores/salidas del entrenamiento, **no métricas independientes de
calidad**. Benchmark quedó omitido por rechazo previo; no se inventan FP/FN,
accuracy, latencia ni causa histórica. No se aumenta el límite de 4 MiB para
obtener verde ni se promueve 3.1.0. El modelo activo sigue intacto, 3.0.0 y SHA-256
`d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2`.

No hay en esta auditoría una evaluación externa independiente y verificable del
modelo activo. Un candidato que pase CI no queda automáticamente aprobado.

### SecureVault y formatos

`lib/secure_vault.dart` mantiene v9→v10, backup y `resetOnError=false`; conserva
secretos inválidos para evitar pérdida silenciosa. v10 usa RSA-OAEP/AES-GCM del
plugin. Las dos pruebas ahora instrumentadas siembran **EncryptedSharedPreferences
real v9** con AES256-SIV/AES256-GCM y exigen lectura v10, cifrado, limpieza del
legado y backup interrumpido. Conservaron sus aserciones, pero **su ejecución
Android está bloqueada por KVM**; tampoco hay prueba de Keystore físico. La
compilación de los nuevos APKs de test debe comprobarse aparte: no se confunde
la compilación de las 19 pruebas JVM con la de `androidTest`.
La cola de mutaciones cambió sólo en su liberación/propiedad entre schedulers;
los formatos y opciones de migración no cambiaron.

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
4. Proporcionar un destino Android autorizado y accesible por `adb`
   (`ANDROID_SERIAL`) para el nuevo paso de migración aislada; Codemagic falla
   si falta, sin sustituirlo por Robolectric. Para Actions, suministrar un runner
   con acceso KVM sin privilegios conforme a su política; el runner observado
   no lo tiene y no se alteran sus permisos desde este trabajo.
5. Comprobar toolchain, formato, análisis, tests sin omisiones AAB, migración,
   JNI, APK y su hash; comparar el SHA real del build antes de instalar.
6. Proporcionar dispositivo autorizado y servidor controlado para la matriz de
   tráfico; no se puede reemplazar ese acceso desde este sandbox. No desinstalar
   ni vaciar una instalación con datos para probar: el APK debug no es una
   migración productiva validada y el test de bóveda usa **otro applicationId**.

Actions sí está ejecutando en esta revisión. Solo si vuelve a responder
`Actions has been disabled for this repository`, el propietario debe ir a
**Settings → Actions → General → Allow all actions** y ejecutar manualmente
**Aura Flutter Quality** y **Aura Android Debug Build** sobre esta rama. No se
solicitan contraseñas, tokens, 2FA ni secretos en chat.

## 8. Criterios de terminado (instantánea previa al run posterior)

Se separan avances reales de aceptación final; los checks del próximo SHA y su
`SOURCE_COMMIT.txt` son la autoridad para ese candidato, no este historial.

- [x] `flutter pub get`, formato 58/0 y análisis limpio en `64167f8`; no sustituye su test Flutter fallido.
- [x] Guards y pytest/JDK de CI: `64167f8` confirmó 135 pruebas + 124 subtests y cero omisiones, incluidas ocho AAB reales.
- [x] JVM de credenciales/RFC 1929/ciclo de vida/correlación/recuperación: 19 pruebas sin migración de Keystore.
- [x] Primer C/JNI/NDK y APK debug real `e8b2db7`, publicado y con SHA-256 registrado.
- [x] Firma negativa/positiva con clave efímera y SBOM de `e8b2db7`.
- [x] Arranque compacto 320×568 sin overflow, con scroll y controles fijados, ejecutado en `1844ec8` y `64167f8`.
- [ ] `flutter test` completo del SHA posterior: falta confirmar la navegación coordinada; el único fallo `64167f8` está transcrito arriba.
- [x] APKs de instrumentación compilados y ELF/modelo del APK real verificados en `3e56b23`; no equivale a ejecutar AndroidKeyStore.
- [ ] Migración real Android instrumentada — **bloqueada por KVM/runner autorizado**.
- [ ] Codemagic ejecutado sobre el SHA final — requiere propietario y destino Android.
- [ ] APK del SHA final instalado en un dispositivo real sin pérdida de datos.
- [ ] VPN inicia/detiene y libera recursos en hardware.
- [ ] SOCKS5 autenticado conectado al forwarding TUN real.
- [ ] TCP/UDP/DNS/IPv4/IPv6 y fugas.
- [ ] Cambio de red y recuperación tras fallo, incluido callback de la misma red.
- [ ] IA con dataset/métricas reproducibles, tamaño aceptado y revisión independiente FP/FN; no promover 3.1.0.
- [ ] SecureVault/migración preserva datos en hardware.
- [x] Compatibilidad **documentada con límites**, no certificada universalmente.
- [x] README de producto/ingeniería y auditoría interna separados.

Existen APKs debug históricos identificados arriba, incluido `3e56b23`. **Funciones
verificadas en dispositivo: ninguna.** No se atribuyen a esos artefactos los cambios posteriores
ni una validación Flutter completa. No hacer merge, publicar ni declarar Aura
terminada mientras los criterios pendientes no tengan evidencia del SHA correcto.
