import 'package:aura_mobile_defens/network/underlying_network_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mapea el transporte físico a la etiqueta visible', () {
    expect(underlyingNetworkLabelForKind('wifi'), 'WiFi');
    expect(underlyingNetworkLabelForKind('cellular'), 'Datos móviles');
    expect(underlyingNetworkLabelForKind('none'), 'Sin conexión');
    expect(underlyingNetworkLabelForKind(null), 'Sin conexión');
  });

  test('acepta la etiqueta nativa y rechaza texto inesperado', () {
    expect(
      underlyingNetworkLabelFromEvent(<String, String>{
        'kind': 'wifi',
        'label': 'WiFi',
      }),
      'WiFi',
    );
    expect(
      underlyingNetworkLabelFromEvent(<String, String>{
        'kind': 'cellular',
        'label': 'no es una etiqueta',
      }),
      'Datos móviles',
    );
    expect(underlyingNetworkLabelFromEvent('wifi'), 'Sin conexión');
  });
}
