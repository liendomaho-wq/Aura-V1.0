# Proveedores gratuitos para el equipo multiagente de Aura

Fecha de verificación: 2026-11-09. Los planes y cuotas pueden cambiar; revisar siempre los enlaces oficiales antes de lanzar lotes de trabajo.

## Arquitectura aprobada

- **Jules (Google): agente ejecutor de código desde navegador.** Se conecta al repositorio, prepara un entorno virtual aislado, ejecuta tareas y puede proponer cambios mediante PR.
- **CodeRabbit: revisor automático de PRs para repositorios públicos.** Detecta posibles problemas y comenta en la PR; no se considera un agente de implementación ni una aprobación humana.
- **ChatGPT: coordinador y auditor final.** Divide trabajo, revisa diffs, evidencia, riesgos, CI y conflictos; no aprueba ni fusiona en nombre del propietario.
- **GitHub Actions: validación reproducible.** Ejecuta format, analyze, tests y builds definidos; no es un modelo de IA.

## Límite real del plan gratuito de Jules

La documentación oficial consultada publica hasta 15 tareas por ventana móvil de 24 horas y hasta 3 tareas concurrentes en el plan gratuito. Por ello, seis perfiles se ejecutan en dos oleadas de tres tareas, no en seis tareas concurrentes. Las cuotas son límites del proveedor y pueden cambiar.

## Conectar Jules desde el teléfono

1. Abrir https://jules.google.com desde el navegador móvil.
2. Iniciar sesión con una cuenta Google.
3. Pulsar **Connect to GitHub account**.
4. Autorizar únicamente el repositorio `liendomaho-wq/Aura-V1.0` si el selector permite limitar el acceso.
5. Confirmar que Aura aparece en el selector de repositorios.
6. No conceder permisos de administración, secretos o escritura directa a `main` si no son necesarios.
7. Crear una tarea piloto de solo lectura primero: pedir análisis del módulo asignado, archivos relevantes, riesgos y pruebas recomendadas, sin modificar código.
8. Tras revisar el plan, lanzar una tarea de implementación acotada en una rama separada y exigir PR hacia `main`.

Enlace oficial de inicio: https://jules.google/docs/

## Conectar CodeRabbit desde el teléfono

1. Abrir https://github.com/marketplace/coderabbitai o https://www.coderabbit.ai/oss.
2. Iniciar sesión con GitHub.
3. Instalar la aplicación para el repositorio público Aura, no para todos los repositorios si no hace falta.
4. Revisar los permisos que solicita antes de confirmar.
5. Activar revisión automática de PRs.
6. Comprobar el primer comentario en una PR de prueba.

El nivel gratuito para open source depende de que el repositorio sea público. CodeRabbit es una segunda opinión automática, no una garantía de ausencia de errores.

## Distribución de los seis agentes

### Oleada 1 — hasta tres tareas simultáneas
1. Android/Kotlin: análisis y cambios acotados de servicios Android.
2. Flutter/UI: análisis y cambios acotados de interfaz.
3. QA/CI: cobertura de pruebas, workflows y reproducibilidad.

### Oleada 2 — hasta tres tareas simultáneas
4. IA/modelos: evaluación de inferencia, integridad de modelos y límites de capacidad.
5. Seguridad/privacidad: revisión de superficies de ataque, almacenamiento y permisos.
6. Arquitectura: dependencias, contratos entre módulos y revisión de integración.

La distribución debe ajustarse si dos agentes necesitan editar los mismos archivos. No asignar tareas solapadas solo para aumentar el paralelismo.

## Contrato de cada tarea

Cada prompt de Jules debe incluir:
- Perfil exacto de `agents/roles/`.
- Un único objetivo verificable.
- Archivos permitidos y archivos prohibidos.
- SHA base del repositorio.
- Dependencias de otras tareas.
- Pruebas requeridas.
- Prohibición de modificar o fusionar `main`.
- Obligación de informar pruebas no ejecutadas como **NO EJECUTADAS**.
- Entrega por rama y PR abierta, sin auto-merge.

## Seguridad y control de cambios

- Mantener la rama `main` protegida por `Aura-main-protection`.
- No almacenar API keys, keystores, certificados ni tokens en commits, issues o prompts.
- Conceder acceso a proveedores externos solo al repositorio necesario.
- Revisar los permisos y la política de privacidad de cada proveedor antes de conectar.
- No enviar datos personales ni secretos de usuarios a servicios de IA.
- Los agentes no pueden fusionar PRs ni cambiar reglas del repositorio.
- La revisión de CodeRabbit y los checks de CI no sustituyen la auditoría de ChatGPT ni la autorización del propietario.

## Fuentes oficiales

- Jules FAQ: https://jules.google/docs/faq
- Jules planes y límites: https://jules.google/docs/usage-limits/
- Jules conexión GitHub: https://jules.google/docs/
- CodeRabbit para open source: https://www.coderabbit.ai/oss
- GitHub Actions: https://docs.github.com/en/actions

## Estado de la conexión

Esta guía define el proceso, pero no conecta cuentas externas. El propietario debe completar los pasos de autorización desde el navegador. No se afirma que Jules o CodeRabbit ya estén instalados ni conectados.
