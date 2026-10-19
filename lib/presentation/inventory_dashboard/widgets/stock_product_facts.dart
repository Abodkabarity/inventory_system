import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/stock_management.dart';

const _ink = Color(0xFF142C40),
    _muted = Color(0xFF64748B),
    _teal = Color(0xFF008A83),
    _blue = Color(0xFF4169D8),
    _amber = Color(0xFFB76C06);
String _qty(dynamic v) => NumberFormat('#,##0.##').format(stockNumber(v));
String _date(String v) {
  final d = DateTime.tryParse(v);
  return d == null ? '—' : DateFormat('dd MMM yyyy').format(d);
}

String _month(dynamic value) {
  final s = '$value'.split('/');
  if (s.length != 2) return 'No positive sales';
  final month = int.tryParse(s[0]), year = int.tryParse(s[1]);
  return month == null || year == null
      ? '—'
      : DateFormat('MMM yyyy').format(DateTime(year, month));
}

/// Product-level facts are exactly the overview snapshot, not receipt quantities.
class StockProductFacts extends StatelessWidget {
  final StockManagementItem item;
  const StockProductFacts({super.key, required this.item});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 1100
          ? 4
          : c.maxWidth >= 600
          ? 2
          : 1;
      final width = (c.maxWidth - (columns - 1) * 10) / columns;
      final stock = item.number('total_stock');
      final cover = stock <= 0
          ? 'No Stock'
          : item.days == null
          ? 'No recent sales'
          : '${_qty(item.days)} days';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: width,
                child: _fact(
                  'TOTAL STOCK',
                  _qty(stock),
                  _ink,
                  Icons.inventory_2_outlined,
                  'STORE ${_qty(item.data['store_stock'])}  ·  Branches ${_qty(item.data['branches_stock'])}',
                ),
              ),
              SizedBox(
                width: width,
                child: _fact(
                  'DAYS ON HAND',
                  cover,
                  item.days != null && item.days! < 30 ? _amber : _teal,
                  Icons.hourglass_bottom_rounded,
                  '${_qty(item.data['daily_sales'])} Qty / day · net demand',
                ),
              ),
              SizedBox(
                width: width,
                child: _fact(
                  'STORE / BRANCHES',
                  item.ratio == null ? '—' : '${_qty(item.ratio)}×',
                  _blue,
                  Icons.compare_arrows_rounded,
                  '${_qty(item.data['stocked_branches'])} stocked branches',
                ),
              ),
              SizedBox(
                width: width,
                child: _fact(
                  'LATEST MRN',
                  _date(item.text('last_mrn_date')),
                  _teal,
                  Icons.receipt_long_outlined,
                  'Received ${_qty(item.data['last_mrn_qty'])} · MRN ${item.text('last_mrn_no').isEmpty ? '—' : item.text('last_mrn_no')}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, space) {
              final width = space.maxWidth >= 650
                  ? (space.maxWidth - 10) / 2
                  : space.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final year in [2025, 2026])
                    SizedBox(width: width, child: _year(year, item.year(year))),
                ],
              );
            },
          ),
        ],
      );
    },
  );

  Widget _fact(
    String label,
    String value,
    Color color,
    IconData icon,
    String subtitle,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8FC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE9EEF5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Tooltip(
          message: subtitle,
          child: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    ),
  );
  Widget _year(int year, Map<String, dynamic> data) {
    final color = year == 2025 ? _blue : _teal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$year SALES',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${_qty(data['total'])} Qty',
                style: TextStyle(
                  color: color,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 22,
            runSpacing: 6,
            children: [
              for (final channel in [
                ('Cash', 'cash'),
                ('Insurance', 'insurance'),
                ('Online', 'online'),
              ])
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.$1,
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _qty(data[channel.$2]),
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: Color(0xFFE0E6EF)),
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.emoji_events_outlined, color: color, size: 17),
              Text(
                'Best month: ${_month(data['best_month'])}',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                data['best_qty'] == null ? '' : 'Qty ${_qty(data['best_qty'])}',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
