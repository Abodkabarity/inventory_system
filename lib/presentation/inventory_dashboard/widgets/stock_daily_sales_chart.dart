import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../domain/entities/stock_daily_sales.dart';
import 'stock_catalog_visuals.dart';

const _colors = <StockSalesChannel, Color>{
  StockSalesChannel.cash: catalogOrange,
  StockSalesChannel.online: catalogBlue,
  StockSalesChannel.insuranceBasic: catalogTeal,
  StockSalesChannel.insuranceThiqa: catalogPurple,
  StockSalesChannel.otherInsurance: catalogRose,
};

class StockDailySalesChart extends StatefulWidget {
  final StockDailySalesMix mix;
  const StockDailySalesChart({super.key, required this.mix});
  @override
  State<StockDailySalesChart> createState() => _StockDailySalesChartState();
}

class _StockDailySalesChartState extends State<StockDailySalesChart> {
  final _scroll = ScrollController();
  int? _selected;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StockDailySalesChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mix != widget.mix) _selected = null;
  }

  void _select(int index) {
    final next = index.clamp(0, widget.mix.days.length - 1);
    if (next != _selected) setState(() => _selected = next);
  }

  void _step(int delta, double step) {
    final next = ((_selected ?? 0) + delta).clamp(
      0,
      widget.mix.days.length - 1,
    );
    _select(next);
    if (!_scroll.hasClients) return;
    final x = 56 + next * step;
    final viewport = _scroll.position.viewportDimension;
    if (x < _scroll.offset || x + step > _scroll.offset + viewport) {
      _scroll.animateTo(
        (x - viewport / 2).clamp(0, _scroll.position.maxScrollExtent),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mix = widget.mix;
    if (!mix.available) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Daily sales breakdown is not available for this snapshot.',
          style: TextStyle(color: catalogMuted),
        ),
      );
    }
    final selected = _selected ?? 0;
    final day = mix.days[selected];
    return LayoutBuilder(
      builder: (context, size) {
        final width = math.max(size.maxWidth, mix.days.length * 40.0 + 72);
        final step = (width - 72) / mix.days.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final channel in StockSalesChannel.values)
                  Tooltip(
                    message: '${channel.label} • period net Qty',
                    child: CatalogPill(
                      '${channel.label}  ${catalogQty(mix.totalFor(channel))}',
                      color: _colors[channel]!,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              key: const ValueKey('daily-sales-selection'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            '${DateFormat('EEE, dd MMM yyyy').format(day.date)}  •  ${catalogQty(day.total)} Qty',
                            key: const ValueKey('daily-sales-selected-date'),
                            style: const TextStyle(
                              color: catalogInk,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Previous day',
                        visualDensity: VisualDensity.compact,
                        onPressed: selected == 0 ? null : () => _step(-1, step),
                        icon: const Icon(Icons.chevron_left, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Next day',
                        visualDensity: VisualDensity.compact,
                        onPressed: selected == mix.days.length - 1
                            ? null
                            : () => _step(1, step),
                        icon: const Icon(Icons.chevron_right, size: 20),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      for (final channel in StockSalesChannel.values)
                        Text(
                          '${channel.label}: ${catalogQty(day.qty(channel))}',
                          style: TextStyle(
                            color: _colors[channel],
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Focus(
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                    event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _step(
                    event.logicalKey == LogicalKeyboardKey.arrowLeft ? -1 : 1,
                    step,
                  );
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: MouseRegion(
                    onHover: (event) {
                      final i = ((event.localPosition.dx - 56) / step).floor();
                      if (i >= 0 && i < mix.days.length) _select(i);
                    },
                    child: GestureDetector(
                      onTapDown: (event) {
                        final i = ((event.localPosition.dx - 56) / step)
                            .floor();
                        if (i >= 0 && i < mix.days.length) _select(i);
                      },
                      child: Semantics(
                        label:
                            'Daily sales. ${mix.days.length} days. Hover or tap a day, or use the previous and next day buttons. Negative quantities are returns.',
                        child: CatalogMotion(
                          builder: (progress) => CustomPaint(
                            key: const ValueKey('daily-sales-plot'),
                            size: Size(width, 290),
                            painter: _DailySalesPainter(
                              mix,
                              selected,
                              progress,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${mix.days.length} calendar days • Net Qty includes returns • Days without sales show 0 • Scroll for all dates',
              style: const TextStyle(color: catalogMuted, fontSize: 11),
            ),
          ],
        );
      },
    );
  }
}

class _DailySalesPainter extends CustomPainter {
  final StockDailySalesMix mix;
  final int selected;
  final double progress;
  _DailySalesPainter(this.mix, this.selected, this.progress);
  void _text(
    Canvas canvas,
    String value,
    Offset position, {
    Color color = catalogMuted,
    double fontSize = 10,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: 'Roboto',
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
  }

  @override
  void paint(Canvas canvas, Size size) {
    double maximum = 1, minimum = 0;
    for (final day in mix.days) {
      double positive = 0, negative = 0;
      for (final value in day.quantities.values) {
        if (value > 0) {
          positive += value;
        } else {
          negative += value;
        }
      }
      maximum = math.max(maximum, positive);
      minimum = math.min(minimum, negative);
    }
    maximum *= 1.15;
    minimum *= 1.15;
    const left = 56.0, top = 18.0;
    final bottom = size.height - 55, height = bottom - top;
    final step = (size.width - 72) / mix.days.length;
    double y(double value) =>
        bottom - (value - minimum) / (maximum - minimum) * height;
    for (var i = 0; i <= 4; i++) {
      final value = minimum + (maximum - minimum) * i / 4;
      canvas.drawLine(
        Offset(left, y(value)),
        Offset(size.width - 16, y(value)),
        Paint()..color = const Color(0xFFEAF0F7),
      );
      _text(
        canvas,
        NumberFormat.compact().format(value),
        Offset(0, y(value) - 6),
      );
    }
    for (var i = 0; i < mix.days.length; i++) {
      final day = mix.days[i], x = left + step * (i + .5);
      if (i == selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - step / 2, top, step, height),
            const Radius.circular(6),
          ),
          Paint()..color = catalogBlue.withValues(alpha: .07),
        );
      }
      double positive = 0, negative = 0;
      for (final channel in StockSalesChannel.values) {
        final qty = day.qty(channel) * progress;
        final start = qty >= 0 ? positive : negative;
        final end = start + qty;
        if (qty >= 0) {
          positive = end;
        } else {
          negative = end;
        }
        if (qty == 0) continue;
        final rect = Rect.fromLTRB(
          x - step * .29,
          math.min(y(start), y(end)),
          x + step * .29,
          math.max(y(start), y(end)),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()..color = _colors[channel]!,
        );
      }
      if (day.quantities.values.every((qty) => qty == 0)) {
        canvas.drawCircle(
          Offset(x, y(0)),
          2,
          Paint()..color = const Color(0xFFB7C6D9),
        );
      }
      final totalLabel = TextPainter(
        text: TextSpan(
          text: catalogQty(day.total),
          style: TextStyle(
            color: day.total < 0 ? catalogRose : catalogInk,
            fontFamily: 'Roboto',
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelScale = math.min(1.0, (step - 4) / totalLabel.width);
      canvas.save();
      canvas.translate(
        x - totalLabel.width * labelScale / 2,
        y(positive) - totalLabel.height * labelScale - 5,
      );
      canvas.scale(labelScale);
      totalLabel.paint(canvas, Offset.zero);
      canvas.restore();
      totalLabel.dispose();
      _text(
        canvas,
        '${day.date.day}'.padLeft(2, '0'),
        Offset(x - 6, bottom + 12),
        color: i == selected ? catalogInk : catalogMuted,
        bold: i == selected,
      );
      _text(
        canvas,
        DateFormat('MMM').format(day.date),
        Offset(x - 10, bottom + 27),
        fontSize: 9,
      );
    }
    canvas.drawLine(
      Offset(left, y(0)),
      Offset(size.width - 16, y(0)),
      Paint()..color = const Color(0xFFBCCBDD),
    );
  }

  @override
  bool shouldRepaint(covariant _DailySalesPainter old) =>
      old.mix != mix || old.selected != selected || old.progress != progress;
}
