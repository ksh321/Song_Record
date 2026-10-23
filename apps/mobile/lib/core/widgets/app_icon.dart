import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The same outline paths used by the approved HTML, in one shared renderer.
/// Unmapped platform/system actions retain their standard Material symbol.
class AppIcon extends Icon {
  const AppIcon(
    super.icon, {
    super.size,
    super.color,
    super.semanticLabel,
    super.key,
  });
  static const music =
      '<path d="M9 18V5l12-2v13M9 9l12-2"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>';
  static const mic =
      '<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3M8 22h8"/>';
  static const list = '<path d="M4 5h13M4 10h13M4 15h8M18 14v6M15 17h6"/>';
  static const search =
      '<circle cx="10.8" cy="10.8" r="7"/><path d="m16 16 5 5"/>';
  static const heart =
      '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/>';
  static final paths = <IconData, String>{
    Icons.library_music_outlined: music,
    Icons.library_music: music,
    Icons.music_note_outlined: music,
    Icons.music_note: music,
    Icons.bar_chart: '<path d="M5 20V10M12 20V4M19 20V13"/>',
    Icons.bar_chart_outlined: '<path d="M5 20V10M12 20V4M19 20V13"/>',
    Icons.mic: mic,
    Icons.mic_none: mic,
    Icons.mic_outlined: mic,
    Icons.queue_music: list,
    Icons.queue_music_outlined: list,
    Icons.playlist_add: list,
    Icons.search: search,
    Icons.chevron_right: '<path d="m9 5 7 7-7 7"/>',
    Icons.arrow_back: '<path d="m15 5-7 7 7 7"/>',
    Icons.more_vert: '<circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>',
    Icons.dark_mode_outlined:
        '<path d="M20.5 13.2A8.7 8.7 0 0 1 10.8 3.5a8.8 8.8 0 1 0 9.7 9.7Z"/>',
    Icons.settings_outlined: '<path d="m9.2 3-.7 2.1-2 .9-2.1-.4-1.5 2.6 1.4 1.7-.2 2.2-1.4 1.7 1.5 2.6 2.2-.4 1.8 1.1.7 2.2h3l.8-2.1 1.9-1 2.2.4 1.5-2.6-1.4-1.7.1-2.2 1.4-1.7-1.5-2.6-2.2.4-1.8-1.1-.7-2.1z" transform="translate(1 1)"/><circle cx="12" cy="12" r="3.2"/>',
    Icons.favorite_border: heart,
    Icons.favorite: heart,
    Icons.edit_outlined: '<path d="m16 3 5 5-12 12-6 1 1-6zM14 5l5 5"/>',
    Icons.schedule: '<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
    Icons.graphic_eq: '<path d="M4 10v4M8 5v14M12 2v20M16 6v12M20 9v6"/>',
    Icons.sort: '<path d="M7 4v16m-4-4 4 4 4-4M14 5h7m-7 5h5m-5 5h3"/>',
    Icons.filter_list: '<path d="M4 6h16M7 12h10M10 18h4"/>',
    Icons.add: '<path d="M12 5v14M5 12h14"/>',
    Icons.star_border: '<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9Z"/>',
    Icons.headphones_outlined: '<path d="M3 14v-3a9 9 0 0 1 18 0v3"/><rect x="3" y="12" width="4" height="9" rx="2"/><rect x="17" y="12" width="4" height="9" rx="2"/>',
    Icons.wb_sunny_outlined: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5 19 19M5 19l1.5-1.5M17.5 6.5 19 5"/>',
    Icons.people_outline: '<circle cx="9" cy="7" r="3"/><path d="M3 21v-3a6 6 0 0 1 12 0v3M16 4a3 3 0 0 1 0 6M17 13a5 5 0 0 1 4 5v3"/>',
    Icons.storage_outlined:
        '<path d="M6 19a5 5 0 0 1-1-10 7 7 0 0 1 13-2 6 6 0 0 1 0 12Z"/>',
    Icons.sync:
        '<path d="M6 19a5 5 0 0 1-1-10 7 7 0 0 1 13-2 6 6 0 0 1 0 12Z"/>',
    Icons.archive_outlined:
        '<path d="M5 3h9l5 5v13H5zM14 3v6h5M9 14h6M9 17h6"/>',
    Icons.unarchive_outlined:
        '<path d="M5 3h9l5 5v13H5zM14 3v6h5M9 14h6M9 17h6"/>',
    Icons.delete_outline:
        '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/>',
    Icons.push_pin_outlined: '<path d="m9 3 6 0-1 6 4 4H6l4-4zM12 13v8"/>',
  };
  @override
  Widget build(BuildContext context) {
    final path = paths[icon];
    if (path == null) {
      return super.build(context);
    }
    final theme = IconTheme.of(context), effective = size ?? theme.size ?? 22;
    final fill = icon == Icons.favorite ? 'currentColor' : 'none';
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="$fill" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">$path</svg>',
      width: effective,
      height: effective,
      semanticsLabel: semanticLabel,
      colorFilter: ColorFilter.mode(
        color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
        BlendMode.srcIn,
      ),
    );
  }
}
