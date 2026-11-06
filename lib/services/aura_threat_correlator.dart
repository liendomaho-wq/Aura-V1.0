enum AuraThreatSeverity { low, medium, high }

extension AuraThreatSeverityLabel on AuraThreatSeverity {
  String get label => switch (this) {
    AuraThreatSeverity.low => 'baja',
    AuraThreatSeverity.medium => 'media',
    AuraThreatSeverity.high => 'alta',
  };
}

class AuraThreatAlert {
  AuraThreatAlert({
    required this.severity,
    required this.blockedConnectionCount,
    required this.domains,
    required this.firstSeenTimestamp,
    required this.lastSeenTimestamp,
    this.domain,
    this.sourceAppPackage,
    this.sourceAppName,
    List<String> appScanIndicators = const <String>[],
  }) : appScanIndicators = List<String>.unmodifiable(appScanIndicators);

  final AuraThreatSeverity severity;
  final int blockedConnectionCount;
  final String? domain;
  final List<String> domains;
  final String? sourceAppPackage;
  final String? sourceAppName;
  final List<String> appScanIndicators;
  final int firstSeenTimestamp;
  final int lastSeenTimestamp;

  String get summary {
    final app = sourceAppName ?? sourceAppPackage;
    if (domain != null) {
      final attribution = app == null ? '' : ' desde la app $app';
      return 'Se bloquearon $blockedConnectionCount conexiones al dominio '
          '$domain$attribution.';
    }

    final appLabel = app ?? 'app de origen no identificada';
    return 'Se bloquearon $blockedConnectionCount conexiones desde la app '
        '$appLabel a ${domains.length} dominios bloqueados: '
        '${domains.join(', ')}.';
  }

  Map<String, Object> toMap() => <String, Object>{
    'severity': severity.label,
    'blocked_connection_count': blockedConnectionCount,
    'domains': domains,
    'first_seen_timestamp': firstSeenTimestamp,
    'last_seen_timestamp': lastSeenTimestamp,
    if (domain != null) 'domain': domain!,
    if (sourceAppPackage != null) 'source_app_package': sourceAppPackage!,
    if (sourceAppName != null) 'source_app_name': sourceAppName!,
    if (appScanIndicators.isNotEmpty) 'app_scan_indicators': appScanIndicators,
  };
}

class AuraThreatCorrelator {
  static const int maxRetainedEvents = 500;
  static const Duration correlationWindow = Duration(minutes: 10);
  static const int repeatedDomainThreshold = 3;

  static final RegExp _domainPattern = RegExp(
    r'^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+'
    r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
  );
  static final RegExp _packagePattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
  );

  AuraThreatCorrelator({int Function()? clock}) : _clock = clock ?? _systemNow;

  final int Function() _clock;
  final List<_BlockedDomainEvent> _blockedEvents = <_BlockedDomainEvent>[];
  Map<String, _AppScanProfile> _appScanProfiles =
      const <String, _AppScanProfile>{};
  int _latestTimestamp = 0;
  int _appScanTimestamp = 0;

  int get retainedBlockedEventCount {
    _expireOldEvents();
    return _blockedEvents.length;
  }

  List<AuraThreatAlert> get alerts {
    _expireOldEvents();
    final output = <AuraThreatAlert>[
      ..._domainAlerts(),
      ..._multiDomainAppAlerts(),
    ];
    output.sort((left, right) {
      final severity = right.severity.index.compareTo(left.severity.index);
      if (severity != 0) return severity;
      final count = right.blockedConnectionCount.compareTo(
        left.blockedConnectionCount,
      );
      if (count != 0) return count;
      return (left.domain ?? left.sourceAppPackage ?? '').compareTo(
        right.domain ?? right.sourceAppPackage ?? '',
      );
    });
    return List<AuraThreatAlert>.unmodifiable(output);
  }

  bool recordNetworkEvent(Map<String, dynamic> event) {
    final action = event['action'];
    if (action != 'BLOCKED' && action != 'ENCRYPTED_DNS_BLOCKED') {
      return false;
    }

    final rawTimestamp = event['timestamp'];
    final rawDomain = event['requested_domain'];
    if (rawTimestamp is! int || rawTimestamp <= 0 || rawDomain is! String) {
      return false;
    }

    final domain = _normalizeDomain(rawDomain);
    if (domain == null) return false;

    final timestamp = rawTimestamp;
    final referenceTimestamp = _currentTimestamp;
    if (timestamp < referenceTimestamp - correlationWindow.inMilliseconds) {
      return false;
    }
    if (timestamp > _latestTimestamp) _latestTimestamp = timestamp;

    _blockedEvents.add(
      _BlockedDomainEvent(
        timestamp: timestamp,
        domain: domain,
        sourceAppPackage: _singleSourcePackage(event['source_app']),
      ),
    );
    _blockedEvents.sort(
      (left, right) => left.timestamp.compareTo(right.timestamp),
    );

    _expireOldEvents();
    if (_blockedEvents.length > maxRetainedEvents) {
      _blockedEvents.removeRange(0, _blockedEvents.length - maxRetainedEvents);
    }
    return true;
  }

  bool recordAppScanResult(Map<String, dynamic> result) {
    final timestamp = result['timestamp'];
    if (result['ok'] != true ||
        result['scan_type'] != 'installed_app_static_review' ||
        timestamp is! int ||
        timestamp <= 0 ||
        timestamp < _appScanTimestamp) {
      return false;
    }

    final profiles = <String, _MutableAppScanProfile>{};
    _addProfiles(profiles, result['applications'], 'servicio sensible activo');
    _addProfiles(
      profiles,
      result['suspicious_apps'],
      'combinación de permisos de alto riesgo (heurística)',
    );
    _addProfiles(
      profiles,
      result['signature_issues'],
      'incidencia de firma reportada por el escáner',
    );
    _addProfiles(
      profiles,
      result['obfuscated_apps'],
      'indicador de ofuscación reportado por el escáner',
    );
    _addProfiles(
      profiles,
      result['special_access'],
      'acceso especial activo',
      activeOnly: true,
    );

    _appScanProfiles = <String, _AppScanProfile>{
      for (final entry in profiles.entries)
        entry.key: _AppScanProfile(
          packageName: entry.key,
          appName: entry.value.appName,
          indicators: entry.value.indicators.toList()..sort(),
        ),
    };
    _appScanTimestamp = timestamp;
    return true;
  }

  void clear() {
    _blockedEvents.clear();
    _appScanProfiles = const <String, _AppScanProfile>{};
    _latestTimestamp = 0;
    _appScanTimestamp = 0;
  }

  String buildReport() {
    final currentAlerts = alerts;
    if (currentAlerts.isEmpty) {
      if (_blockedEvents.isEmpty) {
        return 'No hay eventos recientes de dominios bloqueados para correlacionar.';
      }
      return 'Se registraron ${_blockedEvents.length} conexiones bloqueadas, '
          'sin alcanzar los umbrales para consolidar una alerta.';
    }

    final reports = currentAlerts
        .take(5)
        .map((alert) {
          return 'Alerta consolidada de severidad ${alert.severity.label}: '
              '${alert.summary}';
        })
        .join(' ');
    final remaining = currentAlerts.length - 5;
    return remaining > 0
        ? '$reports Hay $remaining alertas consolidadas adicionales.'
        : reports;
  }

  List<AuraThreatAlert> _domainAlerts() {
    final byDomain = <String, List<_BlockedDomainEvent>>{};
    for (final event in _blockedEvents) {
      byDomain
          .putIfAbsent(event.domain, () => <_BlockedDomainEvent>[])
          .add(event);
    }

    return byDomain.entries
        .where((entry) => entry.value.length >= repeatedDomainThreshold)
        .map((entry) {
          final events = entry.value;
          final sourceApp = _commonSourceApp(events);
          final profile = sourceApp == null
              ? null
              : _appScanProfiles[sourceApp];
          return AuraThreatAlert(
            severity: _severityFor(events),
            blockedConnectionCount: events.length,
            domain: entry.key,
            domains: <String>[entry.key],
            sourceAppPackage: sourceApp,
            sourceAppName: profile?.appName,
            appScanIndicators: profile?.indicators ?? const <String>[],
            firstSeenTimestamp: events.first.timestamp,
            lastSeenTimestamp: events.last.timestamp,
          );
        })
        .toList(growable: false);
  }

  List<AuraThreatAlert> _multiDomainAppAlerts() {
    final byApp = <String, List<_BlockedDomainEvent>>{};
    for (final event in _blockedEvents) {
      final packageName = event.sourceAppPackage;
      if (packageName == null) continue;
      byApp.putIfAbsent(packageName, () => <_BlockedDomainEvent>[]).add(event);
    }

    return byApp.entries
        .map((entry) {
          final events = entry.value;
          final domains = events.map((event) => event.domain).toSet().toList()
            ..sort();
          if (domains.length < 2) return null;

          final profile = _appScanProfiles[entry.key];
          return AuraThreatAlert(
            severity: _severityFor(events),
            blockedConnectionCount: events.length,
            domains: domains,
            sourceAppPackage: entry.key,
            sourceAppName: profile?.appName,
            appScanIndicators: profile?.indicators ?? const <String>[],
            firstSeenTimestamp: events.first.timestamp,
            lastSeenTimestamp: events.last.timestamp,
          );
        })
        .whereType<AuraThreatAlert>()
        .toList(growable: false);
  }

  static AuraThreatSeverity _severityFor(List<_BlockedDomainEvent> events) {
    final count = events.length;
    final elapsed = events.last.timestamp - events.first.timestamp;
    if (count >= 10 || (count >= 5 && elapsed <= 60000)) {
      return AuraThreatSeverity.high;
    }
    if (count >= 5 || (count >= repeatedDomainThreshold && elapsed <= 60000)) {
      return AuraThreatSeverity.medium;
    }
    return AuraThreatSeverity.low;
  }

  static String? _normalizeDomain(String value) {
    final domain = value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return _domainPattern.hasMatch(domain) ? domain : null;
  }

  static String? _singleSourcePackage(Object? value) {
    if (value is! String) return null;
    final packageName = value.trim();
    if (!_packagePattern.hasMatch(packageName) || packageName.contains(',')) {
      return null;
    }
    return packageName;
  }

  void _addProfiles(
    Map<String, _MutableAppScanProfile> profiles,
    Object? rawEntries,
    String indicator, {
    bool activeOnly = false,
  }) {
    if (rawEntries is! List) return;
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map) continue;
      final packageName = _singleSourcePackage(rawEntry['package_name']);
      if (packageName == null ||
          (activeOnly && rawEntry['state'] != 'ACTIVE')) {
        continue;
      }
      final profile = profiles.putIfAbsent(
        packageName,
        () => _MutableAppScanProfile(),
      );
      final appName = rawEntry['app_name'];
      if (appName is String && appName.trim().isNotEmpty) {
        profile.appName = appName.trim();
      }
      profile.indicators.add(indicator);
    }
  }

  static String? _commonSourceApp(List<_BlockedDomainEvent> events) {
    final packageNames = events.map((event) => event.sourceAppPackage).toSet();
    if (packageNames.length != 1) return null;
    return packageNames.single;
  }

  int get _currentTimestamp {
    final now = _clock();
    return now > _latestTimestamp ? now : _latestTimestamp;
  }

  void _expireOldEvents() {
    final cutoff = _currentTimestamp - correlationWindow.inMilliseconds;
    _blockedEvents.removeWhere((entry) => entry.timestamp < cutoff);
  }

  static int _systemNow() => DateTime.now().millisecondsSinceEpoch;
}

class _BlockedDomainEvent {
  const _BlockedDomainEvent({
    required this.timestamp,
    required this.domain,
    required this.sourceAppPackage,
  });

  final int timestamp;
  final String domain;
  final String? sourceAppPackage;
}

class _MutableAppScanProfile {
  String? appName;
  final Set<String> indicators = <String>{};
}

class _AppScanProfile {
  const _AppScanProfile({
    required this.packageName,
    required this.appName,
    required this.indicators,
  });

  final String packageName;
  final String? appName;
  final List<String> indicators;
}
