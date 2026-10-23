import 'package:flutter/material.dart';

import 'app_icon.dart';

/// Shared across own songs, playlists and recordings.
class TierBadge extends StatelessWidget {
  const TierBadge(this.label, {this.size = 33, super.key});
  final String label;
  final double size;
  static const colors = <String, (Color, Color)>{
    'S': (Color(0xfff6d879), Color(0xff614500)),
    'A': (Color(0xfff2b079), Color(0xff703900)),
    'B': (Color(0xffa4cfad), Color(0xff285735)),
    'C': (Color(0xffa4bdd5), Color(0xff314e6b)),
    'D': (Color(0xffb7b0c2), Color(0xff4c435b)),
  };
  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final pair =
        colors[label] ??
        (
          light ? const Color(0xffeeeeee) : const Color(0xffd5d9e0),
          const Color(0xff535b68),
        );
    return Semantics(
      label: '티어 $label',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pair.$1,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: pair.$2,
            fontSize: label == '미정' ? 10 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class SongSuitabilityChoice extends StatelessWidget {
  const SongSuitabilityChoice({
    required this.value,
    required this.onChanged,
    super.key,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 17,
            height: 24,
            child: Checkbox(
              value: value,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: onChanged == null
                  ? null
                  : (v) => onChanged!(v ?? false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(
                      Icons.favorite,
                      size: 19,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        '나에게 어울리는 곡',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '실력과 관계없이 내 음색·창법에 잘 맞는 곡',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
