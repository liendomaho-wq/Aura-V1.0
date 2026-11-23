/// Política local de riesgo para nombres de dominio.
///
/// El modelo 3.0.0 puntúa el **host completo**. Eso hace que un subdominio
/// largo y legítimo (`pubmed.ncbi.nlm.nih.gov`) reciba la misma puntuación que
/// un nombre aleatorio. Esta política separa dos observaciones:
///
/// 1. la puntuación del host observado, tal como la produce el bosque;
/// 2. la puntuación del dominio registrable (eTLD+1), calculada con la misma
///    extracción de características.
///
/// Solo se eleva a [AuraRiskBand.high] cuando ambas observaciones son altas.
/// Un host largo con un dominio registrable limpio queda en
/// [AuraRiskBand.review]: se muestra como revisión, nunca como amenaza y nunca
/// autoriza un bloqueo. La política es determinista y no tiene efectos
/// secundarios, por lo que puede probarse sin Flutter ni canales nativos.
library;

/// Banda de riesgo derivada de dos puntuaciones del bosque.
enum AuraRiskBand {
  /// Ninguna observación alcanza el umbral de revisión.
  clear,

  /// Hay una señal léxica, pero no en el dominio registrable. Requiere que la
  /// persona revise; no es una amenaza confirmada.
  review,

  /// Host y dominio registrable superan el umbral alto. Sigue siendo una
  /// propuesta: el motor nunca bloquea por sí solo.
  high,
}

class AuraHostPolicy {
  AuraHostPolicy._();

  /// Por debajo de este valor no se muestra ninguna señal léxica.
  static const double reviewFloor = 0.35;

  /// Desde este valor, y solo si el dominio registrable también lo alcanza,
  /// la observación se presenta como prioridad alta.
  static const double highFloor = 0.65;

  /// Sufijos de segundo nivel que requieren tres etiquetas para obtener el
  /// dominio registrable. No es la Public Suffix List completa: es una lista
  /// conservadora para las regiones hispanohablantes y los sufijos más comunes.
  /// Los sufijos privados (`github.io`, `blogspot.com`) se excluyen a propósito
  /// para agrupar por el dominio que la persona reconoce.
  static const Set<String> _multiLabelSuffixes = <String>{
    // Reino Unido e Irlanda
    'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'me.uk', 'ltd.uk', 'plc.uk',
    'net.uk', 'sch.uk',
    // España y Portugal
    'com.es', 'org.es', 'nom.es', 'gob.es', 'edu.es',
    'com.pt', 'org.pt', 'gov.pt',
    // Latinoamérica
    'com.ar', 'net.ar', 'org.ar', 'gov.ar', 'edu.ar',
    'com.br', 'net.br', 'org.br', 'gov.br', 'edu.br',
    'com.mx', 'net.mx', 'org.mx', 'gob.mx', 'edu.mx',
    'com.co', 'net.co', 'org.co', 'gov.co', 'edu.co',
    'com.ve', 'net.ve', 'org.ve', 'gob.ve', 'edu.ve', 'mil.ve',
    'com.ec', 'org.ec', 'gob.ec', 'edu.ec',
    'com.pe', 'org.pe', 'gob.pe', 'edu.pe',
    'com.bo', 'org.bo', 'gob.bo', 'edu.bo',
    'com.cl', 'org.cl', 'gob.cl', 'edu.cl',
    'com.uy', 'org.uy', 'gob.uy', 'edu.uy',
    'com.py', 'org.py', 'gov.py', 'edu.py',
    'com.do', 'org.do', 'gob.do', 'edu.do',
    'com.gt', 'org.gt', 'gob.gt', 'edu.gt',
    'com.hn', 'org.hn', 'gob.hn', 'edu.hn',
    'com.sv', 'org.sv', 'gob.sv', 'edu.sv',
    'com.ni', 'org.ni', 'gob.ni', 'edu.ni',
    'com.cr', 'org.cr', 'go.cr', 'edu.cr',
    'com.pa', 'org.pa', 'gob.pa', 'edu.pa',
    'com.cu', 'org.cu', 'gob.cu', 'edu.cu',
    // Asia-Pacífico y otros
    'co.nz', 'net.nz', 'org.nz', 'govt.nz', 'ac.nz',
    'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au',
    'co.jp', 'or.jp', 'ne.jp', 'go.jp', 'ac.jp',
    'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'edu.cn',
    'com.hk', 'com.tw', 'com.sg', 'com.my', 'com.ph',
    'com.tr', 'com.ua', 'com.ru', 'com.pl', 'com.de', 'com.fr', 'com.it',
  };

  static final RegExp _labelPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
  static final RegExp _allDigits = RegExp(r'^[0-9]+$');

  /// Devuelve el dominio registrable de un host ya normalizado, o `null` si no
  /// es un nombre de dominio utilizable.
  ///
  /// Se aplica antes de puntuar. No resuelve DNS ni consulta la red.
  static String? registrableDomain(String rawHost) {
    final host = rawHost.trim().toLowerCase();
    if (host.isEmpty || host.length > 253 || host.contains('/')) return null;
    if (host.endsWith('.')) return registrableDomain(host.substring(0, host.length - 1));

    final labels = host.split('.');
    if (labels.length < 2) return null;
    for (final label in labels) {
      if (!_labelPattern.hasMatch(label)) return null;
    }
    // Una dirección IPv4 no es un dominio: no debe recibir una puntuación
    // léxica ni presentarse como dominio registrable.
    if (labels.every(_allDigits.hasMatch)) return null;

    final lastTwo = '${labels[labels.length - 2]}.${labels.last}';
    final requiredLabels = _multiLabelSuffixes.contains(lastTwo) ? 3 : 2;
    if (labels.length < requiredLabels) return null;
    return labels.sublist(labels.length - requiredLabels).join('.');
  }

  /// Calcula la banda a partir de las dos puntuaciones del bosque.
  ///
  /// Ambas deben ser finitas y estar en [0, 1]. Un valor fuera de rango es un
  /// fallo del motor y se rechaza en vez de redondearse en silencio.
  static AuraRiskBand band({
    required double hostScore,
    required double registrableScore,
  }) {
    _requireScore(hostScore, 'hostScore');
    _requireScore(registrableScore, 'registrableScore');
    if (hostScore >= highFloor && registrableScore >= highFloor) {
      return AuraRiskBand.high;
    }
    if (hostScore >= reviewFloor || registrableScore >= reviewFloor) {
      return AuraRiskBand.review;
    }
    return AuraRiskBand.clear;
  }

  /// Etiqueta breve y estable para UI y pruebas.
  static String label(AuraRiskBand band) => switch (band) {
    AuraRiskBand.clear => 'sin señal',
    AuraRiskBand.review => 'revisión',
    AuraRiskBand.high => 'prioridad alta',
  };

  static void _requireScore(double value, String name) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, name, 'La puntuación debe estar entre 0 y 1.');
    }
  }
}
