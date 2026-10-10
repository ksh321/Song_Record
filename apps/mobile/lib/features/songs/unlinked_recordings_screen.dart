import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/recording_row.dart';
import '../auth/auth_session.dart';
import 'my_song_detail.dart';

typedef UnlinkedWatch = Stream<List<Map<String, dynamic>>> Function();

class UnlinkedRecordingsScreen extends StatefulWidget {
  const UnlinkedRecordingsScreen({required this.watch, this.auth, super.key});
  final UnlinkedWatch watch;
  final AuthController? auth;
  @override
  State<UnlinkedRecordingsScreen> createState() =>
      _UnlinkedRecordingsScreenState();
}

class _UnlinkedRecordingsScreenState extends State<UnlinkedRecordingsScreen> {
  late final String scope = tag();
  late Stream<List<Map<String, dynamic>>> stream = widget.watch();
  String tag() =>
      '${widget.auth?.phase}:${widget.auth?.session?.userId}:${widget.auth?.session?.deviceId}';
  bool invalidated = false;
  void changed() {
    if (mounted && tag() != scope) setState(() => invalidated = true);
  }

  @override
  void initState() {
    super.initState();
    widget.auth?.addListener(changed);
  }

  @override
  void dispose() {
    widget.auth?.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('곡 미연결 녹음')),
    body: SafeArea(
      child: invalidated || tag() != scope
          ? const ContentState(
              phase: ContentPhase.waiting,
              title: '계정이 변경됐어요. 내 곡 목록에서 다시 열어 주세요.',
            )
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ContentState(
                    phase: ContentPhase.error,
                    title: '미연결 녹음을 불러오지 못했어요.',
                    onRetry: () => setState(() => stream = widget.watch()),
                  );
                }
                if (!snapshot.hasData) {
                  return const ContentState(
                    phase: ContentPhase.loading,
                    title: '미연결 녹음을 불러오고 있어요.',
                  );
                }
                final recordings = MySongDetail({
                  'song': null,
                  'revision': 0,
                  'recordings': snapshot.data!,
                }).recordings;
                if (recordings.isEmpty) {
                  return const ContentState(
                    phase: ContentPhase.empty,
                    title: '곡 미연결 녹음이 없어요.',
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text('곡 미연결 녹음 ${recordings.length}개'),
                    for (final r in recordings)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: RecordingRow(recording: r),
                      ),
                  ],
                );
              },
            ),
    ),
  );
}
