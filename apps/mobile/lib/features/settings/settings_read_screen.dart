import 'dart:async';

import 'package:flutter/material.dart';
import 'package:song_record/core/widgets/app_page_bar.dart';

import '../../core/widgets/ui_controls.dart';

/// Actual state only: unavailable data is never replaced by example numbers.
class SettingsReadScreen extends StatefulWidget {
  const SettingsReadScreen({
    required this.title,
    required this.load,
    required this.requireCurrent,
    this.accountChanges,
    super.key,
  });
  final String title;
  final Future<List<(String, String)>> Function() load;
  final VoidCallback requireCurrent;
  final Listenable? accountChanges;
  @override
  State<SettingsReadScreen> createState() => _State();
}

class _State extends State<SettingsReadScreen> {
  List<(String, String)>? rows;
  bool busy = false, failed = false;
  int generation = 0;
  void accountChanged() {
    try {
      widget.requireCurrent();
    } catch (_) {
      generation++;
      if (mounted) {
        setState(() {
          rows = null;
          failed = true;
          busy = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    widget.accountChanges?.addListener(accountChanged);
    unawaited(refresh());
  }

  @override
  void dispose() {
    generation++;
    widget.accountChanges?.removeListener(accountChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsReadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountChanges != widget.accountChanges) {
      oldWidget.accountChanges?.removeListener(accountChanged);
      widget.accountChanges?.addListener(accountChanged);
    }
    if (oldWidget.load != widget.load ||
        oldWidget.requireCurrent != widget.requireCurrent) {
      generation++;
      rows = null;
      busy = false;
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (busy) return;
    final epoch = ++generation;
    setState(() {
      busy = true;
      failed = false;
      rows = null;
    });
    try {
      widget.requireCurrent();
      final value = await widget.load();
      widget.requireCurrent();
      if (mounted && epoch == generation) setState(() => rows = value);
    } catch (_) {
      if (mounted && epoch == generation) {
        setState(() {
          failed = true;
          rows = null;
        });
      }
    } finally {
      if (mounted && epoch == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appPageBar(context, title: Text(widget.title)),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: AppLayout.bodyPadding,
        children: [
          if (busy) const LinearProgressIndicator(),
          if (failed) const Text('정보를 읽지 못했어요. 연결·로그인 상태를 확인해 주세요.'),
          if (!busy && rows?.isEmpty == true) const Text('표시할 정보가 없습니다.'),
          for (final (label, value) in rows ?? const <(String, String)>[])
            ListTile(title: Text(label), subtitle: Text(value)),
          FilledButton(
            onPressed: busy ? null : refresh,
            child: const Text('새로고침'),
          ),
        ],
      ),
    ),
  );
}
