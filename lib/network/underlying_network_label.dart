const knownUnderlyingNetworkLabels = <String>{
  'WiFi',
  'Datos móviles',
  'Sin conexión',
  'Otra red',
};

String underlyingNetworkLabelForKind(String? kind) {
  switch (kind) {
    case 'wifi':
      return 'WiFi';
    case 'cellular':
      return 'Datos móviles';
    case 'other':
      return 'Otra red';
    default:
      return 'Sin conexión';
  }
}

String underlyingNetworkLabelFromEvent(Object? event) {
  if (event is Map) {
    final label = event['label'];
    if (label is String && knownUnderlyingNetworkLabels.contains(label)) {
      return label;
    }
    final kind = event['kind'];
    if (kind is String) return underlyingNetworkLabelForKind(kind);
  }
  return 'Sin conexión';
}
