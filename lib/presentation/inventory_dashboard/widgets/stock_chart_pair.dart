import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Measures both panels at their own widths, then stretches their backgrounds
/// to the taller panel without requesting intrinsic sizes from chart builders.
class StockChartPair extends MultiChildRenderObjectWidget {
  final double leftFraction;
  const StockChartPair({
    super.key,
    required super.children,
    this.leftFraction = .7,
  }) : assert(children.length == 2),
       assert(leftFraction > 0 && leftFraction < 1);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _StockChartPairRender(leftFraction);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _StockChartPairRender).leftFraction = leftFraction;
  }
}

class _ChartParentData extends ContainerBoxParentData<RenderBox> {}

class _StockChartPairRender extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ChartParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ChartParentData> {
  double _leftFraction;
  _StockChartPairRender(this._leftFraction);

  set leftFraction(double value) {
    if (_leftFraction == value) return;
    _leftFraction = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ChartParentData) {
      child.parentData = _ChartParentData();
    }
  }

  @override
  void performLayout() {
    final available = math.max(0.0, constraints.maxWidth - 16);
    final widths = [available * _leftFraction, available * (1 - _leftFraction)];
    var height = 0.0;
    var child = firstChild;
    var index = 0;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: widths[index]),
        parentUsesSize: true,
      );
      height = math.max(height, child.size.height);
      child = childAfter(child);
      index++;
    }
    height = constraints.constrainHeight(height);
    child = firstChild;
    index = 0;
    var x = 0.0;
    while (child != null) {
      child.layout(
        // A loose maximum height keeps natural content changes propagating
        // back to this pair, including asynchronously loaded profile labels.
        BoxConstraints(
          minWidth: widths[index],
          maxWidth: widths[index],
          minHeight: height,
        ),
        parentUsesSize: true,
      );
      (child.parentData! as _ChartParentData).offset = Offset(x, 0);
      x += widths[index] + 16;
      child = childAfter(child);
      index++;
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
