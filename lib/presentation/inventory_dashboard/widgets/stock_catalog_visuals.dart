import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../domain/entities/stock_catalog.dart';
import '../../../domain/entities/stock_management.dart';
import '../../../domain/entities/stock_supply_insight.dart';
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
Color catalogSupplyStatusColor(StockSupplyInsight insight) =>
    switch (insight.currentState) {
      'empty' => insight.currentBranchesQty > 0 ? catalogOrange : catalogRose,
      'limited' => catalogOrange,
      'available' => catalogTeal,
      'cover_unknown' => catalogBlue,
      'invalid' => catalogRose,
      _ => catalogMuted,
    };
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
  final int maxLines;
  const CatalogPill(
    this.text, {
    super.key,
    this.color = catalogTeal,
    this.maxLines = 2,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      maxLines: maxLines,
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
            : caption.isEmpty
            ? 46 + 56 * MediaQuery.textScalerOf(context).scale(1)
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
                  if (caption.isNotEmpty) ...[
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

  Future<void> _showMonthDetails(
    String month,
    String summary,
    String description,
    List<Map<String, dynamic>> receipts,
    bool estimated,
  ) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Month details · $month',
                      style: const TextStyle(
                        color: catalogInk,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close month details',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        summary,
                        style: const TextStyle(
                          color: catalogInk,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          description,
                          style: const TextStyle(
                            color: catalogRose,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        'STORE receipts${estimated ? ' · Estimated' : ''}',
                        style: const TextStyle(
                          color: catalogInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (receipts.isEmpty)
                        const Text(
                          'No MRN receipts recorded for this month.',
                          style: TextStyle(color: catalogMuted, fontSize: 13),
                        )
                      else
                        Table(
                          columnWidths: const {
                            0: FlexColumnWidth(1.1),
                            1: FlexColumnWidth(.6),
                            2: FlexColumnWidth(1.8),
                          },
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          border: const TableBorder(
                            horizontalInside: BorderSide(
                              color: Color(0xFFE8EEF5),
                            ),
                          ),
                          children: [
                            const TableRow(
                              decoration: BoxDecoration(
                                color: Color(0xFFF5F8FC),
                              ),
                              children: [
                                _MonthReceiptText('Date', strong: true),
                                _MonthReceiptText('Qty', strong: true),
                                _MonthReceiptText('At arrival', strong: true),
                              ],
                            ),
                            for (final receipt in receipts)
                              TableRow(
                                children: [
                                  _MonthReceiptText(
                                    catalogDate(receipt['date']),
                                  ),
                                  _MonthReceiptText(
                                    catalogQty(receipt['qty']),
                                    strong: true,
                                  ),
                                  _MonthReceiptText(
                                    StockSupplyInsight.arrivalLabel(receipt),
                                    color: receipt['kind'] == 'restored'
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFF568C0B),
                                  ),
                                ],
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final series = catalogMonthlySeries(widget.item);
    final averages = catalogMovingAverage(series);
    final supply = StockSupplyInsight.of(widget.item);
    final hasGaps = series.any((row) => supply.chartMarksMonth(row['month']));
    final arrivals = supply.chartArrivals;
    final supplySemantics = !hasGaps
        ? ''
        : supply.hasChartPeriods
        ? ' ${supply.chartIsContinuousStockout ? 'Continuous STORE out-of-stock periods' : 'Estimated supply interruption periods'}: ${supply.chartPeriods.map((p) => "${p['from']} through ${p['through']}: ${supply.supplyDuration(p)}").join('; ')}.${supply.chartNeedsReview ? ' Stock history needs checking.' : ''}'
        : ' STORE out-of-stock periods: ${series.where((r) => supply.marksMonth(r['month'])).map((r) => "${r['month']}: ${supply.monthDescription(r['month'])}").join('; ')}.';
    if (series.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('No monthly sales uploaded')),
      );
    }
    final active = _hover == null ? null : series[_hover!];
    var source = '';
    if (active != null) {
      if (active['source'] == 'sales_last_45_days') {
        source = active['through'] == null
            ? 'Daily sales • No current-month data uploaded'
            : 'Daily sales through ${catalogDate(active['through'])}';
      } else if (active['source'] == 'sales_history') {
        source = 'Monthly history';
      }
    }
    final summary = active == null
        ? 'Hover or tap a month to see sales and receipt details.'
        : '${active['month']}  ·  ${catalogQty(active['total'])} Qty  ·  3-month average: ${averages[_hover!] == null ? '—' : '${catalogQty(averages[_hover!])} Qty'}${source.isEmpty ? '' : '  ·  $source'}';
    final description =
        active != null && supply.chartMarksMonth(active['month'])
        ? supply.chartMonthDescription(active['month'])
        : '';
    final monthReceipts = active == null
        ? <Map<String, dynamic>>[]
        : supply.chartArrivalsInMonth(active['month']);
    monthReceipts.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    final receivedQty = monthReceipts.fold<double>(
      0,
      (total, row) => total + stockNumber(row['qty']),
    );
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            const CatalogPill('Monthly net Qty', color: catalogOrange),
            const Tooltip(
              message:
                  'Average monthly net Qty for the selected month and the two preceding months.',
              child: CatalogPill('3-month average', color: catalogBlue),
            ),
            if (supply.showCurrentStatus)
              Tooltip(
                message: supply.currentExplanation,
                child: CatalogPill(
                  'Current: ${supply.currentLabel}',
                  key: const ValueKey('monthly-current-store-status'),
                  color: catalogSupplyStatusColor(supply),
                ),
              ),
            if (hasGaps)
              Tooltip(
                message: supply.chartIsContinuousStockout
                    ? 'One continuous period without STORE stock, from the stock movement analysis. A sales demand model is not required. Branch stock is separate. ${supply.basisDescription}'
                    : supply.hasChartPeriods
                    ? 'Continuous periods of insufficient STORE supply compared with learned historical demand. Small arrivals do not end a period until recovery cover is restored. Branch availability is separate.'
                    : 'Months with at least 7 full days without STORE stock. Branch stock is separate. ${supply.basisDescription}',
                child: CatalogPill(
                  'Chart history · ${supply.chartNeedsReview || supply.hasSupplyAnalysis ? 'Estimated' : supply.basis}',
                  color: catalogRose,
                ),
              ),
            if (supply.chartNeedsReview)
              const CatalogPill(
                'Estimated · Stock history needs checking',
                color: catalogMuted,
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          key: const ValueKey('monthly-selection-info'),
          height: 100 * scale,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 36 * scale,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Tooltip(
                    message: summary,
                    child: Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active == null ? catalogMuted : catalogInk,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: active == null
                            ? FontWeight.w400
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 20 * scale,
                child: Tooltip(
                  message: description,
                  child: Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: catalogRose,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              if (active != null)
                SizedBox(
                  height: 36 * scale,
                  child: TextButton.icon(
                    key: const ValueKey('monthly-receipt-details'),
                    onPressed: () => _showMonthDetails(
                      '${active['month']}',
                      summary,
                      description,
                      monthReceipts,
                      supply.chartNeedsReview ||
                          supply.inferred ||
                          supply.hasSupplyAnalysis,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF15803D),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                    label: Text(
                      monthReceipts.isEmpty
                          ? 'View month details'
                          : '${monthReceipts.length} ${monthReceipts.length == 1 ? 'receipt' : 'receipts'} · ${catalogQty(receivedQty)} Qty · Details',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
                          'Monthly net sales and trailing three month average. Scroll horizontally to see every month.$supplySemantics ${arrivals.map((r) => '${r['date']}: ${StockSupplyInsight.arrivalLabel(r)}, ${catalogQty(r['qty'])} Qty received at STORE').join('; ')}',
                      child: CatalogMotion(
                        builder: (p) => CustomPaint(
                          size: Size(width, 285),
                          painter: _MonthlyPainter(
                            series,
                            averages,
                            p,
                            _hover,
                            supply,
                          ),
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

class _MonthReceiptText extends StatelessWidget {
  final String text;
  final bool strong;
  final Color color;
  const _MonthReceiptText(
    this.text, {
    this.strong = false,
    this.color = catalogInk,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
        height: 1.4,
        fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
  );
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
  final StockSupplyInsight supply;
  _MonthlyPainter(
    this.series,
    this.averages,
    this.progress,
    this.hover,
    this.supply,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final values = series.map((r) => stockNumber(r['total'])).toList();
    final maxValue = math.max(1.0, values.reduce(math.max)) * 1.18;
    final minValue = math.min(0.0, values.reduce(math.min)) * 1.18;
    const left = 60.0;
    final hasGaps = series.any((row) => supply.chartMarksMonth(row['month']));
    final hasArrivals = supply.chartArrivals.isNotEmpty;
    final top = hasArrivals
        ? 85.0
        : hasGaps
        ? supply.hasChartPeriods
              ? 50.0
              : 43.0
        : 15.0;
    final bottom = size.height - 55,
        width = size.width - left - 16,
        height = bottom - top;
    double y(double value) =>
        bottom - (value - minValue) / (maxValue - minValue) * height;
    final zero = y(0), step = width / series.length;
    if (supply.hasChartPeriods) {
      final indices = {
        for (var i = 0; i < series.length; i++) '${series[i]['month']}': i,
      };
      double? position(DateTime date) {
        final key = '${date.month.toString().padLeft(2, '0')}/${date.year}';
        final index = indices[key];
        if (index == null) return null;
        return left +
            step *
                (index +
                    (date.day - 1) /
                        DateTime(date.year, date.month + 1, 0).day);
      }

      for (final period in supply.chartPeriods) {
        final from = DateTime.tryParse('${period['from']}');
        final through = DateTime.tryParse('${period['through']}');
        if (from == null || through == null) continue;
        // Clip spans to the visible series, including a boundary month outside it.
        final firstParts = '${series.first['month']}'.split('/');
        final lastParts = '${series.last['month']}'.split('/');
        final visibleFrom = DateTime(
          int.parse(firstParts.last),
          int.parse(firstParts.first),
        );
        final visibleUntil = DateTime(
          int.parse(lastParts.last),
          int.parse(lastParts.first) + 1,
        );
        final until = DateTime(through.year, through.month, through.day + 1);
        if (!from.isBefore(visibleUntil) || !until.isAfter(visibleFrom)) {
          continue;
        }
        final x1 = from.isBefore(visibleFrom) ? left : position(from);
        final x2 = !until.isBefore(visibleUntil)
            ? size.width - 16
            : position(until);
        if (x1 == null || x2 == null || x2 <= x1) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x1, hasArrivals ? 77 : 31, x2, bottom),
            const Radius.circular(6),
          ),
          Paint()..color = catalogRose.withValues(alpha: .055),
        );
        final bracket = Path()
          ..moveTo(x1, 29)
          ..lineTo(x1, 23)
          ..lineTo(x2, 23)
          ..lineTo(x2, 29);
        canvas.drawPath(
          bracket,
          Paint()
            ..color = catalogRose
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
        final tp = TextPainter(
          text: TextSpan(
            text:
                '${supply.supplyDuration(period, compact: true)} · ${supply.chartIsContinuousStockout ? supply.basis : 'Estimated'}',
            style: const TextStyle(
              color: catalogRose,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'Roboto',
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: math.max(1, x2 - x1 - 8));
        tp.paint(canvas, Offset((x1 + x2 - tp.width) / 2, 5));
      }
    }
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
    // Receipt dates use a separate lane above the values. Several receipts in
    // one month keep their individual lines and share a compact month label.
    for (var i = 0; i < series.length; i++) {
      final arrivals = supply.chartArrivalsInMonth(series[i]['month']);
      if (arrivals.isEmpty) continue;
      final restored = arrivals.any((r) => r['kind'] == 'restored');
      final color = restored
          ? const Color(0xFF15803D)
          : const Color(0xFF65A30D);
      for (final arrival in arrivals) {
        final date = DateTime.parse('${arrival['date']}');
        final x =
            left +
            step *
                (i +
                    (date.day - 1) /
                        DateTime(date.year, date.month + 1, 0).day);
        final lineColor = arrival['kind'] == 'restored'
            ? const Color(0xFF15803D)
            : const Color(0xFF65A30D);
        final pen = Paint()
          ..color = lineColor.withValues(alpha: .55)
          ..strokeWidth = 1.5;
        if (supply.chartNeedsReview) {
          for (var dy = 77.0; dy < bottom; dy += 8) {
            canvas.drawLine(
              Offset(x, dy),
              Offset(x, math.min(dy + 4, bottom)),
              pen,
            );
          }
        } else {
          canvas.drawLine(Offset(x, 77), Offset(x, bottom), pen);
        }
        canvas.drawCircle(Offset(x, 77), 3, Paint()..color = lineColor);
      }
      final x = left + step * i;
      _paintText(
        canvas,
        restored ? 'BACK' : 'LIMITED',
        Offset(x + 4, 42),
        color: color,
        size: 9,
        bold: true,
      );
      _paintText(
        canvas,
        '${NumberFormat.compact().format(arrivals.fold<double>(0, (sum, r) => sum + stockNumber(r['qty'])))} Qty',
        Offset(x + 4, 56),
        color: color,
        size: 9,
      );
    }
    final path = Path();
    var started = false;
    for (var i = 0; i < values.length; i++) {
      final x = left + step * i + step / 2;
      if (!supply.hasChartPeriods &&
          supply.chartMarksMonth(series[i]['month'])) {
        // A separate top lane keeps the quantity labels and line unobscured.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - step / 2 + 2, 2, step - 4, bottom - 2),
            const Radius.circular(6),
          ),
          Paint()..color = catalogRose.withValues(alpha: .055),
        );
        _paintText(
          canvas,
          'OUT',
          Offset(x - 10, 5),
          color: catalogRose,
          bold: true,
          size: 9,
        );
        _paintText(
          canvas,
          '${stockNumber(supply.month(series[i]['month'])['empty_days']).toInt()}d${supply.inferred ? '*' : ''}',
          Offset(x - 10, 18),
          color: catalogRose,
          size: 9,
        );
      }
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
      old.progress != progress ||
      old.hover != hover ||
      old.series != series ||
      old.supply.data != supply.data;
}

class CatalogStockChart extends StatelessWidget {
  final StockManagementItem item;
  const CatalogStockChart({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final stock = math.max(0.0, item.number('total_stock'));
    final sold = math.max(0.0, item.number('recent_sales'));
    final percent = item.stockSalesPercent;
    final colour = stock < sold ? catalogRose : catalogTeal;
    return Column(
      children: [
        Semantics(
          label:
              'Current stock divided by 45-day sales: ${percent == null ? 'unavailable' : '${percent.toStringAsFixed(1)} percent'}',
          child: CatalogMotion(
            builder: (p) => CustomPaint(
              size: const Size(280, 145),
              painter: _GaugePainter(
                percent == null ? 0 : (percent / 100).clamp(0, 1),
                p,
                colour,
              ),
            ),
          ),
        ),
        Text(
          percent == null
              ? (item.stockAvailable ? 'No recent sales' : 'Stock unavailable')
              : '${percent.toStringAsFixed(1)}% stock / sales',
          style: TextStyle(
            color: colour,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Current stock ÷ 45-day net Qty • Gauge capped at 100%',
          style: TextStyle(color: catalogMuted, fontSize: 11),
        ),
        const SizedBox(height: 24),
        for (final entry in [
          (
            'Stock',
            item.stockAvailable ? item.number('total_stock') : 0.0,
            catalogBlue,
          ),
          ('Sales (45D)', item.number('recent_sales'), catalogOrange),
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
                    entry.$1 == 'Stock' && !item.stockAvailable
                        ? '—'
                        : catalogQty(entry.$2),
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
