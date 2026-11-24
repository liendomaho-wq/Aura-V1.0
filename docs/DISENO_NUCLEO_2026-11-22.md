# Núcleo Aura — dirección visual y plan de implementación

Prototipo: `docs/design/aura-nucleo.html` (animado, sin dependencias)
Imagen de referencia: `docs/design/aura-nebula-concept.png`

## Principio

La interfaz deja de ser un tablero y pasa a ser **presencia**. No hay escudo,
no hay tarjetas permanentes, no hay pestañas. Hay un núcleo vivo y una
conversación; la evidencia aparece cuando el usuario la pide.

Esto no significa esconder información de seguridad. Significa separar dos
momentos:

1. **Ahora**: qué está pasando y qué puedo hacer. Una línea, un color, una voz.
2. **Evidencia**: por qué Aura dice eso. Se abre a propósito, no vive en la
   pantalla principal.

## Estados del núcleo

| Estado | Movimiento | Color | Texto |
| --- | --- | --- | --- |
| Reposo | respiración lenta, partículas a 0.2× | cian + violeta | «Estoy aquí. ¿Qué revisamos?» |
| Escuchando | pulso rápido, halo más denso | cian brillante | «Te escucho.» |
| Analizando | trazas recorridas por pulsos | azul frío | «Revisando…» (solo si hay trabajo real) |
| Alerta | órbita ámbar, trazas más rápidas | ámbar + rosa | «Algo requiere tu atención.» |
| Sin motor | órbita casi estática | gris azulado | «Modo local de reglas.» |

Regla: **el color y el movimiento solo cambian con estado real**. Nunca se
simula actividad para que la pantalla se vea viva.

## Composición

- Fondo casi negro con viñeta; sin superficies opacas.
- Núcleo en el tercio superior, texto debajo, un único micrófono abajo.
- Tipografía: una sola familia; titular 34–40 px, peso 400; marca en versalitas
  con tracking amplio.
- Sin iconos decorativos. El escudo, el candado y las tarjetas desaparecen por
  completo.
- El texto de conversación se apoya directamente sobre el vacío. Los mensajes
  largos se atenúan y se puede tocar para expandir, en vez de encerrarlos en
  burbujas.

## Rendimiento en el TECNO POVA 5

El efecto no puede costar la batería ni la fluidez:

- `CustomPainter` con `RepaintBoundary`; el campo se repinta solo, no el árbol.
- 140–180 partículas y 18–24 trazas; nada de miles de puntos.
- 30 fps estables antes que 60 fps inestables; `TickerMode` apaga la animación
  cuando la app pasa a segundo plano.
- Sin `BackdropFilter` continuo ni sombras de blur grandes por partícula.
- `MediaQuery.disableAnimations` / reduce motion: un fotograma estático.
- Modo ahorro: el núcleo baja a 15 fps y las trazas dejan de viajar.

## Cómo se convierte en Flutter

1. `AuraNucleusField` (`CustomPainter` + `AnimationController`, 30 fps).
   Recibe `AuraNucleusState` y `AuraNucleusSeverity`; no conoce herramientas ni
   red.
2. `AuraCoreScreen` conserva toda la lógica actual (`_dispatch`, voz, permisos,
   telemetría) y cambia la capa visual: fondo, cabecera transparente,
   conversación sin tarjetas y filamento inferior.
3. La evidencia se mueve a una capa bajo demanda (deslizar hacia arriba o tocar
   la línea de alerta). No se elimina: se hace intencional.
4. La actividad y los detalles técnicos siguen existiendo para quien los
   necesite; dejan de competir con la conversación.

### Pruebas

- Widget test: el campo no se reconstruye con cada token de texto.
- Prueba de estados: reposo → escuchando → analizando → alerta y vuelta.
- Prueba de accesibilidad: con reduce motion no hay `Ticker` activo; el texto
  conserva contraste y escala.
- Prueba de batería: 60 s en segundo plano no dejan animación corriendo.

## Qué no promete este diseño

- No arregla la seguridad por sí solo: la evidencia y las acciones siguen
  dependiendo de los motores reales.
- No elimina la necesidad de una capa de detalle; la vuelve menos invasiva.
- No se puede validar visualmente en un dispositivo físico desde este entorno.
  El prototipo HTML y las pruebas de CI son la referencia hasta compilar en el
  TECNO POVA 5.
