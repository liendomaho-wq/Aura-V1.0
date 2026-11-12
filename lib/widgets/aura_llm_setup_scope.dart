import 'package:flutter/widgets.dart';

import '../llm/aura_llm_setup_controller.dart';

/// Makes the model setup controller available without coupling screens or
/// tests to a global singleton. Widgets that cannot find it render Aura Básica.
class AuraLlmSetupScope extends InheritedNotifier<AuraLlmSetupController> {
  const AuraLlmSetupScope({
    super.key,
    required AuraLlmSetupController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuraLlmSetupController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuraLlmSetupScope>()?.notifier;
}
