/// Spoken lines built only from values Aura has actually observed.
String auraStatusBrief({
  required bool defenseActive,
  required String networkLabel,
  required int blocksSeenToday,
}) {
  final blocks = blocksSeenToday < 0 ? 0 : blocksSeenToday;
  final network = networkLabel.trim();
  final usableNetwork =
      network.isNotEmpty && network != 'Sin conexión' && network != 'Sin datos';
  final defense = defenseActive
      ? (usableNetwork ? 'Defensa activa en $network.' : 'Defensa activa.')
      : 'Defensa inactiva.';
  final count = blocks == 1
      ? 'Bloqueos que vi hoy: 1.'
      : 'Bloqueos que vi hoy: $blocks.';
  return '$defense $count';
}

int auraBlocksSeenToday(Iterable<Map<String, dynamic>> events, DateTime now) {
  var count = 0;
  for (final event in events) {
    final action = event['action'];
    if (action != 'BLOCKED' && action != 'DGA_ALERT') continue;
    final raw = event['timestamp'];
    if (raw is! int || raw <= 0) continue;
    final millis = raw > 100000000000 ? raw : raw * 1000;
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      count++;
    }
  }
  return count;
}

int auraEventsInLastMinute(
  Iterable<Map<String, dynamic>> events,
  DateTime now,
) {
  final start = now.millisecondsSinceEpoch - 60000;
  final end = now.millisecondsSinceEpoch + 2000;
  var count = 0;
  for (final event in events) {
    final raw = event['timestamp'];
    if (raw is! int || raw <= 0) continue;
    final millis = raw > 100000000000 ? raw : raw * 1000;
    if (millis >= start && millis <= end) count++;
  }
  return count;
}

/// One spoken threat alert per gap, so a burst does not talk over itself.
class AuraAlertGate {
  AuraAlertGate({this.gap = const Duration(seconds: 20)});

  final Duration gap;
  DateTime? last;

  bool allow(DateTime now) {
    final previous = last;
    if (previous != null && now.difference(previous) < gap) return false;
    last = now;
    return true;
  }
}
