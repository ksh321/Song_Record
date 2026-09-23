import 'package:flutter/material.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/core/widgets/selection_sheet.dart';

/// The song's representative key is optional. A cancelled sheet returns null;
/// an explicit "미정으로 두기" returns a SelectionResult containing null.
abstract final class MusicalKeyPicker {
  static Future<SelectionResult<MusicalKey?>?> song({
    required BuildContext context,
    required MusicalKey? selected,
  }) => _show(context: context, selected: selected, allowUnset: true);

  /// A saved recording always has a key. Its initial value is ORIGINAL + 0.
  static Future<SelectionResult<MusicalKey>?> recording({
    required BuildContext context,
    MusicalKey selected = MusicalKey.original,
  }) async {
    final result = await _show(
      context: context,
      selected: selected,
      allowUnset: false,
    );
    return result == null ? null : SelectionResult(result.value!);
  }

  static Future<SelectionResult<MusicalKey?>?> _show({
    required BuildContext context,
    required MusicalKey? selected,
    required bool allowUnset,
  }) {
    final media = MediaQuery.of(context);
    return showModalBottomSheet<SelectionResult<MusicalKey?>>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: AppColors.sheetBackground,
      barrierColor: AppColors.sheetScrim,
      barrierLabel: '키 선택 취소',
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimensions.sheetTopRadius),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(
        maxHeight: media.size.height * AppDimensions.sheetMaxHeightFactor,
      ),
      sheetAnimationStyle: media.disableAnimations || media.accessibleNavigation
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: AppDimensions.sheetAnimationDuration,
              reverseDuration: AppDimensions.sheetAnimationDuration,
            ),
      builder: (sheetContext) => _KeySheet(
        initial: selected,
        allowUnset: allowUnset,
        onApply: (key) =>
            Navigator.of(sheetContext).pop(SelectionResult<MusicalKey?>(key)),
        onUnset: () =>
            Navigator.of(sheetContext)
                .pop(const SelectionResult<MusicalKey?>(null)),
        onCancel: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }
}

class _KeySheet extends StatefulWidget {
  const _KeySheet({
    required this.initial,
    required this.allowUnset,
    required this.onApply,
    required this.onUnset,
    required this.onCancel,
  });

  final MusicalKey? initial;
  final bool allowUnset;
  final ValueChanged<MusicalKey> onApply;
  final VoidCallback onUnset;
  final VoidCallback onCancel;

  @override
  State<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<_KeySheet> {
  late KeyMode _mode;
  late int _shift;
  late FixedExtentScrollController _wheel;

  @override
  void initState() {
    super.initState();
    _mode = widget.initial?.mode ?? KeyMode.original;
    _shift = widget.initial?.shift ?? 0;
    _wheel = FixedExtentScrollController(
      initialItem: _shift - AppDimensions.keyWheelMin,
    );
  }

  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  void _choose(int value) {
    if (value < AppDimensions.keyWheelMin ||
        value > AppDimensions.keyWheelMax) {
      return;
    }
    setState(() => _shift = value);
    if (!_wheel.hasClients) return;
    final index = value - AppDimensions.keyWheelMin;
    final media = MediaQuery.of(context);
    if (media.disableAnimations || media.accessibleNavigation) {
      _wheel.jumpToItem(index);
    } else {
      _wheel.animateToItem(
        index,
        duration: AppDimensions.sheetAnimationDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _number(int value) => value > 0 ? '+$value' : '$value';

  @override
  Widget build(BuildContext context) {
    final chosen = MusicalKey(mode: _mode, shift: _shift);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: AppDimensions.sheetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('키 선택', style: AppTypography.sheetTitle),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.allowUnset
                  ? '곡의 대표 키를 선택해 주세요. 미정으로 둘 수도 있어요.'
                  : '이번 녹음의 키를 선택해 주세요.',
              style: AppTypography.supporting,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('모드', style: AppTypography.sheetOption),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final mode in KeyMode.values)
                  ChoiceChip(
                    label: Text(switch (mode) {
                      KeyMode.original => '원키',
                      KeyMode.male => '남',
                      KeyMode.female => '여',
                    }),
                    selected: _mode == mode,
                    onSelected: (_) => setState(() => _mode = mode),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              liveRegion: true,
              child: Text(
                '선택할 키: ${formatMusicalKey(chosen)}',
                key: const ValueKey('key-readout'),
                style: AppTypography.sheetTitle,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              label: '반음 선택',
              value: _number(_shift),
              increasedValue: _shift < AppDimensions.keyWheelMax
                  ? _number(_shift + 1)
                  : null,
              decreasedValue: _shift > AppDimensions.keyWheelMin
                  ? _number(_shift - 1)
                  : null,
              onIncrease: _shift < AppDimensions.keyWheelMax
                  ? () => _choose(_shift + 1)
                  : null,
              onDecrease: _shift > AppDimensions.keyWheelMin
                  ? () => _choose(_shift - 1)
                  : null,
              explicitChildNodes: true,
              child: SizedBox(
                height: AppDimensions.keyWheelHeight,
                child: Stack(
                  children: [
                    ListWheelScrollView(
                      key: const ValueKey('semitone-wheel'),
                      controller: _wheel,
                      itemExtent: AppDimensions.keyWheelItemHeight,
                      physics: const FixedExtentScrollPhysics(),
                      diameterRatio: 10,
                      perspective: 0.001,
                      onSelectedItemChanged: (index) {
                        final next = index + AppDimensions.keyWheelMin;
                        if (next != _shift) setState(() => _shift = next);
                      },
                      children: [
                        for (
                          var value = AppDimensions.keyWheelMin;
                          value <= AppDimensions.keyWheelMax;
                          value++
                        )
                          Semantics(
                            label: '${_number(value)} 반음',
                            selected: _shift == value,
                            button: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _choose(value),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _number(value),
                                    style: TextStyle(
                                      fontSize: _shift == value
                                          ? AppTypography.keyWheelSelectedSize
                                          : AppTypography.keyWheelSize,
                                      fontWeight: _shift == value
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                      color: _shift == value
                                          ? AppColors.text
                                          : AppColors.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          height: AppDimensions.keyWheelItemHeight,
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: AppColors.sheetBorder),
                              bottom: BorderSide(color: AppColors.sheetBorder),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              '위아래로 밀어 선택 · 한 칸 = 반음 · −12 ~ +12',
              style: AppTypography.supporting,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const ValueKey('apply-key'),
              onPressed: () => widget.onApply(chosen),
              child: const Text('적용'),
            ),
            if (widget.allowUnset) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: widget.onUnset,
                child: const Text('미정으로 두기'),
              ),
            ],
            TextButton(onPressed: widget.onCancel, child: const Text('취소')),
          ],
        ),
      ),
    );
  }
}
