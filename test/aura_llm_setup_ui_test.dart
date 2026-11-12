import 'package:aura_mobile_defens/infrastructure/storage/aura_storage.dart';
import 'package:aura_mobile_defens/llm/aura_llm_model_manager.dart';
import 'package:aura_mobile_defens/llm/aura_llm_model_source.dart';
import 'package:aura_mobile_defens/llm/aura_llm_setup_controller.dart';
import 'package:aura_mobile_defens/theme/aura_tokens.dart';
import 'package:aura_mobile_defens/widgets/aura_capability_ring.dart';
import 'package:aura_mobile_defens/widgets/aura_llm_setup_scope.dart';
import 'package:aura_mobile_defens/widgets/aura_llm_setup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _source = AuraLlmModelSource(
  displayName: 'DeepSeek-R1-Distill-Qwen-1.5B',
  parameters: '1.5B',
  quantization: 'Q4_K_M',
  license: 'Apache-2.0',
  downloadUrl: 'https://example.test/model.gguf',
  sha256: 'f3bdf9cf31dee4b57ae4e455a1cb0d01b5c2c1b50d72d3112141c195506c2840',
  sizeBytes: 1117321312,
  publisher: 'unsloth',
  revision: '3cb4d15544a2a5e07439592b9a0965b6445fbd34',
);

class _FakeStorage extends AuraStorage {
  _FakeStorage(this.value);

  final int? value;

  @override
  Future<int?> freeBytes() async => value;
}

class _FakeProvisioner implements AuraLlmModelProvisioner {
  _FakeProvisioner({this.installed = false, this.configured = true});

  @override
  final AuraLlmModelSource source = _source;

  bool installed;
  bool configured;

  @override
  int get expectedBytes => _source.sizeBytes;

  @override
  int get minimumFreeSpaceBytes => 256 * 1024 * 1024;

  @override
  bool get isConfigured => configured;

  @override
  Future<AuraLlmModelSnapshot> inspect() async => AuraLlmModelSnapshot(
    configured: configured,
    expectedBytes: _source.sizeBytes,
    installedBytes: installed ? _source.sizeBytes : null,
    partialBytes: 0,
  );

  @override
  Future<bool> verifyInstalled({
    AuraLlmHashProgressCallback? onHashProgress,
  }) async {
    if (installed) {
      onHashProgress?.call(_source.sizeBytes, _source.sizeBytes);
    }
    return installed;
  }

  @override
  Future<AuraLlmInstallResult> installModel({
    AuraLlmDownloadProgressCallback? onProgress,
    AuraLlmCancellation? cancellation,
    AuraLlmHashProgressCallback? onHashProgress,
  }) async {
    onProgress?.call(
      const AuraLlmDownloadProgress(
        receivedBytes: 1024,
        totalBytes: 1117321312,
      ),
    );
    onProgress?.call(
      const AuraLlmDownloadProgress(
        receivedBytes: 1117321312,
        totalBytes: 1117321312,
      ),
    );
    installed = true;
    return const AuraLlmInstallResult.success('/fake/model.gguf');
  }

  @override
  Future<String?> resolveInstalledModel() async =>
      installed ? '/fake/model.gguf' : null;

  @override
  Future<String?> resolveVerifiedModel() => resolveInstalledModel();

  @override
  Future<void> deleteInstalled() async {
    installed = false;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<AuraLlmSetupController> controllerFor({
    bool installed = false,
    bool configured = true,
    int? freeBytes = 8 * 1024 * 1024 * 1024,
  }) async {
    final controller = AuraLlmSetupController(
      source: _source,
      manager: _FakeProvisioner(installed: installed, configured: configured),
      storage: _FakeStorage(freeBytes),
      warmUp: () async => true,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    return controller;
  }

  Future<void> pumpSheet(
    WidgetTester tester,
    AuraLlmSetupController controller,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: AuraLlmSetupSheet(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows pinned model facts and gates the download on consent', (
    tester,
  ) async {
    final controller = await controllerFor();
    await pumpSheet(tester, controller);

    expect(find.byKey(const ValueKey('aura-llm-setup-sheet')), findsOneWidget);
    expect(find.text('Preparar Aura IA local'), findsOneWidget);
    expect(find.textContaining('1,04 GiB'), findsWidgets);
    expect(find.textContaining('f3bdf9cf31de'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
    expect(find.textContaining('unsloth'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('aura-llm-download')),
    );
    expect(button.onPressed, isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('aura-llm-consent')));
    await tester.tap(find.byKey(const ValueKey('aura-llm-consent')));
    await tester.pumpAndSettle();

    final enabled = tester.widget<FilledButton>(
      find.byKey(const ValueKey('aura-llm-download')),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('downloads, verifies and exposes the ready controls', (
    tester,
  ) async {
    final controller = await controllerFor();
    await pumpSheet(tester, controller);

    await tester.ensureVisible(find.byKey(const ValueKey('aura-llm-consent')));
    await tester.tap(find.byKey(const ValueKey('aura-llm-consent')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('aura-llm-download')));
    await tester.tap(find.byKey(const ValueKey('aura-llm-download')));
    await tester.pumpAndSettle();

    expect(controller.status, AuraLlmSetupStatus.ready);
    expect(controller.hasConsent, isTrue);
    expect(controller.runtimeReady, isTrue);
    expect(
      find.text('Runtime local cargado y listo para inferencia.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('aura-llm-delete')));
    expect(find.byKey(const ValueKey('aura-llm-delete')), findsOneWidget);
    expect(find.byKey(const ValueKey('aura-llm-prefetch')), findsOneWidget);
  });

  testWidgets('deleting requires confirmation and returns to Basic', (
    tester,
  ) async {
    final controller = await controllerFor(installed: true);
    expect(controller.status, AuraLlmSetupStatus.ready);
    await pumpSheet(tester, controller);

    await tester.ensureVisible(find.byKey(const ValueKey('aura-llm-delete')));
    await tester.tap(find.byKey(const ValueKey('aura-llm-delete')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Eliminar modelo local'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('aura-llm-delete-confirm')));
    await tester.pumpAndSettle();

    expect(controller.status, AuraLlmSetupStatus.notInstalled);
    expect(find.byKey(const ValueKey('aura-llm-download')), findsOneWidget);
  });

  testWidgets('an unpinned build never offers the download', (tester) async {
    final controller = await controllerFor(configured: false);
    await pumpSheet(tester, controller);

    expect(controller.status, AuraLlmSetupStatus.notConfigured);
    expect(find.byKey(const ValueKey('aura-llm-download')), findsNothing);
    expect(find.textContaining('no incluye un modelo fijado'), findsOneWidget);
  });

  testWidgets('the scope exposes the controller and rebuilds listeners', (
    tester,
  ) async {
    final controller = await controllerFor();
    await tester.pumpWidget(
      MaterialApp(
        home: AuraLlmSetupScope(
          controller: controller,
          child: Builder(
            builder: (context) {
              final scoped = AuraLlmSetupScope.maybeOf(context);
              return Text(
                scoped == null ? 'missing' : scoped.statusLabel,
                textDirection: TextDirection.ltr,
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Aura Básica · preparar IA'), findsOneWidget);
  });

  testWidgets('the capability ring paints every state without overflow', (
    tester,
  ) async {
    for (final state in AuraCapabilityState.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: AuraTokens.bg,
            body: Center(
              child: AuraCapabilityRing(
                size: 160,
                model: state,
                classifier: AuraCapabilityState.ready,
                defense: state,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);
    }
  });
}
