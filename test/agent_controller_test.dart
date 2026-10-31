import 'package:aura_mobile_defens/agent/agent_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('help devuelve exactamente la lista de órdenes solicitada', () async {
    const expected = 'ÓRDENES DISPONIBLES — ACTIVAR DEFENSAS · '
        'DESACTIVAR DEFENSAS · BLOQUEAR <dominio> · AISLAR <paquete> · '
        'AISLAMIENTO DE EMERGENCIA · REANUDAR LA RED · ACTUALIZAR DEFENSAS · '
        'ESCANEAR APLICACIONES · ESTADO · PURGA CRIPTOGRÁFICA';
    final controller = AgentController.instance;
    final previousLength = controller.history.length;

    await controller.run('ayuda');

    expect(
      controller.history.skip(previousLength).map((event) => event.message),
      contains(expected),
    );
  });

  test('descarta eventos antiguos al superar 400 entradas', () {
    final controller = AgentController.instance;
    controller.history.clear();

    for (var index = 0; index < 405; index++) {
      controller.reportWarning('evento-$index');
    }

    expect(AgentController.historyCapacity, 400);
    expect(controller.history, hasLength(400));
    expect(controller.history.first.message, 'evento-5');
    expect(controller.history.last.message, 'evento-404');
    controller.history.clear();
  });
}
