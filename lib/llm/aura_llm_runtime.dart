import 'dart:async';

import 'package:flutter/services.dart';

/// Runtime capability report returned by the native llama.cpp bridge.
class AuraLlmCapabilities {
  const AuraLlmCapabilities({
    required this.available,
    required this.loaded,
    required this.backend,
    required this.abi,
    required this.maxContextTokens,
  });

  final bool available;
  final bool loaded;
  final String backend;
  final String abi;
  final int maxContextTokens;

  factory AuraLlmCapabilities.fromMap(Map<Object?, Object?> value) {
    final available = value['available'];
    final loaded = value['loaded'];
    final backend = value['backend'];
    final abi = value['abi'];
    final maxContextTokens = value['max_context_tokens'];

    if (available is! bool ||
        loaded is! bool ||
        backend is! String ||
        abi is! String ||
        maxContextTokens is! int ||
        maxContextTokens < 0) {
      throw const FormatException('Invalid native LLM capability response.');
    }
    return AuraLlmCapabilities(
      available: available,
      loaded: loaded,
      backend: backend,
      abi: abi,
      maxContextTokens: maxContextTokens,
    );
  }
}

/// A token, completion, or failure emitted by the native generation worker.
class AuraLlmEvent {
  const AuraLlmEvent({
    required this.operationId,
    required this.type,
    this.text,
    this.error,
  });

  final String operationId;
  final String type;
  final String? text;
  final String? error;

  factory AuraLlmEvent.fromMap(Map<Object?, Object?> value) {
    final operationId = value['operation_id'];
    final type = value['type'];
    final text = value['text'];
    final error = value['error'];
    if (operationId is! String ||
        operationId.isEmpty ||
        type is! String ||
        !const {'token', 'completed', 'error'}.contains(type) ||
        (text != null && text is! String) ||
        (error != null && error is! String)) {
      throw const FormatException('Invalid native LLM event.');
    }
    return AuraLlmEvent(
      operationId: operationId,
      type: type,
      text: text as String?,
      error: error as String?,
    );
  }
}

/// Typed, fail-closed boundary to Aura's Android-only llama.cpp runtime.
///
/// This class deliberately does not authorize or execute Aura security tools.
/// Model output remains untrusted text until AgentController validates it.
class AuraLlmRuntime {
  AuraLlmRuntime({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel = methodChannel ??
            const MethodChannel('com.ciberdefensa.aura/llm'),
       _eventChannel = eventChannel ??
            const EventChannel('com.ciberdefensa.aura/llm/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<AuraLlmEvent>? _eventStream;

  /// Subscribe before calling [startGeneration] to avoid missing early tokens.
  Stream<AuraLlmEvent> get events =>
      _eventStream ??= _eventChannel.receiveBroadcastStream().map((value) {
        if (value is! Map) {
          throw const FormatException('Native LLM event must be a map.');
        }
        return AuraLlmEvent.fromMap(Map<Object?, Object?>.from(value));
      }).asBroadcastStream();

  Future<AuraLlmCapabilities> capabilities() async {
    final response =
        await _methodChannel.invokeMapMethod<Object?, Object?>('capabilities');
    if (response == null) {
      throw const PlatformException(
        code: 'LLM_EMPTY_CAPABILITIES',
        message: 'Native LLM runtime returned no capability report.',
      );
    }
    return AuraLlmCapabilities.fromMap(response);
  }

  Future<void> loadModel({
    required String absoluteModelPath,
    required int contextTokens,
    int threads = 2,
  }) async {
    if (!absoluteModelPath.startsWith('/') ||
        absoluteModelPath.contains('..') ||
        contextTokens < 512 ||
        contextTokens > 65536 ||
        threads < 1 ||
        threads > 8) {
      throw ArgumentError('Invalid local model loading parameters.');
    }
    await _methodChannel.invokeMethod<void>('loadModel', {
      'model_path': absoluteModelPath,
      'context_tokens': contextTokens,
      'threads': threads,
    });
  }

  /// Starts generation and returns its native operation identifier.
  /// Listen to [events] first; only events with this ID belong to this request.
  Future<String> startGeneration({
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.2,
  }) async {
    if (prompt.trim().isEmpty ||
        prompt.length > 32768 ||
        maxTokens < 1 ||
        maxTokens > 4096 ||
        !temperature.isFinite ||
        temperature < 0 ||
        temperature > 2) {
      throw ArgumentError('Invalid local generation parameters.');
    }
    final operationId = await _methodChannel.invokeMethod<String>(
      'startGeneration',
      {
        'prompt': prompt,
        'max_tokens': maxTokens,
        'temperature': temperature,
      },
    );
    if (operationId == null || operationId.isEmpty) {
      throw const PlatformException(
        code: 'LLM_INVALID_OPERATION_ID',
        message: 'Native LLM runtime did not return an operation identifier.',
      );
    }
    return operationId;
  }

  Future<bool> cancel(String operationId) async {
    if (operationId.isEmpty) {
      throw ArgumentError.value(operationId, 'operationId');
    }
    return await _methodChannel.invokeMethod<bool>(
          'cancel',
          {'operation_id': operationId},
        ) ??
        false;
  }

  Future<void> unloadModel() =>
      _methodChannel.invokeMethod<void>('unloadModel');
}
