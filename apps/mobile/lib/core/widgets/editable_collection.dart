import 'package:flutter/material.dart';

import 'scroll_to_top_button.dart';

class CollectionRowEditing extends InheritedWidget {
  const CollectionRowEditing({
    super.key,
    required this.active,
    required super.child,
  });
  final bool active;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CollectionRowEditing>()
          ?.active ??
      false;
  @override
  bool updateShouldNotify(CollectionRowEditing oldWidget) =>
      active != oldWidget.active;
}

/// One selection/reorder surface for library lists. The scrollable and row keys
/// survive mode changes and drops; only explicit handles initiate a drag.
class EditableCollection extends StatefulWidget {
  const EditableCollection({
    super.key,
    required this.ids,
    required this.row,
    required this.header,
    required this.actions,
    required this.onDelete,
    required this.deleteLabel,
    this.onReorder,
    this.onBeginReorder,
    this.selectionIds,
    this.belowActions,
    this.onHeaderFold,
    this.onRefresh,
    this.footer = const SizedBox.shrink(),
    this.enabled = true,
    this.rowSpacing = 8,
    this.showScrollToTop = false,
  });
  final List<String> ids;
  final List<String>? selectionIds;
  final VoidCallback? onBeginReorder;
  final Widget Function(String) row;
  final Widget header;
  final Widget? belowActions;
  final ValueChanged<bool>? onHeaderFold;
  final Future<void> Function()? onRefresh;
  final Widget footer;
  final Widget Function(bool compact, VoidCallback? reorder) actions;
  final Future<bool> Function(List<String>) onDelete;
  final Future<void> Function(List<String>)? onReorder;
  final String Function(int) deleteLabel;
  final bool enabled;
  final double rowSpacing;
  final bool showScrollToTop;
  @override
  State<EditableCollection> createState() => _EditableCollectionState();
}

class _EditableCollectionState extends State<EditableCollection> {
  final scroll = ScrollController();
  final selected = <String>{};
  final rowKeys = <String, GlobalKey>{};
  final rowHeights = <String, double>{};
  void captureRowHeights() {
    for (final entry in rowKeys.entries) {
      final render = entry.value.currentContext?.findRenderObject();
      if (render is RenderBox && render.hasSize) {
        rowHeights[entry.key] = render.size.height;
      }
    }
  }

  List<String>? ordering;
  bool selecting = false, saving = false;
  bool folded = false;
  void endOrder() {
    ordering = null;
    if (folded) widget.onHeaderFold?.call(false);
    folded = false;
  }

  String? failure;
  @override
  void didUpdateWidget(covariant EditableCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    selected.retainAll(widget.selectionIds ?? widget.ids);
    // A remote membership change invalidates an in-progress order. Never
    // silently drop a new item or reintroduce a removed item on save.
    if (ordering != null &&
        (ordering!.length != widget.ids.length ||
            !ordering!.toSet().containsAll(widget.ids))) {
      ordering = null;
      if (folded) {
        folded = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ordering == null) widget.onHeaderFold?.call(false);
        });
      }
      failure = '목록이 변경됐어요. 다시 순서를 선택해 주세요.';
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void toggle(String id) => setState(() {
    if (!selected.add(id)) selected.remove(id);
  });
  void toggleAll() => setState(() {
    final selectable = widget.selectionIds ?? widget.ids;
    final allSelected = selectable.every(selected.contains);
    selected.clear();
    if (!allSelected) selected.addAll(selectable);
  });
  void beginReorder() => setState(() {
    captureRowHeights();
    widget.onBeginReorder?.call();
    folded =
        scroll.hasClients && scroll.offset <= 12 && widget.onHeaderFold != null;
    widget.onHeaderFold?.call(folded);
    ordering = List.of(widget.ids);
    failure = null;
  });

  Future<void> commit() async {
    setState(() {
      saving = true;
      failure = null;
    });
    try {
      if (ordering != null) {
        await widget.onReorder!(List.of(ordering!));
      } else {
        final deleted = await widget.onDelete(
          (widget.selectionIds ?? widget.ids).where(selected.contains).toList(),
        );
        if (!deleted) return;
      }
      if (mounted) {
        setState(() {
          endOrder();
          selecting = false;
          selected.clear();
        });
      }
    } catch (_) {
      if (mounted) setState(() => failure = '저장하지 못했어요. 목록을 확인한 뒤 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = ordering ?? widget.ids;
    final selectable = widget.selectionIds ?? widget.ids;
    final enabled = widget.enabled && !saving;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !selecting && ordering == null && !saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !saving) {
          setState(() {
            selecting = false;
            selected.clear();
            endOrder();
          });
        }
      },
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: widget.onRefresh ?? () async {},
            notificationPredicate: (notification) =>
                widget.onRefresh != null &&
                !selecting &&
                ordering == null &&
                notification.depth == 0,
            child: CustomScrollView(
              controller: scroll,
              physics: widget.onRefresh == null
                  ? null
                  : const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: widget.onHeaderFold == null
                        ? widget.header
                        : AnimatedSize(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 250),
                            alignment: Alignment.topCenter,
                            child: folded
                                ? const SizedBox.shrink()
                                : widget.header,
                          ),
                  ),
                ),
                if (widget.belowActions != null)
                  SliverPersistentHeader(
                    pinned: !selecting && ordering == null,
                    delegate: _CollectionBar(
                      extent: folded ? 0 : 52,
                      builder: (compact) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Visibility(
                          visible: !selecting && ordering == null,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: widget.actions(
                            compact,
                            enabled &&
                                    widget.onReorder != null &&
                                    ids.length > 1
                                ? beginReorder
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                SliverPersistentHeader(
                  pinned:
                      widget.belowActions == null ||
                      selecting ||
                      ordering != null,
                  delegate: _CollectionBar(
                    builder: (compact) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: selecting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _control(
                                  context,
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Checkbox(
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        value:
                                            ids.isNotEmpty &&
                                            selected.length ==
                                                selectable.length,
                                        onChanged: enabled
                                            ? (_) => toggleAll()
                                            : null,
                                      ),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            const TextSpan(text: '전체 '),
                                            TextSpan(
                                              text: '${selected.length}',
                                              style: TextStyle(
                                                color: colors.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  enabled ? toggleAll : null,
                                  leftPadding: 4,
                                ),
                                _control(
                                  context,
                                  const Text('취소'),
                                  enabled
                                      ? () => setState(() {
                                          selecting = false;
                                          selected.clear();
                                        })
                                      : null,
                                ),
                              ],
                            )
                          : ordering != null
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _control(
                                  context,
                                  const Text('취소'),
                                  enabled ? () => setState(endOrder) : null,
                                ),
                                _control(
                                  context,
                                  Text(saving ? '저장 중' : '완료'),
                                  enabled ? commit : null,
                                ),
                              ],
                            )
                          : widget.belowActions ??
                                widget.actions(
                                  compact,
                                  enabled &&
                                          widget.onReorder != null &&
                                          ids.length > 1
                                      ? beginReorder
                                      : null,
                                ),
                    ),
                  ),
                ),
                if (failure != null)
                  SliverToBoxAdapter(
                    child: Text(
                      failure!,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverReorderableList(
                    itemCount: ids.length,
                    onReorderItem: (from, to) {
                      if (ordering == null || !enabled) return;
                      setState(() {
                        final id = ordering!.removeAt(from);
                        ordering!.insert(to, id);
                      });
                    },
                    proxyDecorator: (child, index, animation) => Material(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      shape: null,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.primary, width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: child,
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final id = ids[index];
                      return Padding(
                        key: ValueKey(id),
                        padding: EdgeInsets.only(bottom: widget.rowSpacing),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: enabled && ordering == null
                              ? () => setState(() {
                                  captureRowHeights();
                                  selecting = true;
                                  selected.add(id);
                                })
                              : null,
                          onTap: selecting && enabled ? () => toggle(id) : null,
                          child: SizedBox(
                            key: rowKeys.putIfAbsent(id, GlobalKey.new),
                            height: selecting || ordering != null
                                ? rowHeights[id]
                                : null,
                            child: Row(
                              children: [
                                if (selecting)
                                  SizedBox(
                                    width: 36,
                                    child: Checkbox(
                                      value: selected.contains(id),
                                      onChanged: enabled
                                          ? (_) => toggle(id)
                                          : null,
                                    ),
                                  ),
                                Expanded(
                                  child: IgnorePointer(
                                    ignoring:
                                        selecting ||
                                        ordering != null ||
                                        !enabled,
                                    child: CollectionRowEditing(
                                      active: selecting || ordering != null,
                                      child: selecting || ordering != null
                                          ? DefaultTextStyle.merge(
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              child: widget.row(id),
                                            )
                                          : widget.row(id),
                                    ),
                                  ),
                                ),
                                if (ordering != null)
                                  ReorderableDragStartListener(
                                    index: index,
                                    enabled: enabled,
                                    child: const SizedBox(
                                      width: 44,
                                      height: 56,
                                      child: Icon(Icons.drag_handle),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(child: widget.footer),
                SliverToBoxAdapter(
                  child: SizedBox(height: selecting ? 80 : 16),
                ),
              ],
            ),
          ),
          if (widget.showScrollToTop && !selecting && ordering == null)
            Positioned(
              right: 16,
              bottom: 16,
              child: ScrollToTopButton(controller: scroll),
            ),
          if (selecting)
            Positioned(
              left: 16,
              right: 16,
              bottom: 8,
              child: SafeArea(
                top: false,
                child: FilledButton(
                  onPressed: enabled && selected.isNotEmpty ? commit : null,
                  child: Text(widget.deleteLabel(selected.length)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _control(
    BuildContext context,
    Widget child,
    VoidCallback? tap, {
    double leftPadding = 12,
  }) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    child: InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 44,
        padding: EdgeInsets.only(left: leftPadding, right: 12),
        alignment: Alignment.center,
        child: DefaultTextStyle(
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _CollectionBar extends SliverPersistentHeaderDelegate {
  _CollectionBar({required this.builder, this.extent = 52});
  final Widget Function(bool) builder;
  final double extent;
  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    if (extent == 0) return const SizedBox.shrink();
    final scrolled = shrinkOffset > 0 || overlapsContent;
    return SizedBox(height: maxExtent, child: builder(scrolled));
  }

  @override
  bool shouldRebuild(covariant _CollectionBar oldDelegate) => true;
}

class CollectionControlSurface extends StatelessWidget {
  const CollectionControlSurface({
    required this.active,
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });
  final bool active;
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('collection-control-surface'),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: .10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
