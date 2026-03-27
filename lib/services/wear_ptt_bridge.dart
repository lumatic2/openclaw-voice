import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../state/app_phase.dart';

class WearPttBridge {
  static const _channel = MethodChannel('com.luma3.ptt/wear');
  bool _initialized = false;

  Future<void> initialize({
    required Future<void> Function() onToggleRequested,
  }) async {
    if (!Platform.isAndroid || _initialized) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onToggle') {
        await onToggleRequested();
      }
    });
    _initialized = true;
  }

  Future<void> pushState(AppPhase phase) async {
    if (!Platform.isAndroid || !_initialized) return;

    try {
      await _channel.invokeMethod('pushState', {
        'status': _phaseToStatus(phase),
      });
    } on MissingPluginException {
      // Wear OS not available on this device
    }
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _channel.setMethodCallHandler(null);
    _initialized = false;
  }

  String _phaseToStatus(AppPhase phase) {
    switch (phase) {
      case AppPhase.idle:
        return 'idle';
      case AppPhase.recording:
        return 'recording';
      case AppPhase.thinking:
        return 'thinking';
      case AppPhase.speaking:
        return 'speaking';
      case AppPhase.error:
        return 'error';
    }
  }
}
