import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../domain/entities/stock_catalog.dart';
import '../../../domain/entities/stock_management.dart';
import '../../../core/theme/app_colors.dart';

/// Stock workspace controls always use the app brand, including routed menus.
ThemeData catalogControlTheme(BuildContext context) {
  final theme = Theme.of(context);
  return theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      primary: AppColors.primaryColor,
      onPrimary: AppColors.secondaryColor,
      secondary: AppColors.primaryColor,
      onSecondary: AppColors.secondaryColor,
      tertiary: AppColors.primaryColor,
      onTertiary: AppColors.secondaryColor,
      primaryContainer: AppColors.primaryColor.withValues(alpha: .14),
      onPrimaryContainer: AppColors.secondaryColor,
      secondaryContainer: AppColors.primaryColor.withValues(alpha: .14),
      onSecondaryContainer: AppColors.secondaryColor,
      surfaceTint: Colors.transparent,
    ),
    focusColor: AppColors.primaryColor.withValues(alpha: .12),
    hoverColor: AppColors.primaryColor.withValues(alpha: .06),
    splashColor: AppColors.primaryColor.withValues(alpha: .12),
    highlightColor: AppColors.primaryColor.withValues(alpha: .08),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.primaryColor,
      selectionColor: AppColors.primaryColor.withValues(alpha: .25),
      selectionHandleColor: AppColors.primaryColor,
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: AppColors.primaryColor.withValues(alpha: .045),
      prefixIconColor: AppColors.primaryColor,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryColor, width: 1.5),
      ),
    ),
    popupMenuTheme: theme.popupMenuTheme.copyWith(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

const catalogInk = Color(0xFF192D4B);
const catalogMuted = Color(0xFF677B95);
const catalogTeal = Color(0xFF069D95);
const catalogBlue = Color(0xFF5277E8);
const catalogPurple = Color(0xFF8259DB);
const catalogOrange = Color(0xFFF19A4B);
const catalogRose = Color(0xFFD74674);
final _quantity = NumberFormat('#,##0.##');
String catalogQty(dynamic n) => _quantity.format(stockNumber(n));
String catalogDate(dynamic value) {
  final d = DateTime.tryParse('$value');
  return d == null ? '—' : DateFormat('dd MMM yyyy').format(d);
}

String catalogCover(StockCatalogItem item) => item.days == null
    ? 'No recent sales'
    : item.days! <= 0
    ? 'No stock'
    : item.days! >= 60
    ? '${(item.days! / 30).toStringAsFixed(1)} months'
    : '${item.days!.toStringAsFixed(1)} days';
Color catalogSignalColor(StockCatalogItem item) =>
    item.distributionStatus.needsDistribution
    ? catalogOrange
    : item.surge || item.newDemand
    ? catalogPurple
    : item.salesExceedStock || item.status == 'no_stock'
    ? catalogRose
    : item.status == 'low_cover'
    ? catalogOrange
    : catalogTeal;

class CatalogPill extends StatelessWidget {
  final String text;
  final Color color;
  const CatalogPill(this.text, {super.key, this.color = catalogTeal});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
    ),
  );
}

class CatalogPanel extends StatelessWidget {
  final String title, subtitle;
  final Widget child;
  final Widget? trailing;
  const CatalogPanel({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.child,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE6EBF4)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x07192D4B),
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: catalogInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              subtitle,
              style: const TextStyle(color: catalogMuted, fontSize: 12),
            ),
          ),
        const SizedBox(height: 20),
        child,
      ],
    ),
  );
}

class CatalogMetric extends StatelessWidget {
  final String title, value, caption;
  final Color color;
  final IconData icon;
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final bool selected;
  final bool dense;
  const CatalogMetric({
    super.key,
    required this.title,
    required this.value,
    required this.caption,
    required this.color,
    required this.icon,
    this.iconWidget,
    this.onTap,
    this.selected = false,
    this.dense = false,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        height: dense
            ? null
            : 52 + 86 * MediaQuery.textScalerOf(context).scale(1),
        padding: EdgeInsets.all(dense ? 12 : 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                color.withValues(alpha: selected ? .19 : .10),
                Colors.white,
              ),
              Colors.white,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: color.withValues(alpha: selected ? .7 : .16),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: .06),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: dense
            ? Tooltip(
                message: caption,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: iconWidget ?? Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        style: const TextStyle(
                          color: catalogMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      value,
                      style: TextStyle(
                        color: color,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 20 * MediaQuery.textScalerOf(context).scale(1),
                    child: Row(
                      children: [
                        iconWidget ?? Icon(icon, color: color, size: 19),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: catalogMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 36 * MediaQuery.textScalerOf(context).scale(1),
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: color,
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 30 * MediaQuery.textScalerOf(context).scale(1),
                    child: Tooltip(
                      message: caption,
                      child: Text(
                        caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: catalogMuted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}

/// Trend matches the displayed percentage; an undefined comparison is distinct
/// from zero growth. A new demand signal is an increase without a percentage.
class CatalogGrowthMetric extends StatelessWidget {
  final StockCatalogItem item;
  const CatalogGrowthMetric({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final growth = item.growth;
    final displayed = growth == null
        ? null
        : double.parse(growth.toStringAsFixed(1));
    final increasing = item.newDemand || (displayed != null && displayed > 0);
    final decreasing = !item.newDemand && displayed != null && displayed < 0;
    final stable = !item.newDemand && displayed != null && displayed == 0;
    final color = increasing
        ? const Color(0xFF15975A)
        : decreasing
        ? const Color(0xFFDC3545)
        : catalogOrange;
    final label = increasing
        ? 'Sales increasing'
        : decreasing
        ? 'Sales decreasing'
        : stable
        ? 'Sales unchanged'
        : 'Growth unavailable';
    final icon = increasing
        ? Icons.trending_up_rounded
        : decreasing
        ? Icons.trending_down_rounded
        : Icons.more_horiz_rounded;
    final direction = increasing
        ? -1.0
        : decreasing
        ? 1.0
        : 0.0;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 360);
    return CatalogMetric(
      title: 'GROWTH',
      value: item.newDemand
          ? 'New demand'
          : displayed == null
          ? '—'
          : '${displayed == 0 ? '0.0' : displayed.toStringAsFixed(1)}%',
      caption: '3-day average vs previous 42-day average',
      color: color,
      icon: icon,
      iconWidget: Tooltip(
        message: label,
        child: Semantics(
          label: label,
          image: true,
          child: SizedBox(
            width: 19,
            height: 19,
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(label),
                tween: Tween(begin: 0, end: 1),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (_, progress, child) => Transform.translate(
                  offset: Offset(
                    stable ? 4 * (1 - progress) : 0,
                    direction * 5 * (1 - progress),
                  ),
                  child: child,
                ),
                child: stable
                    ? CustomPaint(
                        size: const Size(19, 19),
                        painter: _CatalogFlatTrendPainter(color),
                      )
                    : Icon(icon, color: color, size: 19),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogFlatTrendPainter extends CustomPainter {
  final Color color;
  const _CatalogFlatTrendPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .05, size.height * .5)
      ..cubicTo(
        size.width * .2,
        size.height * .5,
        size.width * .2,
        size.height * .26,
        size.width * .35,
        size.height * .26,
      )
      ..cubicTo(
        size.width * .5,
        size.height * .26,
        size.width * .5,
        size.height * .74,
        size.width * .65,
        size.height * .74,
      )
      ..cubicTo(
        size.width * .8,
        size.height * .74,
        size.width * .8,
        size.height * .5,
        size.width * .95,
        size.height * .5,
      )
      ..moveTo(size.width * .78, size.height * .33)
      ..lineTo(size.width * .95, size.height * .5)
      ..lineTo(size.width * .78, size.height * .67);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CatalogFlatTrendPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// One short animation per mount, painted inside a RepaintBoundary.
class CatalogMotion extends StatelessWidget {
  final Widget Function(double progress) builder;
  const CatalogMotion({super.key, required this.builder});
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (_, p, _) => builder(p),
    ),
  );
}

class CatalogMonthlyChart extends StatefulWidget {
  final StockCatalogItem item;
  const CatalogMonthlyChart({super.key, required this.item});
  @override
  State<CatalogMonthlyChart> createState() => _CatalogMonthlyChartState();
}

class _CatalogMonthlyChartState extends State<CatalogMonthlyChart> {
  int? _hover;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final series = catalogMonthlySeries(widget.item);
    final averages = catalogMovingAverage(series);
    if (series.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('No monthly sales uploaded')),
      );
    }
    final active = _hover == null ? null : series[_hover!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            const CatalogPill('Monthly net Qty', color: catalogOrange),
            const CatalogPill('3-month moving average', color: catalogBlue),
            if (active != null)
              Text(
                '${active['month']}  ·  ${catalogQty(active['total'])} Qty  ·  MA ${averages[_hover!] == null ? '—' : catalogQty(averages[_hover!])}',
                style: const TextStyle(
                  color: catalogInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, size) {
            final width = math.max(size.maxWidth, series.length * 48.0 + 64);
            return Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: MouseRegion(
                  onExit: (_) => setState(() => _hover = null),
                  onHover: (event) {
                    final i =
                        ((event.localPosition.dx - 60) /
                                (width - 76) *
                                series.length)
                            .floor();
                    final next = i >= 0 && i < series.length ? i : null;
                    if (_hover != next) setState(() => _hover = next);
                  },
                  child: GestureDetector(
                    onTapDown: (event) {
                      final i =
                          ((event.localPosition.dx - 60) /
                                  (width - 76) *
                                  series.length)
                              .floor();
                      setState(
                        () => _hover = i >= 0 && i < series.length ? i : null,
                      );
                    },
                    child: Semantics(
                      label:
                          'Monthly net sales and trailing three month average. Scroll horizontally to see every month.',
                      child: CatalogMotion(
                        builder: (p) => CustomPaint(
                          size: Size(width, 285),
                          painter: _MonthlyPainter(series, averages, p, _hover),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Current month may be partial • Net quantities include returns • Scroll for all months',
          style: const TextStyle(color: catalogMuted, fontSize: 11),
        ),
      ],
    );
  }
}

void _paintText(
  Canvas canvas,
  String text,
  Offset offset, {
  Color color = catalogMuted,
  double size = 10,
  bool bold = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontFamily: 'Roboto',
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, offset);
}

class _MonthlyPainter extends CustomPainter {
  final List<Map<String, dynamic>> series;
  final List<double?> averages;
  final double progress;
  final int? hover;
  _MonthlyPainter(this.series, this.averages, this.progress, this.hover);
  @override
  void paint(Canvas canvas, Size size) {
    final values = series.map((r) => stockNumber(r['total'])).toList();
    final maxValue = math.max(1.0, values.reduce(math.max)) * 1.18;
    final minValue = math.min(0.0, values.reduce(math.min)) * 1.18;
    const left = 60.0, top = 15.0;
    final bottom = size.height - 55,
        width = size.width - left - 16,
        height = bottom - top;
    double y(double value) =>
        bottom - (value - minValue) / (maxValue - minValue) * height;
    final zero = y(0), step = width / series.length;
    for (var i = 0; i <= 4; i++) {
      final value = minValue + (maxValue - minValue) * i / 4;
      canvas.drawLine(
        Offset(left, y(value)),
        Offset(size.width - 16, y(value)),
        Paint()..color = const Color(0xFFEAF0F7),
      );
      _paintText(
        canvas,
        NumberFormat.compact().format(value),
        Offset(0, y(value) - 6),
      );
    }
    final path = Path();
    var started = false;
    for (var i = 0; i < values.length; i++) {
      final x = left + step * i + step / 2;
      if (hover == i) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - step / 2, top, step, height),
            const Radius.circular(6),
          ),
          Paint()..color = catalogBlue.withValues(alpha: .06),
        );
      }
      final target = y(values[i] * progress);
      final rect = Rect.fromLTRB(
        x - step * .30,
        math.min(zero, target),
        x + step * .30,
        math.max(zero, target),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: values[i] >= 0
                ? [const Color(0xFFFFB575), catalogOrange]
                : [catalogRose.withValues(alpha: .6), catalogRose],
          ).createShader(rect),
      );
      _paintText(
        canvas,
        NumberFormat.compact().format(values[i]),
        Offset(x - step * .28, target + (values[i] >= 0 ? -17 : 5)),
        color: catalogInk,
        bold: true,
        size: 9,
      );
      final parts = '${series[i]['month']}'.split('/');
      _paintText(
        canvas,
        DateFormat(
          'MMM',
        ).format(DateTime(2025, int.tryParse(parts.first) ?? 1)),
        Offset(x - 12, bottom + 12),
      );
      _paintText(canvas, parts.last, Offset(x - 13, bottom + 27), size: 9);
      if (averages[i] != null) {
        final point = Offset(x, y(averages[i]! * progress));
        if (!started) {
          path.moveTo(point.dx, point.dy);
          started = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawCircle(point, 3, Paint()..color = catalogBlue);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = catalogBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawLine(
      Offset(left, zero),
      Offset(size.width - 16, zero),
      Paint()..color = const Color(0xFFCCD8E8),
    );
  }

  @override
  bool shouldRepaint(covariant _MonthlyPainter old) =>
      old.progress != progress || old.hover != hover || old.series != series;
}

class CatalogStockChart extends StatelessWidget {
  final StockCatalogItem item;
  const CatalogStockChart({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final stock = math.max(0.0, item.number('total_stock'));
    final sold = math.max(0.0, item.number('recent_sales'));
    final percent = stock > 0 ? sold / stock * 100 : null;
    return Column(
      children: [
        Semantics(
          label:
              '45-day sales divided by current stock: ${percent == null ? 'unavailable' : '${percent.toStringAsFixed(1)} percent'}',
          child: CatalogMotion(
            builder: (p) => CustomPaint(
              size: const Size(280, 145),
              painter: _GaugePainter(
                percent == null ? 0 : (percent / 100).clamp(0, 1),
                p,
                item.salesExceedStock ? catalogRose : catalogTeal,
              ),
            ),
          ),
        ),
        Text(
          percent == null
              ? 'No stock available'
              : '${percent.toStringAsFixed(1)}% sales / stock',
          style: TextStyle(
            color: item.salesExceedStock ? catalogRose : catalogTeal,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '45-day net Qty ÷ current stock • Gauge capped at 100%',
          style: TextStyle(color: catalogMuted, fontSize: 11),
        ),
        const SizedBox(height: 24),
        for (final entry in [
          ('Available', item.number('total_stock'), catalogBlue),
          ('Sold (45D)', item.number('recent_sales'), catalogOrange),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    entry.$1,
                    style: const TextStyle(color: catalogMuted, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: CatalogMotion(
                    builder: (p) => ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        minHeight: 22,
                        value:
                            math.max(0, entry.$2) /
                            math.max(1, math.max(stock, sold)) *
                            p,
                        color: entry.$3,
                        backgroundColor: const Color(0xFFF0F4FA),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 75,
                  child: Text(
                    catalogQty(entry.$2),
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: catalogInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value, progress;
  final Color color;
  _GaugePainter(this.value, this.progress, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 16),
        radius = math.min(size.width / 2 - 20, size.height - 24);
    final arc = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      arc,
      math.pi,
      math.pi,
      false,
      paint..color = const Color(0xFFEAF0F7),
    );
    canvas.drawArc(
      arc,
      math.pi,
      math.pi * value * progress,
      false,
      paint
        ..shader = SweepGradient(
          startAngle: math.pi,
          endAngle: 2 * math.pi,
          colors: [catalogTeal, catalogBlue, color],
        ).createShader(arc),
    );
    for (var i = 0; i <= 4; i++) {
      final angle = math.pi + math.pi * i / 4;
      final p =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius - 29);
      _paintText(canvas, '${i * 25}', p - const Offset(8, 5), size: 10);
    }
    final angle = math.pi + math.pi * value * progress;
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * (radius - 40),
      Paint()
        ..color = catalogInk
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 6, Paint()..color = catalogInk);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.progress != progress || old.value != value || old.color != color;
}
