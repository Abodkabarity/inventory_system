import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'stock_selectable_cell_text.dart';

/// total_qty already includes the reported total; bonus is a note only.
class StockReceiptQuantity extends StatelessWidget {
  final num quantity, bonus;
  final double fontSize;
  const StockReceiptQuantity({
    super.key,
    required this.quantity,
    this.bonus = 0,
    this.fontSize = 16,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      StockSelectableCellText(
        NumberFormat('#,##0.##').format(quantity),
        style: TextStyle(
          color: const Color(0xFF142C40),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (bonus > 0)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF5EF),
            borderRadius: BorderRadius.circular(7),
          ),
          child: StockSelectableCellText(
            'Bonus ${NumberFormat('#,##0.##').format(bonus)}',
            style: const TextStyle(
              color: Color(0xFF26735D),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ],
  );
}
