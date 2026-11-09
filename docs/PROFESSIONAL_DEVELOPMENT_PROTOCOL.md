# Protocolo de desarrollo profesional — Aura

**Versión:** 1.0  
**Fecha de adopción:** 2026-11-09  
**Objetivo:** Terminar Aura con calidad técnica, seguridad verificable y una experiencia de usuario profesional.

Este protocolo rige el trabajo de cierre. No sustituye las pruebas de aceptación ni convierte código compilado en protección verificada.

## 1. Reglas fundamentales

1. Revisar contexto, dependencias y efectos secundarios antes de modificar código.
2. Evitar cambios innecesarios y reescrituras sin justificación técnica.
3. No eliminar, omitir ni debilitar pruebas para conseguir una compilación verde.
4. Distinguir compilación, pruebas automatizadas, validación física y aceptación.
5. No presentar reglas, heurísticas o respuestas predefinidas como un LLM.
6. Proteger los datos existentes; no ejecutar migraciones destructivas sin respaldo y pruebas.
7. Actualizar la documentación después de cada fase.
8. Trabajar en ramas de desarrollo y cambios revisables.
9. No integrar cambios en `main` sin autorización expresa del propietario.
10. No declarar una fase terminada sin evidencia reproducible.

## 2. Ciclo obligatorio de cada modificación

### A. Diagnóstico
- Identificar y reproducir el problema.
- Localizar archivos, dependencias y contratos afectados.
- Revisar efectos secundarios y riesgos.
- Definir de antemano cómo se verificará la solución.

### B. Planificación
- Especificar el resultado esperado.
- Separar correcciones necesarias de mejoras opcionales.
- Documentar riesgos y criterios de aceptación.

### C. Implementación
- Realizar cambios pequeños y controlados.
- Mantener compatibilidad con el resto del proyecto.
- Proteger datos, permisos, claves y operaciones sensibles.

### D. Verificación
- Formato y análisis estático.
- Pruebas unitarias y de integración pertinentes.
- Compilación Android y revisión del artefacto.
- Pruebas en dispositivo físico cuando la función dependa del sistema operativo, hardware o tráfico real.

### E. Evidencias
- Registrar SHA de origen, archivos modificados y comandos ejecutados.
- Registrar resultados reales, incluidos fallos y omisiones.
- Documentar bloqueos, riesgos y trabajo pendiente.
- Actualizar el estado de la fase sin heredar resultados de otro SHA.

## 3. Estados oficiales de cada función

| Estado | Significado |
|---|---|
| Pendiente | Aún no implementada o no investigada. |
| Implementada | Existe código, pero falta verificar el comportamiento. |
| Verificada en CI | Pasó las pruebas automatizadas aplicables en un SHA identificado. |
| Verificada en dispositivo | Se comprobó en hardware físico autorizado y se conservaron evidencias. |
| Aceptada | Cumple todos los criterios de aceptación acordados. |

Una función no está terminada solo porque aparezca en la interfaz, exista código o la APK compile.

## 4. Orden de finalización

1. Auditoría del estado real del repositorio.
2. Corrección de errores críticos y regresiones reproducibles.
3. Verificación del motor de protección Android.
4. Pruebas reales del servicio VPN y del tráfico.
5. Verificación de SecureVault y migraciones criptográficas.
6. Validación del comportamiento real de Aura AI.
7. Revisión visual y de experiencia en Android 16.
8. Pruebas de rendimiento, batería y estabilidad.
9. Revisión de privacidad y seguridad.
10. Compilación de producción, firma y verificación del paquete.
11. Documentación y preparación para una futura publicación.

## 5. Reglas de seguridad

- No guardar claves privadas, tokens ni contraseñas en el repositorio.
- No distribuir artefactos firmados con claves de depuración.
- No debilitar autenticación, cifrado, integridad ni controles de permisos.
- No afirmar que la VPN protege tráfico que no haya sido observado y verificado.
- No borrar datos ante errores de migración para aparentar recuperación.
- No activar pagos, monetización ni publicación sin autorización.
- No publicar Aura sin revisar permisos, privacidad, licencias y comportamiento real.
- No solicitar al propietario secretos, códigos 2FA ni credenciales por chat.

## 6. Informe obligatorio por fase

Cada fase debe registrar:
- Objetivo y alcance.
- Diagnóstico y justificación.
- Archivos y componentes afectados.
- Pruebas y comandos ejecutados.
- SHA probado y enlaces a CI/artefactos.
- Resultados PASS / FAIL / NO PROBADO.
- Problemas pendientes y severidad.
- Riesgos conocidos.
- Criterios que faltan para su aceptación.

## 7. Línea base de cierre — 2026-11-09

La rama `main` observada al adoptar este protocolo apunta a `11d50fbc6944b00496499182b3b61e92c2259a31` (merge de PR #11). En esa revisión no se encontraron workflow runs ni estados de commit asociados directamente al SHA de merge; los resultados verdes documentados corresponden al HEAD de PR #11 `afab61f276f9d8a7d9ab2d4397290a2299f068d0`, no deben atribuirse automáticamente al SHA de merge.

La auditoría existente `AURA_FINAL_AUDIT.md` y el README describen límites aún abiertos:
- VPN: falta la matriz de tráfico real en el Redmi/Android físico (TCP, UDP, DNS, IPv4/IPv6, fugas, handover, revocación y ciclos start/stop).
- SecureVault: los APKs de instrumentación de migración se compilaron, pero la ejecución AndroidKeyStore no se completó por falta de KVM en el runner. BiometricPrompt no usa CryptoObject y no está vinculado criptográficamente a cada descifrado.
- IA: el agente de intenciones es un parser por reglas, no un LLM; el modelo móvil activo es 3.0.0. El candidato 3.1.0 fue rechazado por tamaño y no debe promoverse sin evaluación.
- Dispositivo y distribución: falta instalación/aceptación en hardware, benchmark físico y firma de producción verificada. Codemagic no se considera ejecutado sin un build identificable y logs del SHA correspondiente.

Esta línea base es una fotografía de la revisión; cualquier avance posterior debe actualizarse con nuevos SHAs y evidencias. No es una certificación ni un dictamen de release.

## 8. Regla final

Aura estará terminada cuando las funciones principales estén implementadas, verificadas y aceptadas con evidencia en el SHA y hardware objetivo; no simplemente cuando produzca una APK.
