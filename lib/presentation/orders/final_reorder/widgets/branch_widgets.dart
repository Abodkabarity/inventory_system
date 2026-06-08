import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';
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
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.backgroundWidget,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.secondaryColor,
              fontWeight: FontWeight.bold,
            ),
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
  final ValueChanged<String>? onChanged;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final bool canInc;
  final bool canDec;
  final int maxAllowed;
  const NumericField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.label,
    required this.helperText,
    this.onChanged,
    required this.onDec,
    required this.onInc,
    required this.canInc,
    required this.canDec,
    required this.maxAllowed,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(9),
        TextInputFormatter.withFunction((oldValue, newValue) {
          final val = int.tryParse(newValue.text);

          if (val == null) return newValue;

          if (val > maxAllowed) {
            return oldValue;
          }

          return newValue;
        }),
      ],

      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: AppColors.secondaryColor,
      ),

      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        filled: true,
        labelStyle: TextStyle(color: AppColors.secondaryColor),
        fillColor: AppColors.backgroundWidget,
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
          borderSide: const BorderSide(
            color: AppColors.primaryColor,
            width: 1.4,
          ),
        ),
        prefixIcon: IconButton(
          onPressed: canDec ? onDec : null,
          icon: Icon(
            Icons.remove_circle_outline,
            color: canDec ? AppColors.secondaryColor : Colors.grey,
          ),
        ),
        suffixIcon: IconButton(
          onPressed: canInc ? onInc : null,
          icon: Icon(
            Icons.add_circle_outline,
            color: canInc ? AppColors.secondaryColor : Colors.grey,
          ),
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
      maxLines: 1,
      decoration: InputDecoration(
        labelText: 'Reason',
        hintText: 'Why are you increasing or decreasing this item?',
        errorText: showError ? 'Reason is required.' : null,
        filled: true,
        fillColor: AppColors.backgroundWidget,
        labelStyle: TextStyle(color: AppColors.secondaryColor),
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
          borderSide: const BorderSide(
            color: AppColors.primaryColor,
            width: 1.4,
          ),
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
        color: isZero ? AppColors.backgroundWidget : const Color(0xFFEEF2FF),
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
  final int minReOrder;
  final int storeStock;
  final bool onlyDecrease;
  final int reorderQtyNum;
  final int maxReorder;

  const MiniStats({
    super.key,
    required this.row,
    required this.minReOrder,
    required this.storeStock,
    required this.onlyDecrease,
    required this.reorderQtyNum,
    required this.maxReorder,
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
        Row(
          children: [
            Expanded(child: _kv('Store Stock', storeStock.toString())),
            SizedBox(width: 5),
            Expanded(child: _kv('Min Reorder', minReOrder.toString())),
          ],
        ),
        Row(
          children: [
            Expanded(child: _kv('Max Reorder', maxReorder.toString())),
            SizedBox(width: 5),
            Expanded(child: _kv('Reorder QTY', reorderQtyNum.toString())),
          ],
        ),
        Row(
          children: [
            Expanded(child: _kv('Mismatch', t(row.mismatchStock))),
            SizedBox(width: 5),
            Expanded(child: _kv('Formulary', t(row.branchFormulary))),
          ],
        ),

        Center(child: _kv('Purchase Type', t(row.itemPurchaseType))),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: 300.w,
        height: 30.h,
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          color: AppColors.backgroundWidget,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text(k, style: const TextStyle(color: Color(0xFF6B7280))),
            SizedBox(width: 10.w),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
