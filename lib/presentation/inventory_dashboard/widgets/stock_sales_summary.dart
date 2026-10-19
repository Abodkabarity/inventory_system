import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/stock_management.dart';
import 'stock_selectable_cell_text.dart';

/// Compact, fully labelled sales channels shared by both stock views.
class StockSalesSummary extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color totalColor;

  const StockSalesSummary({
    super.key,
    required this.data,
    required this.totalColor,
  });

  static final _quantity = NumberFormat('#,##0.##');
  static const _channels = [
    ('cash', 'Cash', Color(0xFF00796F)),
    ('insurance', 'Insurance', Color(0xFF355AC1)),
    ('online', 'Online', Color(0xFF7852AD)),
  ];

  String _qty(dynamic value) => _quantity.format(stockNumber(value));

  Widget _channel(String key, String label, Color color, bool stacked) {
    final quantity = _qty(data[key]);
    final labelText = StockSelectableCellText(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      style: TextStyle(
        color: color,
        fontSize: 12,
        height: 1.15,
        fontWeight: FontWeight.w600,
      ),
    );
    final valueText = StockSelectableCellText(
      quantity,
      textAlign: TextAlign.center,
      maxLines: 1,
      style: TextStyle(
        color: color,
        fontSize: 14,
        height: 1.15,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Tooltip(
      message: '$label: $quantity',
      child: stacked
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: labelText),
                const SizedBox(width: 8),
                Flexible(child: valueText),
              ],
            )
          : Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: .035),
                    color.withValues(alpha: .095),
                  ],
                ),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: color.withValues(alpha: .16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [labelText, const SizedBox(height: 2), valueText],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Align(
        alignment: Alignment.center,
        child: StockSelectableCellText(
          'Sales unavailable',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 240;
        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: StockSelectableCellText(
                    _qty(data['total']),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      color: totalColor,
                      fontSize: 19,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                const StockSelectableCellText(
                  'Total',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (stacked)
              for (final channel in _channels)
                _channel(channel.$1, channel.$2, channel.$3, true)
            else
              Row(
                children: [
                  for (var i = 0; i < _channels.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(
                      child: _channel(
                        _channels[i].$1,
                        _channels[i].$2,
                        _channels[i].$3,
                        false,
                      ),
                    ),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}
