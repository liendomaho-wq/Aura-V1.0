# Aura — identidad visual y experiencia de la IA

Fecha: 2026-11-02  
Estado: diseño visual implementado parcialmente en `main`; pendiente de validación en dispositivos físicos.

## Concepto

Aura debe sentirse como una presencia inteligente dentro del teléfono, no como un panel de ciberseguridad al que se le añadió un chat. La conversación es la superficie principal. El avatar representa la identidad de Aura y comunica estados observables de la aplicación.

La dirección visual combina:
- Fondo profundo midnight (`#050B18`) y superficies azul noche.
- Luz cyan para disponibilidad e información.
- Violeta para escucha e identidad.
- Verde para una operación defensiva confirmada.
- Coral/rojo solo para alertas.
- Tipografía limpia, jerarquía breve y espacio alrededor del avatar.

No utilizar escudos, radares, retículas de vigilancia ni paneles densos como lenguaje visual principal.

## Avatar

El avatar se dibuja localmente con Flutter `CustomPainter`, sin cargar imágenes remotas ni incorporar SDK adicional. Su forma actual es una entidad luminosa abstracta: núcleo profundo, halo, órbita y rostro geométrico con ojos y expresión mínima.

### Estados

| Estado | Cuándo se muestra | Tratamiento |
|---|---|---|
| Disponible | No hay una operación activa ni alerta vigente | Cyan suave, pulso lento |
| Escuchando | El reconocimiento de voz está activo | Violeta, órbita más dinámica |
| Analizando | Una instrucción o herramienta está ejecutándose | Cyan, movimiento más rápido |
| Protegiendo | Android confirma que la defensa local está activa | Verde |
| Advertencia | La postura del dispositivo requiere revisión, sin ser crítica | Ámbar |
| Alerta | La postura o el motor informa una señal de advertencia/crítica | Coral |

La animación solo comunica el estado que la app conoce. No representa progreso ficticio ni acredita por sí misma que el dispositivo esté protegido. La preferencia Android de reducir animaciones detiene el movimiento.

## Pantalla principal

1. Identidad compacta AURA y rol de agente local en la cabecera.
2. Avatar protagonista dentro de una superficie luminosa y contenida.
3. Saludo y frase de estado derivada de la actividad real.
4. Conversación como área principal; mensajes del usuario y respuestas de Aura se distinguen sin formato de terminal como experiencia dominante.
5. Auditoría, privacidad y control de VPN permanecen accesibles, pero son secundarios a la conversación.
6. Compositor inferior para texto y voz, con envío deshabilitado cuando no hay contenido o el agente no puede aceptar otra orden.

## Reglas de interacción y confianza

- Mostrar resultados como completados, parciales, denegados o no disponibles; nunca transformar un error en éxito.
- Acciones que alteren conectividad, bloqueen dominios o borren datos requieren confirmación visible.
- No mostrar “protegiendo” hasta que el estado Android confirme la defensa activa.
- Los errores de autenticación mantienen bloqueada la consola.
- Mantener etiquetas semánticas del avatar y objetivos táctiles accesibles.
- No enviar contenido privado a servicios remotos por defecto.

## Estado de la inteligencia

El agente actual es un orquestador local determinista de herramientas y un clasificador de dominios basado en un modelo de árboles. No es todavía un LLM generativo. El diseño visual no debe sugerir conversación abierta de propósito general hasta que exista un modelo generativo real, sus pesos/runtime, evaluación de seguridad y controles de privacidad.

## Pendiente de validación

- Revisar composición en pantallas pequeñas, grandes y con escala de texto.
- Probar teclado abierto, rotación, TalkBack, movimiento reducido y contraste.
- Medir animación del avatar en batería/temperatura durante sesiones prolongadas.
- Validar que cada estado visual se corresponda con un estado real de Android/agente.
- Ejecutar `flutter analyze`, pruebas widget y build Android antes de aprobar el diseño para entrega.
