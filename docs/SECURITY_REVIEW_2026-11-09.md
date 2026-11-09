# Revisión de seguridad inicial — Aura

**Fecha:** 2026-11-09  
**Base revisada:** `main` en `11d50fbc6944b00496499182b3b61e92c2259a31`  
**Dictamen:** revisión parcial de fuente; no es una certificación ni una prueba de penetración.

## 1. Origen externo de actualizaciones del modelo — pendiente de confirmar

### Evidencia

En `lib/agent/aura_tools.dart`, las tres URL de actualización están fijadas a:

- `https://yojamm16-boop.github.io/Aura-V1.0/model/aura_brain_model.json`
- `https://yojamm16-boop.github.io/Aura-V1.0/model/aura_brain_model.json.sha256`
- `https://yojamm16-boop.github.io/Aura-V1.0/model/aura_brain_model.json.sig`

El repositorio principal del producto es `liendomaho-wq/Aura-V1.0`; el repositorio público que corresponde al hostname es `yojamm16-boop/Aura-V1.0`, bajo otra cuenta GitHub. El README remoto indica que publica artefactos del modelo mediante GitHub Pages. En esta revisión no fue posible inspeccionar el directorio publicado desde la rama principal ni verificar los bytes del endpoint Pages.

La app valida la firma RSA usando la clave pública embebida en `lib/crypto/aura_crypto_layer.dart` (con posibilidad de override de build) y comprueba SHA-256 antes de instalar. La validación de firma reduce el riesgo de aceptar un modelo alterado sin la clave privada correspondiente. Este hallazgo **no demuestra falsificación, compromiso ni una vulnerabilidad explotable**.

### Riesgo y acciones requeridas

La autoridad del publicador, custodia de la clave privada, proceso de rotación/revocación y continuidad del hosting no están documentados en el repositorio principal. Antes de release se debe:

1. Confirmar que la cuenta externa y el GitHub Pages son infraestructura autorizada y controlada por el propietario de Aura.
2. Confirmar quién custodia la clave privada correspondiente a la clave pública fijada y cómo se protege.
3. Verificar en un entorno reproducible que modelo, digest y firma publicados corresponden al modelo 3.0.0 aprobado.
4. Documentar continuidad/recuperación del endpoint.
5. Si el origen no está autorizado, migrar a hosting controlado por el propietario sin cambiar ni relajar la verificación criptográfica; cualquier rotación de clave requiere un proceso explícito y compatible.

**Estado:** pendiente de confirmación del propietario. No cambiar endpoint, clave pública ni modelo hasta resolver la titularidad.

## 2. Autenticación biométrica de SecureVault — hardening pendiente

La implementación de `MainActivity.authenticateFingerprint` invoca `BiometricPrompt.authenticate(promptInfo)` sin `CryptoObject`. La política `SECURITY.md` y el README ya describen correctamente que el prompt abre la consola, pero no vincula criptográficamente la autenticación a cada operación de descifrado.

No se cambió este comportamiento. Añadir `CryptoObject` no es una modificación cosmética: requiere diseñar la clave Android Keystore, autorización por uso, invalidación, fallback de credencial del dispositivo, recuperación y migración sin perder datos de SecureVault v9/v10. Debe tratarse como trabajo criptográfico independiente, con pruebas AndroidKeyStore reales y un plan de compatibilidad antes de tocar producción.

**Estado:** limitación conocida y documentada; pendiente de diseño y ejecución en Android real.

## 3. Bloqueos de aceptación ya registrados

Los siguientes puntos continúan pendientes según `AURA_FINAL_AUDIT.md`, `docs/ANDROID_TRAFFIC_VALIDATION.md` y `docs/RELEASE_AND_DEVICE_VALIDATION.md`:

- Prueba de tráfico VPN extremo a extremo en un Android físico: TCP, UDP, DNS, IPv4/IPv6, fugas, cambio de red, revocación, parada y recuperación.
- Ejecución real de las pruebas instrumentadas de migración v9→v10 con AndroidKeyStore. La compilación de APKs de instrumentación no es ejecución; el runner CI previo no tenía KVM.
- Benchmark y evaluación del modelo en el dispositivo objetivo. El modelo activo permanece en 3.0.0; no promover 3.1.0 por el rechazo de tamaño ni inventar métricas.
- Build Codemagic sobre el SHA final y firma productiva verificada. Los artefactos debug no se distribuyen.

## 4. Límites de esta revisión

Esta revisión se hizo leyendo los archivos fuente publicados en GitHub. No se ejecutaron Flutter, Gradle, Android Emulator, AndroidKeyStore, Codemagic ni pruebas de tráfico físico desde esta sesión. Los resultados automatizados existentes deben atribuirse al SHA exacto que los produjo, no al commit de merge si no se ejecutaron sobre él.
