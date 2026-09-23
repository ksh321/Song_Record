import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_tokens.dart';

/// A null route result means cancellation. A result containing null means
/// an explicit choice of an unset value (for example, a tier).
class SelectionResult<T> {
  const SelectionResult(this.value);
  final T value;
}

class SelectionOption<T> {
  const SelectionOption(this.value, this.label, {this.description});
  final T value;
  final String label;
  final String? description;
}

Future<SelectionResult<T>?> showSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<SelectionOption<T>> options,
  String? description,
}) {
  final choices = List<SelectionOption<T>>.unmodifiable(options);
  if (choices.isEmpty ||
      choices.map((option) => option.value).toSet().length != choices.length ||
      !choices.any((option) => option.value == selected)) {
    throw ArgumentError('선택지는 중복 없이 현재 값을 포함해야 합니다.');
  }
  final media = MediaQuery.of(context);
  return showModalBottomSheet<SelectionResult<T>>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: AppColors.sheetBackground,
    barrierColor: AppColors.sheetScrim,
    barrierLabel: '선택 취소',
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
    builder: (sheetContext) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: AppDimensions.sheetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: AppTypography.sheetTitle),
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(description, style: AppTypography.supporting),
            ],
            const SizedBox(height: AppSpacing.md),
            for (final option in choices)
              Semantics(
                selected: option.value == selected,
                inMutuallyExclusiveGroup: true,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.label, style: AppTypography.sheetOption),
                  subtitle: option.description == null
                      ? null
                      : Text(
                          option.description!,
                          style: AppTypography.supporting,
                        ),
                  trailing: option.value == selected
                      ? const Icon(Icons.check, semanticLabel: '선택됨')
                      : null,
                  onTap: () =>
                      Navigator.of(sheetContext)
                          .pop(SelectionResult<T>(option.value)),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('취소'),
            ),
          ],
        ),
      ),
    ),
  );
}
