import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const underlyingNetworkChannelName = 'com.ciberdefensa.aura/underlying_network';

void mockUnderlyingNetwork({
  String kind = 'none',
  String label = 'Sin conexión',
}) {
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler(underlyingNetworkChannelName, (
    message,
  ) async {
    if (message == null) return null;
    final call = codec.decodeMethodCall(message);
    if (call.method == 'listen') {
      messenger.handlePlatformMessage(
        underlyingNetworkChannelName,
        codec.encodeSuccessEnvelope(<String, String>{
          'kind': kind,
          'label': label,
        }),
        (_) {},
      );
    }
    return codec.encodeSuccessEnvelope(null);
  });
}

void clearUnderlyingNetworkMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(underlyingNetworkChannelName, null);
}
