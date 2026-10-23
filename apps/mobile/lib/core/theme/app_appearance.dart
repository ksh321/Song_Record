import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppAppearance extends InheritedNotifier<ValueNotifier<bool>> {
  const AppAppearance({
    required ValueNotifier<bool> light,
    required super.child,
    super.key,
  }) : super(notifier: light);
  static ValueNotifier<bool>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppAppearance>()?.notifier;
  static const channel = MethodChannel('song_record/device_settings');
}

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});
  @override
  Widget build(BuildContext context) {
    final value = AppAppearance.of(context);
    if (value == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: value.value ? '다크 모드 켜기' : '다크 모드 끄기',
      icon: const Icon(Icons.dark_mode_outlined),
      onPressed: () async {
        value.value = !value.value;
        try {
          await AppAppearance.channel.invokeMethod<void>('writeLightMode', {
            'light': value.value,
          });
        } on PlatformException catch (_) {
        } on MissingPluginException catch (_) {}
      },
    );
  }
}
