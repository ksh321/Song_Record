import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_tokens.dart';

enum ContentPhase { loading, empty, error, waiting }

/// Display only. The caller supplies the actual request or operation state.
/// Waiting is not loading and does not imply an active network request.
class ContentState extends StatelessWidget {
  const ContentState({
    required this.phase,
    required this.title,
    this.message,
    this.onRetry,
    super.key,
  }) : assert(onRetry == null || phase == ContentPhase.error);

  final ContentPhase phase;
  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations || media.accessibleNavigation;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (phase == ContentPhase.loading && !reduceMotion)
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Icon(
                switch (phase) {
                  ContentPhase.loading => Icons.hourglass_top,
                  ContentPhase.empty => Icons.music_note_outlined,
                  ContentPhase.error => Icons.cloud_off_outlined,
                  ContentPhase.waiting => Icons.schedule,
                },
                size: 32,
                color: AppColors.muted,
              ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, textAlign: TextAlign.center, style: AppTypography.songTitle),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(message!, textAlign: TextAlign.center, style: AppTypography.supporting),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              Center(
                child: OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
