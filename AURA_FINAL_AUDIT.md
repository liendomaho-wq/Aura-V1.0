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

### Formato genuino de la navegación coordinada (`bd1dcef`)

El [quality 42484627880 / job 128743686193](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42484627880/job/128743686193)
falló en 39s por formato de **un** archivo; los widgets no se ejecutaron.
Se aplica su parche íntegro, no un formateador sustituto: 3823 bytes,
SHA-256 `fcc5ae8f048c5830b499dbe1a0e96e2217fc34d2f0203985f5bff26c369f77f5`,
un fragmento XZ/base64, ruta única `lib/screens/aura_core_screen.dart`.
Se verificaron manifiesto, longitud, SHA, ruta y `git apply --check` antes de
aplicarlo. Guards y 25 tests locales pasan después del parche; el full local
previo (`23-coordinated-scroll-local-python.log`) fue 127/8 omitidos/124 subtests,
no AAB local. No se debilita el gate de formato ni se atribuyen widgets a un
job que no llegó a ellos. La reejecución posterior se identifica en PR #11.

### `029efe1`: calidad real verde, sin declarar release

**Código fuente probado:** `029efe1908b151f3f3a6b588bbf525254d7e0ef7`.
[Quality 42485347770 / job 128745883851](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42485347770/job/128745883851)
terminó **success, 1m12s**. La API del run confirmó ese `head_sha`; checkout
usa explícitamente el HEAD de la PR, no una mezcla no identificada.

| Comando real en CI | Resultado observado |
|---|---|
| `flutter pub get` | Exit 0 |
| `dart format --set-exit-if-changed .` | 58 archivos, **0 cambios** (0.17s) |
| `python3 tool/test_verify_aab.py` | **8 tests OK** (2.611s), ninguno omitido |
| `python3 -m pytest -q -rs` | **135 pasan + 124 subtests**, **0 omitidos** (5.75s) |
| `flutter analyze --no-pub` | **No issues found** (5.6s) |
| `flutter test --no-pub` | **194 pasan / 0 fallan / 1 omitido** |

El omitido es la suite preexistente
`test/aura_inference_benchmark_test.dart`, anotada literalmente
`@Skip('requiere dispositivo/entorno local')`. No se añadió esta omisión ni se
borró ninguna aserción para conseguir verde. **No se ejecutó el benchmark**, ni
se deducen latencias, precisión, protección o compatibilidad de esos tests.
La ejecución cubre el test compacto sin overflow y el test Core original con
regreso al avatar por gesto real, estados VPN no verificables y revocación;
son pruebas de widgets/canales, **no forwarding Android real**.

Las anotaciones completas se conservaron localmente en
`029efe1-quality-annotations.json`. `git diff --exit-code 82db8e7a8c24557f2196e0b08ab4ecb69ad92b1c HEAD -- assets pubspec.yaml pubspec.lock`
salió 0: assets, `pubspec.yaml` y lock permanecen sin diferencias.
`sha256sum assets/model/aura_brain_model.json` volvió a dar
`d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2`.
El commit documental posterior no cambia ese código; su ejecución y artefacto
exactos se publican en el resumen de PR #11, sin heredar el hash de otro APK.

### `029efe1`: APK, instrumentación compilada y gates que siguen abiertos

[Android 42485347775 / build job 128745883763](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42485347775/job/128745883763)
terminó **success, 8m06s**, con JDK 17 / SDK 36 / NDK 28.2.13676358 reales:

```text
./gradlew :app:testDebugUnitTest --no-daemon
BUILD SUCCESSFUL in 3m 50s
JUnit: 19 tests / 0 failures / 0 errors / 0 skipped
./gradlew :app:assembleStorageMigration :app:assembleStorageMigrationAndroidTest --no-daemon
BUILD SUCCESSFUL in 1m 53s
275 actionable tasks: 269 executed, 6 up-to-date
flutter build apk --debug
Running Gradle task 'assembleDebug'... 72.5s
Built build/app/outputs/flutter-apk/app-debug.apk
APK SHA256=3876bee5c2cbe374e4fe3230b54bf53039df74dbdece747f42f7b98a80c20fa4
```

La inspección real del APK volvió a validar ELF/clase/máquina en **armeabi-v7a,
arm64-v8a, x86 y x86_64**. Los tamaños y SHA de las cuatro bibliotecas HEV son
idénticos a la tabla de `3e56b23` de arriba; no se infieren de una lista de ABIs.
Modelo/digest/firma empaquetados coinciden byte a byte con el checkout exacto.
No es prueba de instalación, llamadas JNI en un teléfono, forwarding ni soporte
16 KiB físico.

Artefacto [13619059672](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42485347775/artifacts/13619059672):
`aura-debug-029efe1908b151f3f3a6b588bbf525254d7e0ef7`.
ZIP **86005108 bytes**, digest ZIP
`942dd9b09f34d9e04b763066f74aaf76a154790cab86c33a95fe10de340a764a`.
El hash **APK** es `3876bee5c2cbe374e4fe3230b54bf53039df74dbdece747f42f7b98a80c20fa4`;
no confundirlo con el digest del ZIP. El archivo contiene `SOURCE_COMMIT.txt`
y `SHA256SUMS`; la evidencia del hash se calculó **en CI**, no en una descarga
local fingida. Es DEBUG de prueba, no actualización productiva autorizada.

La [migración instrumentada / job 128747851842](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42485347775/job/128747851842)
falló en 7s antes de ejecutar:

```text
This runner has no unprivileged KVM access. Provide a KVM-enabled runner; no root/device bypass is used.
```

El workflow Android **sigue en failure**, aunque su job de compilación sea
verde. No se sustituye Keystore por JVM ni se omite ese gate. Los tests de
migración están compilados, no ejecutados.

[Firma 42485347773](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42485347773)
completó sus tres jobs: guard `128745883724`, positivo con clave efímera
`128745883795` y SBOM `128745883658`, todos **success**. Esto no acredita una
clave de producción del propietario.

[Modelo 42485347779 / job 128745883847](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42485347779/job/128745883847)
terminó **failure, 7m46s**: candidato de 7207922 bytes frente al límite 4194304,
todavía excedido a profundidad 8 con poda agresiva. Golden y upload de reportes
pasaron; benchmark posterior no se ejecutó. No se ha promovido 3.1.0 ni cambiado
el modelo base. No se extrapola este rechazo al fallo histórico de octubre cuyo
log completo no fue recuperado.

Esta última actualización es **sólo documental** y conserva la evidencia del
código realmente probado `029efe1`. Tras publicarla se verifican otra vez los
checks y el APK del SHA documental; ese SHA y sus resultados exactos se fijan
en el resumen final de PR #11, sin otro ciclo de commits de resultados.

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

## 8. Criterios de terminado (código verificado: `029efe1`)

Se separan avances reales de aceptación final; los checks del próximo SHA y su
`SOURCE_COMMIT.txt` son la autoridad para ese candidato, no este historial.

- [x] `flutter pub get`, formato 58/0 y análisis limpio en `029efe1`.
- [x] Guards y pytest/JDK de CI: `029efe1` confirmó 135 pruebas + 124 subtests y cero omisiones, incluidas ocho AAB reales.
- [x] JVM de credenciales/RFC 1929/ciclo de vida/correlación/recuperación: 19 pruebas sin migración de Keystore.
- [x] C/JNI/NDK y APK debug real de `029efe1`, publicado y con SHA-256 registrado; no instalado en hardware.
- [x] Firma negativa/positiva con clave efímera y SBOM de `029efe1`; no credenciales productivas.
- [x] Arranque compacto 320×568 sin overflow, scroll y controles fijados, revalidado en `029efe1`.
- [x] `flutter test` de `029efe1`: 194 pasan / 0 fallan / 1 benchmark preexistente omitido; navegación coordinada ejecutada.
- [ ] Benchmark de inferencia en dispositivo: sigue omitido, sin latencias verificadas.
- [x] APKs de instrumentación compilados y ELF/modelo del APK real revalidados en `029efe1`; no equivale a ejecutar AndroidKeyStore.
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

Existe el APK debug de `029efe1` identificado arriba, además de los históricos. **Funciones
verificadas en dispositivo: ninguna.** No se atribuyen a esos artefactos los cambios posteriores
ni una validación Flutter completa. No hacer merge, publicar ni declarar Aura
terminada mientras los criterios pendientes no tengan evidencia del SHA correcto.


---

## 9. Actualización de evidencia — 2026-11-11 UTC

Esta sección prevalece sobre las afirmaciones históricas de las secciones 1, 7 y
8 cuando describen el estado de PR #26 y de la migración SecureVault.

- PR [#26](https://github.com/liendomaho-wq/Aura-V1.0/pull/26), head
  `d448e0cb7650cf00f94398229381a318c219380e`, fue fusionada mediante squash
  después de completar las verificaciones de Flutter Quality y Android Debug
  Build y la migración instrumentada. Commit de merge en `main`:
  `f361f7af50ebd9a6e24de6eabc4f873f82b6ea84`.
- La migración real de SecureVault v9→v10 ejecutó cinco pruebas instrumentadas
  en emulador Android 16. El job
  [130220913617](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42927314684/job/130220913617)
  terminó **completed / success**. El log muestra
  `Starting 5 tests on emulator-5554 - 16`,
  `Finished 5 tests` y `BUILD SUCCESSFUL in 4m 39s`.
  Esto valida ese conjunto de pruebas en emulador; no sustituye una prueba de
  migración en el Redmi ni certifica todos los escenarios de recuperación.
- El job [Aura Android Debug Build
  130217059998](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42927314684/job/130217059998)
  y Flutter Quality run **42927314799** constan como success para el candidato
  de PR. La APK generada en ese run validó compilación y empaquetado de las
  bibliotecas nativas del túnel; **no contiene aún el runtime llama.cpp enlazado
  ni DeepSeek funcionando**.
- El endurecimiento del parser de propuestas LLM rechaza claves JSON duplicadas
  (incluidas claves equivalentes escapadas), profundidad excesiva y colecciones
  demasiado grandes. Solo acepta propuestas de herramientas de lectura; no
  concede permisos ni ejecuta acciones.
- Estado de IA comprobado tras el merge: Dart define el contrato de canal
  `com.ciberdefensa.aura/llm`, pero `MainActivity` todavía no registra esos
  canales; no hay puente JNI de inferencia enlazado al APK, descarga privada
  verificada del GGUF ni generación real conectada a `AgentController`.
  El workflow de compilación llama.cpp sigue siendo una prueba de compilación
  aislada de archivos estáticos, no integración de producto.

### Dictamen actualizado

**La migración de bóveda en emulador y el endurecimiento de propuestas están
cerrados para el SHA indicado. Aura como producto sigue NO CERRADA y NO LISTA
PARA RELEASE.** No pedir al propietario que use Codemagic como prueba de DeepSeek
hasta que el runtime nativo, el ciclo de vida Kotlin/JNI, el servicio Dart y la
orquestación segura del agente estén realmente integrados y CI verifique la APK.
La validación física en el Redmi y el tráfico VPN extremo a extremo siguen
pendientes.

## 10. Fase 1 — runtime LLM local y NLU determinista (2026-11-11 UTC)

Esta sección sustituye las afirmaciones de la sección 9 sobre canales sin
registrar, ausencia de puente JNI y ausencia de commits. Toda la evidencia
siguiente está atada a commits concretos y a runs de GitHub Actions. Nada de
esta sección procede de una prueba en hardware físico.

### 10.1 Rama, commits y PR

- `main` remoto al iniciar esta fase: `3ba34c55d773c80bba9c3f78ffa31e373bdc5c88`.
- Rama `feat/llm-native-bridge`, PR
  [#29](https://github.com/liendomaho-wq/Aura-V1.0/pull/29), base `main`.
- Cuatro commits sobre `main`:
  - `147da0a` — runtime llama.cpp fijado, puente JNI, contrato Kotlin, plugin
    de orquestación, planificador Dart y gestor verificado del GGUF.
  - `ffd773b` — NLU tolerante a acentos y sinónimos sin perder fronteras.
  - `09bb350` — corrección de dos pruebas LLM (evento terminal tras cancelación
    y aserción de `intent.toEvent()`).
  - `83e4606` — sugerencias deterministas ante typos (`hintFor`).

### 10.2 Qué quedó integrado en el código

- JNI: `android/app/src/main/cpp/aura_llm/aura_llm_jni.cpp` con `JNI_OnLoad`
  que exige `com/ciberdefensa/aura/AuraLlmBridge` y la firma
  `(Ljava/lang/String;ILjava/lang/String;)V`; si falta, devuelve `JNI_ERR`.
- `CMakeLists.txt` enlaza `llama → ggml → ggml-cpu → ggml-base` y `Threads`,
  `dl`, `m`, `log`, `android`.
- Kotlin: `AuraLlmContract.kt` (canales, rangos y respuestas),
  `AuraLlmOperationRegistry.kt` (una sola generación activa, cancelación
  cooperativa), `AuraLlmBridge.kt` (carga JNI), `AuraLlmPlugin.kt`
  (orquestación) y registro en `MainActivity`.
- Gradle: descarga del tarball de llama.cpp fijada por commit
  `806b3c2bed44490233f1e8ffa403519370965fe7` y SHA-256
  `1c073db9bf1dfbaf7dfdfa27c0a1720147d593c6d704acf81a3c4470e6e95d37`,
  caché por stamp y compilación de las 4 ABIs.
- Dart: `LocalLlmPlanner` (prompt estricto, carga lazy, timeout de resolución,
  cancelación nativa, buffer acotado y revalidación con `LlmToolProposal.parse`),
  `AuraLlmModelManager` (descarga HTTPS a `.partial`, SHA-256 antes del rename
  atómico, single-flight) y la rama `AuraIntentKind.unknown` del
  `AgentController`.
- El modelo es entrada no confiable: solo produce propuestas read-only
  (`analyze_domain`, `audit_device`, `scan_apps`) que vuelven a pasar por el
  parser endurecido; nunca ejecuta herramientas ni concede confirmaciones.

### 10.3 Evidencia real de CI

Runs del commit `83e4606` (cabeza de la rama):

- [Flutter Quality 43049717136](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43049717136)
  — **completed / success**:
  - `dart format --set-exit-if-changed .`: 66 archivos, 0 cambios.
  - `flutter analyze`: `No issues found!` (7.9 s).
  - `flutter test`: **246 pruebas pasan, 1 omitida**.
  - Suite Python completa: **223 passed + 132 subtests passed** (10.76 s).
  - Guards de seguridad, plantilla VPN, JNI con fixtures y AAB firmados: OK.
- [Aura Android Debug Build 43049716539](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43049716539)
  — **completed / success** (ambos jobs):
  - Job de APK: `flutter build apk --debug` OK; las 4 ABIs exportan los JNI
    requeridos; JVM **40 pruebas, 0 fallos, 0 errores**.
  - Job de Keystore real en emulador Android 16: log con
    `Starting 5 tests on emulator-5554 - 16`, `Finished 5 tests` y
    `BUILD SUCCESSFUL in 11m 27s` para la migración instrumentada SecureVault
    v9→v10.
  - APK `app-debug.apk`:
    `6f81724accb0a823e65d42dcebca980521dc4f2d9ec6d7a9da3e91aefac89f43`;
    artefacto `aura-debug-83e4606…` de 96,476,260 bytes.
  - `libaura_llm.so` empaquetado (mismo tamaño que en `09bb350`, hash distinto:
    el enlace nativo **no es bit-reproducible** entre runs):
    - arm64-v8a: 6,573,040 bytes,
      `86a73767b43e82a2fb26dccd9650d0e35aff4533b9523333e87905e52bbb6e54`
    - armeabi-v7a: 4,798,484 bytes,
      `64967013d8033116a697c83427ae5e21d4146ab3f0fa5a176700235cfee45318`
    - x86: 7,062,420 bytes,
      `222b983867340a9c3c62e6b9c167ee2ee8a5fcf7932979c2ce536e081c5bec1a`
    - x86_64: 7,058,568 bytes,
      `ebd8c3f3947ed05fed091541888da0ba06f3bfcf19e2a278735ea2f9bf5e836c`
  - Modelo empaquetado verificado byte a byte:
    `d190dddf5ca0d55093a215463dfd98d81395d9282f3a93fb425a058853928ba2`.
- [Release signing integrity 43049716535](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43049716535)
  — **completed / success**.
- [Aura Model Dataset, Training and Benchmark 43049716570](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43049716570)
  — **completed / success**.

Runs del commit anterior `09bb350`, conservados como referencia:

- Flutter Quality
  [43044305962](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43044305962)
  — success, 241 pruebas + 1 omitida.
- Android Debug Build
  [43044305879](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43044305879)
  — success; APK `de46d7ad2cccddfe6572d05cac712166ac5fcfef8c4ee5d227416c5ff4da96d3`.
- Release signing integrity
  [43044305893](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43044305893)
  y Model Dataset
  [43044305986](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43044305986)
  — success.

### 10.4 NLU determinista y sugerencias

- La normalización de acentos se usa **solo para comparar**; las entidades, los
  textos de confirmación y las fronteras `;`, `:`, `\n` conservan el texto
  original. Así «analiza ejemplo.com» y «análiza ejemplo.com» producen la misma
  intención sin alterar el dominio capturado.
- Sinónimos y variantes de órdenes se resuelven antes de invocar al modelo. El
  LLM local solo recibe órdenes que el NLU no reconoce.
- `hintFor` compara la orden fallida contra frases canónicas y devuelve la más
  cercana. Es **asesoría**: se muestra en el warning como `suggested_command` y
  nunca se ejecuta ni se autoconfirma.
- Las respuestas del modelo siguen pasando por `LlmToolProposal.parse`
  (esquema de dos claves, allowlist read-only, rechazo de claves duplicadas,
  profundidad y colecciones acotadas).

### 10.5 Evidencia local (no sustituye CI)

- `python3 tool/test_llm_native_integration.py`: **25 guards OK** entre Dart,
  Kotlin, C++ y Gradle. No ejecutan Android, JNI ni inferencia.
- `python3 tool/check_apk_jni.py`: OK; los `.so` de las 4 ABIs exportan los
  símbolos JNI requeridos.
- `clang++ -std=c++17 -fsyntax-only -Wall -Wextra` sobre
  `aura_llm_jni.cpp`: exit 0 contra las cabeceras de la revisión fijada.
- `PyYAML` valida los workflows.
- `dart analyze` local sobre el parser: `No issues found!`.
- El harness Dart de NLU/sugerencias pasó los casos de acentos, sinónimos,
  fronteras y typos. El gate de formato se replicó con `languageVersion: 3.12`
  para coincidir con CI (66 archivos, 0 cambios), pero la ejecución oficial es
  la del run de CI citado.

### 10.6 Límites reales: lo que sigue abierto

- **No hay GGUF elegido, alojado ni fijado.** `AURA_LLM_MODEL_URL` y
  `AURA_LLM_MODEL_SHA256` no se definen en ningún workflow ni build; con el
  fail-closed actual, toda orden no reconocida termina en
  `modelNotConfigured`. La app no ejecuta inferencia real.
- **`prefetchModel()` no se llama en el arranque** y no existe UI de descarga,
  progreso, consentimiento ni control de espacio libre. Aunque se fijara un
  GGUF, la primera descarga ocurriría dentro del presupuesto corto de una orden
  y fallaría por timeout.
- **No hay inferencia observada en el TECNO LH7n** ni carga del modelo, primer
  token o cancelación real fuera de tests JVM/Dart simulados.
- **El enlace nativo no es bit-reproducible**: mismos tamaños, hashes distintos
  entre `09bb350` y `83e4606`. Los hashes identifican artefactos, no garantizan
  reproducibilidad byte a byte del `.so`.
- **La fusión a `main` no aprueba release.** El merge integra código verificado
  por CI; los criterios de producto de la sección 8 (hardware, VPN extremo a
  extremo, IA en dispositivo, Codemagic, SecureVault en dispositivo) siguen
  abiertos.

### 10.7 Dictamen de esta sección

La ruta completa Dart → canal → Kotlin → JNI → llama.cpp **compila, se empaqueta
y pasa los gates de CI** para `83e4606`, y el NLU determinista ya resuelve
órdenes con acentos, sinónimos y typos sin depender del modelo. Aura **no está
lista para release**: falta un GGUF verificado, el calentamiento/descarga desde
la app y la validación en hardware. El siguiente paso de producto es elegir y
alojar un GGUF con URL y SHA-256 fijos, exponer una acción de preparación con
progreso y verificar la primera generación y la cancelación en el TECNO LH7n.

## 11. Fase 2 — GGUF fijado y preparación local con consentimiento (2026-11-12 UTC)

Esta sección sustituye, para el working tree descrito, los pendientes de la
sección 10.6 sobre ausencia de GGUF fijado, falta de descarga desde la app y
falta de UI de preparación. No sustituye la validación en hardware ni un run de
CI: esos siguen abiertos.

### 11.1 Estado y alcance

- Rama local: `main`.
- HEAD base: `20a3fcefe0ac4c31ea128646737e8b16aac9661f` (merge del PR #29).
- Commits locales de esta fase: `b315f10` (pin, consentimiento, reanudación y
  verificación) y `3fc55bd` (guards CI alineados). **Push pendiente**: la
  credencial HTTPS de GitHub no está disponible en este entorno
  (`could not read Username for 'https://github.com'`).
- No se ejecutó un build Android completo ni un run de CI para estos cambios.
- No se observó inferencia en hardware.

### 11.2 Modelo fijado y verificado

- Repositorio: `unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF`.
- Revisión inmutable:
  `3cb4d15544a2a5e07439592b9a0965b6445fbd34`.
- Archivo: `DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf`.
- Tamaño: `1117321312` bytes.
- SHA-256:
  `f3bdf9cf31dee4b57ae4e455a1cb0d01b5c2c1b50d72d3112141c195506c2840`.
- Licencia: Apache-2.0; publicador: `unsloth`.

La descarga independiente completa terminó en `/tmp/aura-model.gguf` y
`sha256sum` devolvió exactamente el digest anterior con el tamaño exacto. El pin
está en `lib/llm/aura_llm_model_source.dart`; no hay descarga ni carga sin ese
digest.

### 11.3 Flujo implementado

- `AuraLlmModelManager` reanuda `.partial` con `Range`, reinicia si el servidor
  ignora el rango, respeta cancelación, valida espacio libre antes de abrir la
  conexión, limita el tamaño, verifica SHA-256 por bloques y solo renombra de
  forma atómica después de que el digest coincide.
- `AuraLlmSetupController` exige consentimiento explícito, persiste
  `aura.llm.consent.v1` y `aura.llm.prefetch.v1`, expone estados de descarga,
  verificación y carga, y conserva el prefijo al pausar.
- `LocalLlmPlanner.prefetchModel()` devuelve el resultado real del runtime;
  `unloadModel()` permite borrar o reemplazar el archivo. El path de órdenes del
  agente usa `resolveInstalledModel()`, que **no descarga**.
- `AuraStoragePlugin` expone `StatFs.availableBytes` por el canal
  `com.ciberdefensa.aura/storage`; falla cerrado si Android no responde.
- La UI incluye consentimiento, tamaño, SHA-256 corto, progreso/velocidad,
  pausa/reanudación, borrado con confirmación, precarga al iniciar, banner de
  preparación y anillo de capacidades del avatar.
- `main.dart` crea el planner, lo enlaza a `AgentController.instance` y expone
  el controlador mediante `AuraLlmSetupScope`.

### 11.4 Evidencia local ejecutada

- `flutter test`: **282 pruebas pasan, 1 omitida** (línea base previa: 246
  pasan, 1 omitida). Las nuevas cubren reanudación, cancelación, espacio,
  tamaño, digest, canal de almacenamiento, consentimiento, estados, UI y
  `unloadModel`.
- `flutter analyze --no-pub`: sin errores ni warnings. Solo quedan avisos
  informativos de deprecaciones del Flutter master local (`material.dart`,
  `activeColor`), que no son el SDK de CI.
- Verificación independiente del GGUF: tamaño y SHA-256 exactos, ver 11.2.
- No se modificó `pubspec.lock`; se revirtió el cambio producido por
  `pub get` local.

### 11.5 Lo que sigue abierto

- Ejecutar CI sobre el commit real y confirmar `dart format`, `flutter analyze`,
  `flutter test`, JVM y build Android.
- Probar la descarga real desde la app, la reanudación tras matar el proceso y
  el borrado en un dispositivo.
- Cargar el GGUF y observar primer token, cancelación y consumo de memoria en el
  TECNO LH7n.
- Confirmar que el runtime nativo acepta el archivo verificado y que la UI
  refleja "IA local lista" solo después de esa carga.

### 11.6 Dictamen de esta sección

El pin y el flujo fail-closed están implementados y cubiertos por pruebas
locales; la integridad del GGUF fue verificada de forma independiente. Aura
**sigue sin estar lista para release**: falta CI sobre estos cambios, push,
validación Android y observación de inferencia real en hardware.

## 12. Fase 3 — Interfaz centrada en la IA (2026-11-12 UTC)

La consola deja de ser un tablero de paneles y pasa a una composición única
alrededor de la presencia local de Aura:

- `AuraNeuralField` pinta un campo neuronal animado a pantalla completa (nodos,
  sinapsis y pulsos) que cambia con el estado real: escucha, razonamiento,
  escudo, advertencia o alerta. Respeta `disableAnimations`.
- `AuraPresence` concentra avatar, anillo de capacidades, saludo, estado del
  modelo local y métricas de sesión sin tarjetas ni contenedores rellenos.
- `AuraIntentConstellation` sustituye la rejilla de accesos por nodos de
  intención conectados: analizar, escudo, privacidad, IA local, informes,
  auditoría y ayuda.
- `AuraCommandFilament` reemplaza la barra de entrada por un filamento con
  pulso, microcopy de privacidad local y controles de voz/envío. El campo se
  deshabilita mientras Aura procesa o la consola no está autenticada.
- El hilo de eventos ya no usa burbujas: cada evento es una línea temporal con
  espina, nodo, hablante y texto seleccionable.
- El banner de preparación, la telemetría local, la explicación del veredicto,
  la auditoría de cobertura y las advertencias de accesibilidad se presentan
  como márgenes de señal con una regla lateral, sin `Card` ni fondos de panel.
- Se conservan las claves y textos exigidos por la suite: `vpn-toggle` como
  `TextButton`, `aura-event-list`, `aura-overview-scroll`,
  `local-telemetry-panel`, `Hola, soy Aura.`,
  `verdict-explanation-card-*` y el layout compacto 320x568.

Evidencia local: `flutter test` → **282 pasan, 1 omitida**; `flutter analyze`
sin errores ni warnings (solo infos de deprecaciones del master local); formato
limpio en los archivos tocados. No se validó visualmente en un dispositivo
físico ni se ejecutó CI para este rediseño.

## 13. Fase 4 — respuesta local, contexto adaptativo y build debug (2026-11-13 UTC)

Esta fase se ejecutó en la rama `fix/final-engineering-completion`, derivada de
`ae7dc63`. **Todavía no se hizo push ni merge a `main`**, por lo que ninguna de
estas correcciones tiene aún un build de CI propio.

### 13.1 Cambios implementados

- `LlmConversationReply` (`lib/agent/llm_tool_proposal.dart`) acepta únicamente
  `{"answer":"..."}`, con máximo 4096 caracteres, sin claves extra, caracteres
  de control ni salida mayor de 8192 bytes. La propuesta de herramienta se
  intenta primero; la respuesta es el fallback.
- `LocalLlmPlanner` devuelve `LocalLlmPlanStatus.answer` y un texto acotado
  cuando la orden no corresponde a una herramienta. El prompt pide español,
  prohíbe afirmar acciones ejecutadas y mantiene las tres herramientas de solo
  lectura.
- `AgentController` muestra la respuesta como `local_llm` no verificada y **no
  ejecuta ninguna herramienta**. La conversación es de un solo turno: no hay
  historial persistente ni memoria entre consultas.
- `AuraMemoryInfo` y `AuraStorage.memoryInfo()` exponen `total_bytes`,
  `available_bytes`, `threshold_bytes` y `low_memory` desde
  `ActivityManager.MemoryInfo` en `AuraStoragePlugin.kt`.
- `AuraLlmContextPolicy` selecciona contexto de 8K como base, con niveles hasta
  64K, presupuesto conservador de memoria, límite por `lowMemory` y fallback por
  mitades. `LocalLlmPlanner` reintenta hasta tres contextos menores y solo
  publica `effectiveContextTokens` cuando el runtime aceptó la carga.
- `main.dart` pasa al planner el tamaño real del GGUF configurado y la base de
  contexto; `AuraLlmModelSource.runtimeContextTokens` queda en 8192.
- `codemagic.yaml` añade el workflow manual `android-debug` para construir un
  APK instalable de prueba, ejecutar formato/análisis/tests, verificar las 3
  ABI de Flutter, los JNI, los assets del modelo y publicar `SHA256SUMS` y
  `SOURCE_COMMIT.txt`. No se ejecutó en Codemagic.
- El copy de `aura_core_screen.dart` deja de prometer “pensar, explicar y
  actuar” sin matices: ahora dice que el modelo responde y propone lecturas, y
  que cada acción requiere confirmación.

### 13.2 Evidencia local ejecutada

- `dart format --set-exit-if-changed .`: **84 archivos, 0 cambiados**.
- `flutter analyze --no-pub`: **No issues found!**
- `flutter test --no-pub`: **294 pasan, 1 omitida** (línea base de 282/1; +12
  pruebas nuevas de contexto, memoria, respuesta y controlador).
- `python3 tool/test_llm_native_integration.py`: **28 tests OK**, ampliado para
  verificar el contrato `memoryInfo`, `LlmConversationReply.parse` y la política
  de contexto.
- `tool/test_release_signing_policy.py`: 13 OK; `test_verify_packaged_model.py`:
  6 OK; `test_ci_run.py`: 7 OK; `test_install_android_ndk.py`: 6 OK;
  `test_vpn_config_template.py`: PASS; `test_gradle_wrapper_policy.py`: 1 OK.
- APK debug del commit `ae7dc63` (run `43374933380`, artifact
  `14014158629`): 193.660.826 bytes, SHA-256
  `8979a858c8a2f172951d267a24f2b93cf8a4a46677a251cefee60f6ea41ca60d`; las 4
  ABI y los ELF se verificaron con `readelf`. **Este APK es anterior a los
  cambios de esta fase y no debe presentarse como entrega final.**

### 13.3 Pendiente antes de la entrega

- Push de la rama, merge a `main`, CI final y descarga del APK del commit final.
- Ejecución manual del workflow CodeMagic `android-debug` y, por separado,
  `Release signing integrity`/`Aura Model Dataset...`; no hay token de
  Codemagic en el entorno local.
- Build Android/Kotlin de `memoryInfo` y del workflow nuevo: no existe SDK
  Android local.
- Prueba en el Redmi Note 15 Pro+ 5G: descarga, carga del GGUF, primer token,
  cancelación, latencia, RSS/PSS y estabilidad de 8K/16K/32K/64K.
- Inferencia real y calidad de respuesta: no observadas. La respuesta local es
  de un solo turno y no tiene memoria persistente.
- Firma de producción: ausente; el APK debug no es distribuible como release.

### 13.4 Hallazgo de empaquetado x86

La inspección del APK de `86af1be` encontró `libaura_llm.so`,
`libhev-socks5-tunnel.so` y `libdartjni.so` bajo `lib/x86/`, pero **no**
`lib/x86/libflutter.so`. Flutter `3.47.9` solo ofrece motores
`android-arm`, `android-arm64` y `android-x64`; el ABI x86 de 32 bits quedó
obsoleto en el proyecto. Un dispositivo x86 habría instalado la APK y fallado
al cargar Flutter.

Se corrigió la configuración para empaquetar solo `armeabi-v7a`, `arm64-v8a` y
`x86_64`, y se alinearon Gradle, `tool/verify_apk_jni.py`, GitHub Actions y
Codemagic. El workflow nativo aislado puede seguir compilando x86 como prueba
del motor, pero la APK ya no lo declara. Esto no afecta al Redmi ARM64 objetivo
y reduce el tamaño y la superficie del artefacto.

### 13.5 Dictamen de esta fase

Los cambios de Dart están implementados, formateados, analizados y cubiertos
por **294 pruebas locales**. La compilación Android, el APK final y CI se
cerraron en la sección 14; la ejecución en dispositivo y la inferencia real
siguen pendientes. El estado honesto es **implementado y validado hasta CI**,
no “IA local lista para release”.

## 14. Cierre verificable — commit `a6ff02e` (2026-11-13 UTC)

Esta sección cierra los pendientes de CI y artefacto de la fase 4. El commit
de código verificado es:

```text
a6ff02eabe66ba9b77051d76dae1c1a85c093497
fix(android): drop unsupported 32-bit x86 ABI
```

Después se añadió únicamente documentación. El APK final se reconstruyó sobre
`4c612d3dc07978f9ba30faff5c8a2bc0292ecd58`; ese commit no cambia código de la
app. Su CI volvió a pasar: Flutter Quality
[43404901563](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43404901563)
y Android Debug Build
[43404901634](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43404901634).

### 14.1 CI del commit final

Cuatro workflows terminaron en **success** sobre el SHA completo:

| Workflow | Run | Resultado |
| --- | ---: | --- |
| Aura Flutter Quality | [43398897135](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43398897135) | success |
| Aura Android Debug Build | [43398899937](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43398899937) | success |
| Release signing integrity | [43398897375](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43398897375) | success |
| Aura Model Dataset, Training and Benchmark | [43398897049](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/43398897049) | success |

El job Android ejecutó tests JVM VPN/SOCKS5, compilación de APKs aislados de
migración, build debug con NDK, verificación JNI de las tres ABI y la
**migración real v9→v10 de Keystore en un emulador Android 16**. No sustituye
una prueba de la app ni del GGUF en hardware.

`Release signing integrity` validó la política estricta y una firma release
efímera; **no** es una firma de producción ni publica un release. El pipeline de
dataset entrenó, evaluó, benchmarkeó y ejecutó golden tests, pero no promociona
automáticamente el modelo activo.

### 14.2 APK debug final

- Run: `43404901634`; artifact ID `14026454992`.
- Nombre: `aura-debug-4c612d3dc07978f9ba30faff5c8a2bc0292ecd58`.
- `SOURCE_COMMIT.txt`: `4c612d3dc07978f9ba30faff5c8a2bc0292ecd58`.
- APK: **186.102.478 bytes**.
- SHA-256: `29efb57f89d94c52053482f69df1f4732fe6b50c9864e4c74247fcd528994a3d`.
- ABIs empaquetadas: `armeabi-v7a`, `arm64-v8a`, `x86_64`; **sin x86 de 32
  bits**, porque Flutter `3.47.9` no publica ese motor.
- `tool/verify_apk_jni.py`: las tres ABI exportan `JNI_OnLoad`, las funciones
  HEV y todas las entradas de `AuraLlmBridge`.
- `libhev-socks5-tunnel.so`, `libaura_llm.so`, `libdartjni.so` y `libflutter.so`
  están presentes en las tres ABI; los ELF tienen clase y máquina correctas.
- Los assets `aura_brain_model.json`, `.sha256` y `.sig` coinciden byte a byte
  con el checkout.
- El APK está firmado con la clave debug de CI. Es un artefacto de instalación
  y prueba, **no un release distribuible**.

### 14.3 Lo que queda fuera de este cierre

- Instalación y arranque en el Redmi Note 15 Pro+ 5G; permisos, biometría,
  servicios VPN y estabilidad del proceso.
- Descarga real del GGUF desde la app, reanudación tras matar el proceso,
  verificación, carga y primer token.
- Medición de RSS/PSS, latencia, temperatura, OOM y estabilidad con 8K, 16K,
  32K y 64K. No se declara 64K operativo.
- Calidad y seguridad de las respuestas conversacionales; son de un solo turno,
  sin memoria persistente y no sustituyen verificaciones deterministas.
- Keystore/secretos de producción y publicación de un release firmado.
- Workflow CodeMagic `android-debug`: está declarado y validado
  sintácticamente, pero no se ejecutó por falta de acceso/token de Codemagic.

### 14.4 Dictamen final

- **Código y CI:** verificados para `a6ff02e`; Flutter Quality, Android Debug,
  migración Android 16, signing guard y dataset terminaron en success. El
  commit documental `4c612d3` también pasó Quality y Android Debug.
- **APK debug:** generado sobre `4c612d3`, descargado y validado
  estructuralmente; listo para instalación manual en ARM64, no probado aún en
  el dispositivo.
- **IA local:** implementada y cubierta por tests; inferencia real **no
  observada**. La conversación es acotada y de un solo turno.
- **Release:** **no listo**. Faltan firma de producción, pruebas físicas y
  validación de la IA en hardware.
