# Aura: puntos de revisión antes de cambiar datos o seguridad

Base inspeccionada: `11d50fbc6944b00496499182b3b61e92c2259a31`. Esta es
una revisión estática parcial, no una certificación ni un sustituto del informe
completo de Julie. La rama añade cambios de infraestructura; no se ha alterado
ninguno de los mecanismos descritos aquí.

## P0: autenticación y SecureVault — CONFIRMADO / PARCIAL

`MainActivity.authenticateFingerprint` llama a `BiometricPrompt.authenticate`
sin `CryptoObject` y devuelve un booleano. `AgentController` guarda ese valor y
`splash_screen.dart` lo usa para avanzar en el arranque. `AuraSecureVault` lee
la clave maestra mediante `flutter_secure_storage`, sin recibir un objeto
criptográfico autenticado de ese prompt. Por tanto, el diálogo protege la
navegación normal, pero el código inspeccionado no demuestra que Keystore exija
esa autenticación para cada operación sobre los secretos. No se ha ejecutado
un ataque de canal falsificado ni se afirma que esté reproducido.

El vault tiene migración y backup configurados (`resetOnError: false`);
invalidar una clave o reescribir esos datos sin diseño de recuperación puede
hacer inaccesibles datos existentes. También existe un flujo explícito para un
dispositivo sin bloqueo local y otro de credencial del dispositivo. La política
futura debe decidir expresamente cómo compatibilizarlos con protección ligada
a biometría y con API 24–36, sin prometer recuperación si no existe.

**Revisión requerida antes de implementación:** especificar datos protegidos,
modelo de amenaza, política de biometría y credencial, recuperación tras cambio
de inscripción y pérdida de claves, migración reversible y condiciones para
conservar datos anteriores. No tratar un booleano Dart como autorización
criptográfica. Validar en Android real cancelación, bloqueo, llamada falsificada,
invalidez de clave y migración con datos previos; registrar límites de hardware.

## P1: persistencia del modelo — CONFIRMADO por inspección; fallo NO REPRODUCIDO

`lib/ai_brain.dart`, `_writeModelPair`, escribe temporales y renombra por
separado modelo, digest y firma. Si un rename posterior falla o el proceso se
interrumpe entre renames, no existe en ese método una transacción que restaure
los tres archivos anteriores. `_loadModel` verifica digest y firma y, al fallar,
activa reglas locales; no se ha demostrado que recupere el modelo anterior.
No se ha reproducido aún una interrupción real y no se afirma corrupción en
una instalación concreta.

`installDownloadedModel` verifica firma y digest antes de instalar; conservar
esas verificaciones y no cambiar la clave pública. Propuesta para revisión:
versiones completas en directorios separados, validadas antes de activar un
puntero de versión mediante una única operación atómica apropiada para Android,
retener la versión anterior y leer el formato existente durante una migración
no destructiva. El diseño debe evaluar durabilidad real, fallos en cada paso,
reinicio, concurrencia, rollback y limpieza sin perder el único modelo válido.
Requiere pruebas de fallos inyectados y de dispositivo antes de aplicarse.

## P1: credenciales temporales VPN — PARCIAL

`AuraVpnService.prepareTunnelConfiguration` escribe un YAML en `filesDir` con
credenciales efímeras; `discardTunnelConfiguration` lo elimina en varios caminos
normales y de error. `onCreate` no lo elimina. Android puede terminar el proceso
sin ejecutar `onDestroy`; por inspección no se garantiza limpieza ante esa
terminación. La exposición concreta en un dispositivo no se ha reproducido.
Una solución debe evaluar sincronización con el worker nativo y recuperación,
no registrar credenciales y probar inicio, fallo y muerte abrupta en dispositivo.

## JNI / compatibilidad — CONFIRMADO

El applicationId y namespace son `com.ciberdefensa.aura`, pero
`AuraCryptoSecure` está en `com.aura.cyberdefense` y el símbolo C exportado
contiene ese mismo nombre. `hev-jni.c` exporta el símbolo de `MainActivity` y
registra otros métodos dinámicamente con `RegisterNatives` en `JNI_OnLoad`.
Cambiar paquetes sin coordinar clases, registro, callbacks y símbolos puede
romper la carga. No se ha probado `UnsatisfiedLinkError` en esta revisión.
Verificar ABI y ejecutar las llamadas JNI en dispositivo antes de unificar.

## Evidencia de pruebas ejecutadas

En el entorno de revisión, con `cc`/GCC disponibles:

- `python3 tool/test_aura_sni_firewall.py`: PASS, 15 pruebas.
- `python3 tool/test_mapped_dns.py`: PASS, 6 pruebas.
- `python3 tool/test_tun_packet_filter.py`: PASS, 7 pruebas.
- `python3 tool/test_lwip_fragment_policy.py`: PASS, 5 pruebas.
- `python3 tool/test_verify_packaged_model.py`: PASS, 6 pruebas.

CI del commit `88a0167743acc8f37526ac1b47e9d4efc8bb4f67`:

- PASS: Flutter Quality; build APK debug, pruebas Kotlin, compilación de APKs
  aislados de migración y verificación de ELF de las cuatro ABI y del modelo.
  [Build Android](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42607341344).
- FAIL: la prueba real de migración Keystore no pudo iniciarse: el runner no
  disponía de acceso KVM no privilegiado. No equivale a una prueba ejecutada.
- FAIL: entrenamiento del candidato móvil: la configuración probada produjo
  7.128.733 bytes frente al límite de 4.194.304. No se cambió el asset base.
  [Pipeline del modelo](https://github.com/liendomaho-wq/Aura-V1.0/actions/runs/42607341405).
  No debe elevarse el límite ni relajarse el gate sin evaluación y revisión.

Son pruebas de host y CI, no de tráfico real. Las pruebas
físicas de tráfico siguen el protocolo `docs/ANDROID_TRAFFIC_VALIDATION.md` y
permanecen pendientes; también faltan pruebas de biometría, migración real y
comportamiento Android 14, 15 y 16. No se afirma ausencia de fugas.
