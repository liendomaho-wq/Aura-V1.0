# Guía de operación multiagente desde el teléfono

## Objetivo
Permitir que el propietario dirija seis especialidades de Aura usando un navegador móvil y GitHub como registro compartido, sin depender de una computadora.

## Preparación con agentes conectados
1. Conectar Jules a GitHub y autorizar únicamente `liendomaho-wq/Aura-V1.0`.
2. Abrir Jules desde el navegador del teléfono y crear tareas usando los seis perfiles de `agents/roles/`.
3. Ejecutar hasta tres tareas simultáneas por oleada; completar las otras tres en la siguiente oleada para respetar el nivel gratuito documentado.
4. Cada tarea debe trabajar en una rama separada y entregar una PR hacia `main`; nunca aceptar auto-merge.
5. Instalar CodeRabbit en el repositorio público para una revisión automatizada adicional de cada PR.
6. Compartir los enlaces de las PR aquí para la auditoría final de ChatGPT.
7. Consultar `PROVIDER_SETUP.md` para pasos y límites.

## Plantilla breve para iniciar un agente
Copia el siguiente texto y completa los campos:

> Actúa como el agente especialista descrito en [ENLACE AL PERFIL]. Repositorio: https://github.com/liendomaho-wq/Aura-V1.0. Tarea: [OBJETIVO]. Alcance permitido: [ARCHIVOS/MÓDULOS]. No escribas ni fusiones en main. Crea una rama agents/<rol>/<tarea>, inspecciona el código antes de editar, informa riesgos y pruebas, realiza solo cambios necesarios y abre una Pull Request hacia main. No debilites pruebas ni presentes funciones simuladas como reales. Si no puedes ejecutar una prueba, marca NO EJECUTADA y explica por qué. No publiques secretos.

## Revisión desde el teléfono
- GitHub → Pull requests → abrir la PR.
- Revisar pestañas Conversation, Commits, Files changed y Checks.
- Comparar el SHA probado con el SHA actual de la rama.
- Leer los logs de jobs fallidos o marcados como skipped.
- No aprobar ni fusionar hasta que la revisión técnica independiente esté completa.

## Qué puede automatizarse gratis y qué no
GitHub Actions puede ejecutar pruebas, análisis y validaciones según los límites de uso del plan y del repositorio. No ejecuta por sí mismo un modelo de IA que programe. Los agentes de navegador pueden tener planes, límites y políticas de uso distintos. Esta configuración no crea cuentas, no inicia sesiones de terceros, no compra planes ni configura API keys.

## Protección de main — acción manual pendiente
La consulta de GitHub realizada al preparar esta guía informó que `main` no tenía protección activa. La conexión usada para preparar esta PR no ofrece una acción para cambiar esa configuración. El propietario debe abrir:
Settings → Rules → Rulesets → New ruleset → Branch ruleset
y configurar como mínimo:
- Target branch: `main`.
- Require a pull request before merging.
- Require status checks to pass (seleccionar los checks reales después de que se ejecuten).
- Block force pushes.
- Restrict deletions.
- No permitir bypass salvo que el propietario decida expresamente lo contrario.

No activar nombres de checks inventados: elegir los que aparezcan en GitHub tras CI. En cuentas/planes donde alguna regla no esté disponible, mantener la política de PR obligatoria y revisar manualmente. Esta guía no afirma que la protección ya esté activada.
