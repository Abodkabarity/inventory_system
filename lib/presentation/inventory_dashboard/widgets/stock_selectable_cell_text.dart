import 'package:flutter/material.dart';

/// A consistent centered presentation for both single- and multi-line references.
class StockReferenceCell extends StatelessWidget {
  final String reference;
  final TextStyle style;
  const StockReferenceCell(this.reference, {super.key, required this.style});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: reference,
    child: Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: double.infinity,
        child: StockSelectableCellText(
          reference.isEmpty ? '—' : reference,
          textAlign: TextAlign.center,
          maxLines: 3,
          style: style,
        ),
      ),
    ),
  );
}

/// Keeps the row's normal click action while its text remains selectable.
class StockCellTapScope extends InheritedWidget {
  final VoidCallback onTap;

  const StockCellTapScope({
    super.key,
    required this.onTap,
    required super.child,
  });

  static VoidCallback? maybeOnTap(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StockCellTapScope>()?.onTap;

  @override
  bool updateShouldNotify(StockCellTapScope oldWidget) =>
      onTap != oldWidget.onTap;
}

class StockSelectableCellText extends StatelessWidget {
  final String text;
  final TextSpan? span;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  const StockSelectableCellText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  }) : span = null;

  const StockSelectableCellText.rich(
    this.span, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  }) : text = '';

  @override
  Widget build(BuildContext context) => span == null
      ? SelectableText(
          text,
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          onTap: StockCellTapScope.maybeOnTap(context),
        )
      : SelectableText.rich(
          span!,
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          onTap: StockCellTapScope.maybeOnTap(context),
        );
}
