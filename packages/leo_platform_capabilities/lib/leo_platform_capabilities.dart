import 'package:flutter/services.dart';

/// Thin adapter over native OS APIs. It intentionally contains no permission
/// policy or AI decisions; those belong to Leo's Capability Hub.
class LeoPlatformCapabilities {
  LeoPlatformCapabilities({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('ai.leo/platform_capabilities');

  final MethodChannel _channel;

  Future<String> getPlatform() async =>
      await _channel.invokeMethod<String>('getPlatform') ?? 'unknown';

  /// Returns the current OS-level grant state. Leo must still check its own
  /// separately persisted consent before invoking a capability.
  Future<bool> checkOsPermission(String capabilityId) async {
    try {
      return await _channel.invokeMethod<bool>(
            'checkOsPermission',
            <String, Object?>{'capabilityId': capabilityId},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Requests a permission only after the user has approved Leo's explanation.
  Future<bool> requestOsPermission(String capabilityId) async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestOsPermission',
            <String, Object?>{'capabilityId': capabilityId},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }


  /// Opens the Windows microphone privacy page. Windows desktop microphone
  /// access is controlled by OS privacy settings rather than a runtime prompt.
  Future<bool> openWindowsMicrophonePrivacySettings() async {
    try {
      return await _channel.invokeMethod<bool>(
            'openMicrophonePrivacySettings',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<Map<String, Object?>> execute(
    String operation, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'executeCapability',
      <String, Object?>{
        'operation': operation,
        'arguments': arguments,
      },
    );
    if (result == null) {
      throw PlatformException(
        code: 'empty_native_result',
        message: 'لم يُرجع نظام التشغيل نتيجة للعملية المطلوبة.',
      );
    }
    return result.map((key, value) => MapEntry(key.toString(), value));
  }
}
