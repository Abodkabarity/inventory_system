import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../domain/entities/daily_order_row.dart';

class FinalReorderHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const FinalReorderHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

enum AlertType { info, warning, blocked }

class AlertCard extends StatelessWidget {
  final AlertType type;
  final String title;
  final String body;

  const AlertCard({
    super.key,
    required this.type,
    required this.title,
    required this.body,
  });

  Color get _bg {
    switch (type) {
      case AlertType.info:
        return const Color(0xFFEFF6FF);
      case AlertType.warning:
        return const Color(0xFFFFF7E6);
      case AlertType.blocked:
        return const Color(0xFFFDECEC);
    }
  }

  Color get _border {
    switch (type) {
      case AlertType.info:
        return const Color(0xFFBFDBFE);
      case AlertType.warning:
        return const Color(0xFFFCD34D);
      case AlertType.blocked:
        return const Color(0xFFFCA5A5);
    }
  }

  IconData get _icon {
    switch (type) {
      case AlertType.info:
        return Icons.info_outline;
      case AlertType.warning:
        return Icons.warning_amber_rounded;
      case AlertType.blocked:
        return Icons.block;
    }
  }

  Color get _iconColor {
    switch (type) {
      case AlertType.info:
        return const Color(0xFF1D4ED8);
      case AlertType.warning:
        return const Color(0xFFB45309);
      case AlertType.blocked:
        return const Color(0xFFB91C1C);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: _iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF111827),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: Color(0xFF111827),
      ),
    );
  }
}

class TwoValuesRow extends StatelessWidget {
  final String leftTitle;
  final String leftValue;
  final String rightTitle;
  final String rightValue;

  const TwoValuesRow({
    super.key,
    required this.leftTitle,
    required this.leftValue,
    required this.rightTitle,
    required this.rightValue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatBox(title: leftTitle, value: leftValue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatBox(title: rightTitle, value: rightValue),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String title;
  final String value;

  const _StatBox({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class NumericField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String helperText;
  final ValueChanged<String>? onChanged; // ✅ NEW

  const NumericField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.label,
    required this.helperText,
    this.onChanged, // ✅ NEW
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged, // ✅ NEW
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(9),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4338CA), width: 1.4),
        ),
      ),
    );
  }
}

class ReasonField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool showError;
  final ValueChanged<String>? onChanged; // ✅ NEW

  const ReasonField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.showError,
    this.onChanged, // ✅ NEW
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged, // ✅ NEW
      maxLines: 3,
      decoration: InputDecoration(
        labelText: 'Reason',
        hintText: 'Why are you increasing or decreasing this item?',
        errorText: showError ? 'Reason is required.' : null,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4338CA), width: 1.4),
        ),
      ),
    );
  }
}

class StepperRow extends StatelessWidget {
  final int value;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final bool canInc;
  final bool canDec;
  final bool disabled;

  const StepperRow({
    super.key,
    required this.value,
    required this.onDec,
    required this.onInc,
    required this.canInc,
    required this.canDec,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6E8F0)),
          color: const Color(0xFFFFFFFF),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: canDec ? onDec : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Expanded(
              child: Center(
                child: Text(
                  value.toString(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: canInc ? onInc : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class DiffChip extends StatelessWidget {
  final int oldQty;
  final int newQty;

  const DiffChip({super.key, required this.oldQty, required this.newQty});

  @override
  Widget build(BuildContext context) {
    final diff = newQty - oldQty;
    final isZero = diff == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isZero ? const Color(0xFFF3F4F6) : const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Text(
        isZero ? 'No change' : 'Diff: ${diff > 0 ? '+' : ''}$diff',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class MiniStats extends StatelessWidget {
  final DailyOrderRow row;
  final int storeStock;
  final int maxAllowed;
  final bool onlyDecrease;
  final int reorderQtyNum;
  final int oldQty;

  const MiniStats({
    super.key,
    required this.row,
    required this.storeStock,
    required this.maxAllowed,
    required this.onlyDecrease,
    required this.reorderQtyNum,
    required this.oldQty,
  });

  @override
  Widget build(BuildContext context) {
    String t(dynamic v) =>
        (v ?? '').toString().trim().isEmpty ? '—' : v.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Quick info'),
        const SizedBox(height: 10),
        _kv('Store stock', storeStock.toString()),
        _kv('Reorder qty (num)', reorderQtyNum.toString()),
        if (onlyDecrease) _kv('Rule', 'Increase disabled (only decrease)'),
        _kv('Max allowed (this branch)', maxAllowed.toString()),
        _kv('Auto (Old)', oldQty.toString()),
        _kv('Branch stock', t(row.branchStock)),
        _kv('Demand 30d', t(row.demandFor30Days)),
        _kv('Purchase type', t(row.itemPurchaseType)),
        _kv('Formulary', t(row.branchFormulary)),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: const TextStyle(color: Color(0xFF6B7280))),
          ),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
