@Skip('requiere dispositivo/entorno local')

import 'dart:convert';

import 'package:aura_mobile_defens/inference/aura_ai_inference.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('mide 1.000 inferencias locales sobre 20 dominios', () async {
    final rawModel = jsonDecode(
      await rootBundle.loadString('assets/model/aura_brain_model.json'),
    );
    if (rawModel is! Map) {
      throw const FormatException('El asset del modelo no contiene un objeto.');
    }
    final model = Map<String, dynamic>.from(rawModel);
    final domains = <String>[
      'wikipedia.org',
      'mozilla.org',
      'example.com',
      'stackoverflow.com',
      'rust-lang.org',
      'python.org',
      'debian.org',
      'kernel.org',
      'archlinux.org',
      'duckduckgo.com',
      'goggle.com',
      'x7z9q1wplmnb.xyz',
      'free-crypto-rewards.click',
      'update-system-android.live',
      '91kazmslqo1029az.biz',
      'get-unlocked-premium.fit',
      'malicious-payload-server.info',
      'aqwzsxedcrfv12.top',
      'p0wz9172mlxozq.tk',
      'shw28190axmzq.xyz',
    ];
    final durations = List<int>.generate(1000, (index) {
      final stopwatch = Stopwatch()..start();
      AuraAIInference.analyzeHostSecure(
        domains[index % domains.length],
        model,
      );
      stopwatch.stop();
      return stopwatch.elapsedMicroseconds;
    })
      ..sort();

    double percentile(double percentile) {
      final index = ((percentile * durations.length).ceil() - 1)
          .clamp(0, durations.length - 1);
      return durations[index] / 1000;
    }

    print(
      'INFERENCE_BENCHMARK samples=${durations.length} '
      'domains=${domains.length} '
      'p50_ms=${percentile(0.50).toStringAsFixed(3)} '
      'p95_ms=${percentile(0.95).toStringAsFixed(3)} '
      'p99_ms=${percentile(0.99).toStringAsFixed(3)}',
    );
  });
}
