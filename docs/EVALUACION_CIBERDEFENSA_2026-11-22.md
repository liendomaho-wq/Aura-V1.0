# Evaluación de ciberdefensa de Aura — 2026-11-22

## Puntaje

**58 / 100** de madurez de ciberdefensa (rango honesto: 55–60).

No es una certificación ni una comparación con un EDR comercial. Es una
estimación de ingeniería basada en lo que el código hace hoy, lo que verifica
CI y lo que todavía no puede hacer en Android con permisos ordinarios.

| Dimensión | Peso | Puntaje | Por qué |
| --- | ---: | ---: | --- |
| Control de red y prevención | 20 % | 65 | VPN local, DNS/SNI, bloqueo de DoH/QUIC, blocklists con SHA-256 y verificación RS256 opcional del manifiesto. La firma aún no está activa en una compilación publicada. |
| Detección y correlación | 20 % | 60 | Bosque local de 500 árboles, correlador de 10 minutos, postura, permisos, firmas y ofuscación. QUIC/ECH/IP directa siguen siendo puntos ciegos. |
| Respuesta y contención | 15 % | 40 | Bloqueo DNS y aislamiento de emergencia reales; no hay contención por app, playbooks ni eliminación automática. |
| Evidencia y gestión de casos | 10 % | 50 | Actividad en vivo, auditoría cifrada y casos con evidencia. Ya persisten cifrados con decisión, tope y retención; faltan estados de flujo y validación en dispositivo. |
| Integridad y actualizaciones | 10 % | 55 | Modelo RSA/SHA-256, feeds con digest y firma RS256 del manifiesto implementada con rotación; falta activarla, canal de actualización de código y autorreparación. |
| Privacidad y resistencia a abuso | 10 % | 80 | Todo local, sin telemetría, confirmaciones explícitas, guardas de inyección y límites de argumentos. |
| Cobertura de plataforma | 5 % | 35 | Solo Android, permisos ordinarios, sin Device Owner, sin iOS. |
| Ingeniería y verificación | 10 % | 62 | 389 pruebas Flutter, 239 de Python, analyze y gates de CI; pantalla monolítica, singletons y ausencia de pruebas de widget/dispositivo. |

Ponderado: **57,5 → 58**. Las mejoras de esta iteración no suben el puntaje
porque la firma sigue sin clave publicada y no hubo validación en el POVA 5.

## Progreso posterior a la evaluación

- **Casos persistentes:** `SecureVault` guarda hasta 200 casos, retención de 30
  días, decisión `abierta`/`descartada`, restauración y purga global verificable.
  La hoja conserva el historial completo y muestra solo 40 casos por vista.
- **Firma del manifiesto:** verificación RSA/SHA-256 con `key_id`, rotación de
  varias claves y fallo cerrado cuando hay claves configuradas. Herramienta
  `tool/sign_blocklist_manifest.py` y 5 pruebas Python. Sin
  `AURA_BLOCKLIST_MANIFEST_PUBLIC_KEYS` sigue el modo heredado con advertencia.
- **CI:** `Aura Flutter Quality` en 389 pruebas Flutter (1 omitida), 239 pruebas
  Python, analyze limpio y format limpio. `Aura Android Debug Build` compila el
  APK debug y el servicio Kotlin. `sbom` ahora instala el NDK declarado.

## Lo que ya es sólido

- El tráfico no se envía a un servidor de Aura: el túnel y el análisis viven en
  el dispositivo.
- Las acciones destructivas exigen confirmación explícita y pasan por guardas
  de ejecución.
- El modelo local se verifica con RSA y SHA-256; si falla, cae a reglas locales.
- Hay detección real de DGA/phishing, postura, permisos, firmas y ofuscación.
- La actividad muestra lo que ocurrió, sin progreso simulado.
- El corpus conversacional y las pruebas de seguridad son regresiones estrictas,
  no demostraciones.

## Recomendaciones prioritarias

### P0 — antes de llamarlo «sistema de amenazas»

1. **Firmar el manifiesto de blocklists** con una clave pública embebida y
   rotación. Infraestructura implementada (`AURA_BLOCKLIST_MANIFEST_PUBLIC_KEYS`,
   RS256, `.sig`, rotación y herramienta `tool/sign_blocklist_manifest.py`);
   **no está activa** hasta configurar una clave y publicar el `.sig`. Sin
   configurar sigue el modo heredado con advertencia.
2. **Persistir casos cifrados** con decisión (`abierta`/`descartada`),
   retención de 30 días, tope de 200 y borrado global verificable. Hecho; faltan
   estados `en revisión`/`mitigada` y la prueba en el POVA 5.
3. **Playbooks de respuesta** por caso: contener en DNS, aislar la red, abrir la
   ficha de la app o lanzar el desinstalador del sistema. Nunca desinstalar en
   silencio.
4. **Pruebas de widget, golden e integración** para actividad, amenazas y núcleo;
   presupuesto de rendimiento medido en el TECNO POVA 5.
5. **Mapa de cobertura visible**: decir en la interfaz qué no se puede ver (QUIC,
   ECH, IP directa) y qué implica.

### P1 — siguiente nivel

6. **Análisis estático local de APK**: manifiesto, certificados, cadenas
   sospechosas, hashes conocidos; sin subir el APK ni datos del usuario.
7. **MITRE Mobile** por caso, con explicación y acción recomendada.
8. **Actualización firmada con manifiesto, canary y rollback**; autorreparación
   de modelo/configuración corruptos.
9. **Aprendizaje local de falsos positivos**: descartar un caso ajusta la
   allowlist del dispositivo, no un modelo remoto.
10. **Reducir el monolito**: extraer despacho, voz y presentación de
    `aura_core_screen.dart`; inyectar dependencias en lugar de singletons.

### P2 — madurez de plataforma

11. **Device Owner / modo empresarial** para controles que Android no concede a
    una app ordinaria.
12. **Fuzzing y red team** de parsers, feeds y túnel; SBOM y análisis de
    dependencias en CI.
13. **Inteligencia firmada opcional** (IOC de dominios/hashes) con consentimiento
    y sin historial de navegación.
14. **iOS** solo si el producto lo justifica; no se puede prometer paridad con
    el modelo de permisos actual.

## Lo que no recomiendo

- **Modificar código en ejecución**: rompe la firma, la integridad y la cadena de
  suministro. La automejora debe ser un pipeline supervisado con CI y revisión.
- **Desinstalar o detener apps automáticamente**: Android no lo permite sin
  privilegios especiales; prometerlo sería una simulación.
- **Inspeccionar TLS**: convertiría a Aura en un intermediario y aumentaría el
  riesgo para el usuario.
- **Telemetría en la nube**: contradice la propuesta de privacidad y no es
  necesaria para mejorar el producto.

## Ruta a 70–75

Si se completan P0 y P1 con pruebas y validación en dispositivo, el puntaje
estimado sube a **70–75**: se gana en respuesta, evidencia, integridad y
cobertura, sin cambiar la promesa de privacidad.

La validación en un TECNO POVA 5 sigue siendo obligatoria antes de afirmar que
cualquiera de estos controles funciona en producción.
