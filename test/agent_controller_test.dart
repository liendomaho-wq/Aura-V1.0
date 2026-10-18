import 'package:aura_mobile_defens/agent/agent_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('help devuelve exactamente la lista de órdenes solicitada', () async {
    const expected = 'ÓRDENES DISPONIBLES — ACTIVAR DEFENSAS · '
        'DESACTIVAR DEFENSAS · BLOQUEAR <dominio> · AISLAR <paquete> · '
        'AISLAMIENTO DE EMERGENCIA · REANUDAR LA RED · ACTUALIZAR DEFENSAS · '
        'ESTADO · PURGA CRIPTOGRÁFICA';
    final controller = AgentController.instance;
    final previousLength = controller.history.length;

    await controller.run('ayuda');

    expect(
      controller.history.skip(previousLength).map((event) => event.message),
      contains(expected),
    );
  });
}
