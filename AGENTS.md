# Aura — instrucciones obligatorias para agentes

Estas reglas aplican a cualquier agente humano o de IA que trabaje en este repositorio.

## Objetivo
Mejorar Aura, una aplicación Android de ciberdefensa local sin root, mediante cambios pequeños, revisables y verificables. La documentación del producto y `docs/agents/` complementan estas reglas.

## Límites de autoridad
- Nunca escribir, hacer push ni fusionar directamente en `main`.
- Trabajar exclusivamente en una rama propia `agents/<rol>/<tarea-corta>` o en la rama indicada por el coordinador.
- Entregar el trabajo mediante Pull Request hacia `main`; mantenerla abierta y en borrador hasta revisión.
- No fusionar, cerrar ni cambiar la base de una PR sin autorización explícita del propietario.
- No crear, rotar, copiar ni publicar secretos, tokens, claves privadas, certificados o datos personales.
- No activar pagos, telemetría, servicios remotos, permisos invasivos ni funciones de distribución sin autorización.

## Reglas de ingeniería
- Leer primero el README, el protocolo de desarrollo vigente y el código relacionado con la tarea.
- Antes de editar, informar objetivo, archivos previstos, dependencias, riesgos y pruebas.
- Limitar los cambios al alcance aprobado. No hacer refactors oportunistas.
- No debilitar, borrar, saltar ni reescribir pruebas para conseguir un CI verde.
- No sustituir pruebas reales por mocks y luego declarar la función verificada.
- No presentar reglas, heurísticas, clasificadores ML ni parsers como un LLM.
- No afirmar que una VPN protege tráfico real por el mero hecho de iniciar un servicio.
- No alterar formatos criptográficos, claves, migraciones o autenticación sin plan de compatibilidad, rollback y pruebas de datos.
- No modificar endpoint de modelos, firma o clave pública sin verificar propiedad y proceso de rotación.
- No agregar dependencias sin justificar mantenimiento, licencia, tamaño, seguridad y compatibilidad Android.

## Evidencia obligatoria
Cada PR debe indicar:
1. Qué se cambió y por qué.
2. Archivos y componentes afectados.
3. Comandos y pruebas ejecutados, con resultado.
4. SHA del commit probado y enlaces de CI.
5. Qué no se pudo probar y por qué.
6. Riesgos residuales y pasos de validación en dispositivo.

Usa solo estos estados: **Pendiente**, **Implementada**, **Verificada en CI**, **Verificada en dispositivo**, **Aceptada**. Una compilación no demuestra funcionamiento en un teléfono. Una prueba no ejecutada debe figurar como **NO EJECUTADA**, nunca como PASS.

## Revisión
El agente autor no puede aprobar su propia entrega. La revisión final corresponde al coordinador y al propietario. Si falta evidencia, hay cambios fuera de alcance o falla una prueba, la PR no está lista para fusionarse.
