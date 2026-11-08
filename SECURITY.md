# Política de seguridad — Aura Mobile Defens

## Propiedad intelectual y licencia propietaria

Aura Mobile Defens se distribuye bajo los términos del [contrato de licencia propietario](LICENSE): Copyright (C) 2026. Todos los derechos reservados. El permiso concedido se limita a visualizar, revisar y auditar el código de este repositorio.

Sin autorización expresa y por escrito del titular de los derechos, la licencia prohíbe modificar, traducir, adaptar o crear obras derivadas; distribuir, vender, sublicenciar o alquilar el código fuente o los binarios; y recrear, duplicar, clonar o renombrar el proyecto para su explotación comercial o distribución pública bajo otra marca. La publicación del repositorio permite la revisión y auditoría, pero no concede una licencia de reutilización, redistribución ni explotación.

Estas condiciones se describen para informar del alcance de la licencia del proyecto y no sustituyen asesoramiento jurídico.

## Protecciones técnicas y límites

La arquitectura aplica los controles siguientes. Describen las medidas presentes en el código; no constituyen una garantía de protección absoluta.

1. **Reducción de remanencia de claves en memoria.** En Android, `aura_secure_mem_clear` sobrescribe con ceros los buffers nativos de clave AES de 32 bytes y de IV de 16 bytes, y el puente JNI limpia también los arreglos mutables que controla. Kotlin y Dart limpian sus arreglos mutables en las rutas implementadas. El descifrado AES se delega al proveedor JCE del sistema desde el puente JNI. No es posible garantizar desde la aplicación la sobrescritura física de todas las copias internas del proveedor, del runtime, del sistema operativo o de valores inmutables. Véanse [aura_crypto_secure.c](android/app/src/main/cpp/aura_crypto_secure.c) y [AuraCryptoSecure.kt](android/app/src/main/kotlin/com/aura/cyberdefense/AuraCryptoSecure.kt).

2. **Autenticidad de actualizaciones mediante RSA.** La aplicación verifica la firma RSA-2048 PKCS#1 v1.5 con SHA-256 del modelo antes de instalarlo, usando la clave pública DER proporcionada al compilar mediante `AURA_PUBLIC_KEY`. Una verificación ausente o fallida no valida el modelo y activa el comportamiento conservador definido por la aplicación. El hash SHA-256 detecta cambios, pero por sí solo no autentica el origen. La clave privada de firma debe mantenerse fuera del repositorio y del cliente. Véanse [aura_crypto_layer.dart](lib/crypto/aura_crypto_layer.dart) y las instrucciones de compilación en [README.md](README.md).

3. **Inspección nativa TLS SNI.** El firewall C inspecciona el ClientHello TLS y puede rechazar conexiones que coincidan con las reglas SNI instaladas, antes de reenviar ese tráfico a través del túnel. Los eventos de bloqueo se comunican al nivel Android para auditoría y notificación. Esta inspección no descifra TLS ni cubre universalmente DNS cifrado, SNI cifrado (ECH), IPv6, DoH/DoT, resolvedores personalizados u otros protocolos; la cobertura depende del tráfico visible para el túnel y de las reglas configuradas. Véanse [aura_sni_firewall.c](android/app/src/main/cpp/aura_sni_firewall.c) y [hev-socks5-session-tcp.c](android/app/src/main/cpp/hev-socks5-tunnel/src/hev-socks5-session-tcp.c).

## Integridad del cliente y depuración USB

`AuraAntiTampering.inspect` conserva `adbEnabled` como dato informativo y la
clave de compatibilidad `adbBlocked=false` que consume Dart. Activar opciones
de desarrollador o depuración USB no es evidencia de manipulación y no debe
apagar la VPN. Se mantienen la validación de firma, la detección de depurador
adjunto en builds no debug y las señales de instrumentación; si no se puede
inspeccionar el mapa del proceso, el informe no confirma integridad. El fallback
de firma local solo se permite en debug sin una lista de certificados configurada.

Estas comprobaciones se ejecutan en el cliente y **no son un límite de
seguridad**: un proceso o sistema comprometido puede modificarlas o esquivarlas.
No demuestran que un teléfono esté libre de malware. `BiometricPrompt` se usa
actualmente como puerta de interfaz, sin `CryptoObject`; no se afirma que la
autenticación biométrica esté ligada criptográficamente a cada descifrado de
SecureVault. Cambiar ese contrato requiere autorización y un diseño de migración
que conserve los datos existentes.

## Reporte privado de vulnerabilidades

No publiques detalles de una vulnerabilidad, credenciales, claves, datos personales ni un exploit en un issue o pull request público. Comunica el hallazgo de forma privada al mantenedor principal mediante un canal directo cuya identidad hayas verificado. Incluye los pasos mínimos para reproducirlo, el componente afectado, el impacto observado y, si existe, una mitigación; no incluyas secretos ni datos de terceros.

El repositorio no publica aquí una dirección de contacto ni ofrece un programa formal de recompensas. No presupongas autorización para acceder a sistemas, cuentas, dispositivos o servicios ajenos al código y entorno que tienes permiso expreso para evaluar.
