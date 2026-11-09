# Equipo multiagente de Aura

Este directorio contiene seis perfiles de trabajo. Son **instrucciones especializadas**, no seis procesos autónomos ya conectados. Desde el navegador móvil, el propietario puede abrir sesiones de agentes compatibles, copiar la tarea asignada y entregar el resultado por GitHub Pull Request.

## Los seis roles
1. [Arquitectura y coordinación](roles/architecture.md)
2. [Android y Kotlin](roles/android-kotlin.md)
3. [Flutter y experiencia visual](roles/flutter-ui.md)
4. [IA y modelos](roles/ai-models.md)
5. [Seguridad y privacidad](roles/security-privacy.md)
6. [QA, CI y documentación](roles/qa-ci-docs.md)

## Flujo de trabajo
1. El coordinador divide una tarea aprobada en entregables pequeños.
2. Cada agente recibe un solo objetivo, archivos permitidos, restricciones y criterios de aceptación.
3. El agente inspecciona el estado actual del repositorio y crea una rama propia: `agents/<rol>/<tarea-corta>`.
4. El agente ejecuta las pruebas pertinentes y registra sus resultados reales.
5. El agente abre una PR hacia `main`, preferiblemente en borrador, usando el contrato de PR del repositorio.
6. CI ejecuta las verificaciones automáticas disponibles.
7. Un revisor distinto del autor examina el diff, las pruebas, los logs y los riesgos.
8. El propietario decide si autoriza la fusión. Sin esa autorización, la PR permanece sin fusionar.

## Operación desde teléfono y coste
- No se requiere ordenador ni Codex CLI para seguir el flujo documental.
- GitHub Mobile o github.com sirven para consultar ramas, PRs y ejecuciones.
- Las instrucciones pueden copiarse a agentes que funcionen en navegador. Cada proveedor puede tener límites gratuitos propios; este repositorio no promete uso ilimitado ni agentes gratuitos.
- GitHub Actions valida código; no genera por sí solo código con IA.
- No se configuran claves de API ni se envía código a servicios externos automáticamente.

## Estado de la conexión
La entrega por PR es el puente compartido y auditable. Los agentes externos no transmiten automáticamente su razonamiento a ChatGPT. El coordinador revisa los artefactos publicados en GitHub.

## Convención de ramas
`agents/<rol>/<tarea-corta>`

Roles permitidos: `architecture`, `android`, `flutter`, `ai`, `security`, `qa`.

## Seguridad de la rama principal
Al iniciar esta infraestructura, GitHub reportó `main` con `protected=false`. Esta PR no cambia la configuración administrativa. El propietario debe habilitar protección de rama o un ruleset desde Settings → Rules → Rulesets, exigiendo PR y checks antes de aceptar cambios. Hasta entonces, el equipo aplica una prohibición operativa estricta de escribir o fusionar en `main`.
