import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The four corners a floating control can sit in.
enum Corner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get isLeft => this == topLeft || this == bottomLeft;
  bool get isTop => this == topLeft || this == topRight;

  static Corner fromName(String? name, Corner fallback) =>
      values.firstWhere((c) => c.name == name, orElse: () => fallback);
}

/// A control that floats in one corner of its Stack and can be dragged to
/// another. On release it glides to the nearest corner that [blocked] (the
/// other floating control's corner) isn't using, so two never overlap.
///
/// Must be a direct child of a [Stack]. A plain tap still reaches [child]:
/// dragging only starts once the finger actually moves.
class CornerFloat extends StatefulWidget {
  const CornerFloat({
    super.key,
    required this.corner,
    required this.blocked,
    required this.area,
    required this.onCornerChanged,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(16, 14, 16, 16),
  });

  final Corner corner;
  final Corner blocked;

  /// The size of the Stack this floats in.
  final Size area;
  final ValueChanged<Corner> onCornerChanged;
  final Widget child;

  /// Space kept between the control and the area's edges.
  final EdgeInsets margin;

  @override
  State<CornerFloat> createState() => _CornerFloatState();
}

class _CornerFloatState extends State<CornerFloat> {
  Size? _size;

  /// Where the finger has dragged the control to (top-left), while dragging.
  Offset? _dragAt;

  Offset _cornerOrigin(Corner c, Size size) {
    final m = widget.margin;
    final a = widget.area;
    return Offset(
      c.isLeft ? m.left : a.width - size.width - m.right,
      c.isTop ? m.top : a.height - size.height - m.bottom,
    );
  }

  Corner _nearestFree(Offset topLeft, Size size) {
    final center = topLeft + size.center(Offset.zero);
    final candidates = [
      for (final c in Corner.values)
        if (c != widget.blocked) c,
    ];
    candidates.sort(
      (a, b) => (_cornerOrigin(a, size) + size.center(Offset.zero) - center)
          .distance
          .compareTo(
            (_cornerOrigin(b, size) + size.center(Offset.zero) - center)
                .distance,
          ),
    );
    return candidates.first;
  }

  @override
  Widget build(BuildContext context) {
    final measured = _Measure(
      onSize: (s) {
        if (s != _size) setState(() => _size = s);
      },
      child: GestureDetector(
        onPanStart: (_) => setState(
          () => _dragAt = _cornerOrigin(widget.corner, _size ?? Size.zero),
        ),
        onPanUpdate: (d) => setState(() => _dragAt = _dragAt! + d.delta),
        onPanEnd: (_) {
          final size = _size ?? Size.zero;
          final target = _nearestFree(_dragAt!, size);
          setState(() => _dragAt = null);
          if (target != widget.corner) widget.onCornerChanged(target);
        },
        child: widget.child,
      ),
    );

    final size = _size;
    if (size == null) {
      // First frame: place by edges until the control's size is known.
      final m = widget.margin;
      return Positioned(
        left: widget.corner.isLeft ? m.left : null,
        right: widget.corner.isLeft ? null : m.right,
        top: widget.corner.isTop ? m.top : null,
        bottom: widget.corner.isTop ? null : m.bottom,
        child: measured,
      );
    }
    final at = _dragAt ?? _cornerOrigin(widget.corner, size);
    return AnimatedPositioned(
      // Follow the finger instantly; glide when snapping to a corner.
      duration: _dragAt != null || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      // max(0, …): if the control is bigger than the area (a tiny screen
      // with large text), clamp would get an upper bound below its lower one.
      left: at.dx.clamp(0, math.max(0, widget.area.width - size.width)),
      top: at.dy.clamp(0, math.max(0, widget.area.height - size.height)),
      child: measured,
    );
  }
}

/// Reports its child's laid-out size after each layout.
class _Measure extends SingleChildRenderObjectWidget {
  const _Measure({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasure(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasure renderObject) =>
      renderObject.onSize = onSize;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      // Not during layout: report once this frame is done.
      final reported = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
    }
  }
}
