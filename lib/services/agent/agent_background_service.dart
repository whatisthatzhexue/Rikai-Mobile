import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the process alive while an Agent run is active.
///
/// The Android side is a low-importance foreground service with a partial wake
/// lock. It is started only after the run passed local validation and is
/// stopped on done/failure/cancel. All platform failures are non-fatal: losing
/// the background guarantee must never fail the analysis.
abstract interface class AgentBackgroundPort {
  Future<void> start();

  Future<void> stop();
}

class PlatformAgentBackgroundService implements AgentBackgroundPort {
  const PlatformAgentBackgroundService();

  static const MethodChannel _channel = MethodChannel('rikai/agent_background');

  @override
  Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      // Widget/unit tests and non-Android hosts have no native handler.
    } on PlatformException {
      // The OS may reject a foreground start; the run still proceeds.
    }
  }

  @override
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // No native handler.
    } on PlatformException {
      // Best effort; the service also stops with the process.
    }
  }
}
