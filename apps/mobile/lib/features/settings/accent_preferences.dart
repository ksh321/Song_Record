import 'package:flutter/services.dart';

import '../../core/theme/app_tokens.dart';

abstract interface class AccentPreferences {
  Future<AppAccent?> read();
  Future<void> write(AppAccent accent);
}

/// Installation/device preference. Not an account, sync or backup record.
class DeviceAccentPreferences implements AccentPreferences {
  const DeviceAccentPreferences();
  static const channel = MethodChannel('song_record/device_settings');
  @override
  Future<AppAccent?> read() async {
    final id = await channel.invokeMethod<String>('readAccent');
    for (final accent in AppAccent.values) {
      if (accent.id == id) return accent;
    }
    return null;
  }

  @override
  Future<void> write(AppAccent accent) =>
      channel.invokeMethod<void>('writeAccent', {'accent': accent.id});
}
