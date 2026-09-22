import 'package:flutter/material.dart';

/// The five destinations, in the order fixed by design section 2.1.
enum AppTab {
  songs(
    label: '내 곡',
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music,
    introduction: '내 곡과 연습 기록을 한곳에서',
  ),
  charts(
    label: '인기 차트',
    icon: Icons.bar_chart_outlined,
    selectedIcon: Icons.bar_chart,
    introduction: '인기 있는 곡을 찾아보세요',
  ),
  recording(
    label: '녹음',
    icon: Icons.mic_none,
    selectedIcon: Icons.mic,
    introduction: '노래를 녹음하고 기록해요',
  ),
  playlists(
    label: '플레이리스트',
    icon: Icons.queue_music_outlined,
    selectedIcon: Icons.queue_music,
    introduction: '함께 부를 곡을 모아보세요',
  ),
  search(
    label: '검색',
    icon: Icons.search,
    selectedIcon: Icons.search,
    introduction: '곡명과 가수로 새 곡을 찾아보세요',
  );

  const AppTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.introduction,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String introduction;
}
