import 'package:flutter/material.dart';

import '../../../domain/entities/daily_order_row.dart';

class FinalReorderSidePanel extends StatefulWidget {
  final DailyOrderRow row;
  final int oldQty; // auto qty
  final int initialQty; // current (edited or auto)
  final bool isLimitedStock;

  final VoidCallback onClose;
  final ValueChanged<int> onSave;
  final VoidCallback onReset;

  const FinalReorderSidePanel({
    super.key,
    required this.row,
    required this.oldQty,
    required this.initialQty,
    required this.isLimitedStock,
    required this.onClose,
    required this.onSave,
    required this.onReset,
  });

  @override
  State<FinalReorderSidePanel> createState() => _FinalReorderSidePanelState();
}

class _FinalReorderSidePanelState extends State<FinalReorderSidePanel> {
  late int _qty;

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty;
  }

  bool get _isNonFormulary {
    final f = (widget.row.branchFormulary ?? '')
        .toString()
        .trim()
        .toUpperCase();
    return f == 'NON';
  }

  // ✅ limited stock rule:
  // if limited -> cannot increase above oldQty (only decrease allowed)
  bool get _canIncrease {
    if (widget.isLimitedStock) return false;
    return true;
  }

  bool get _canDecrease {
    // you said: "اذا لا يستطيع الحذف والاضافة" => this is another rule
    // but you didn’t specify exact condition.
    // We'll interpret it as: if oldQty == 0 then cannot decrease below 0 (always)
    return true;
  }

  void _inc() {
    if (!_canIncrease) {
      _showSnack('Limited stock: you can only decrease the quantity.');
      return;
    }
    setState(() => _qty += 1);
  }

  void _dec() {
    if (!_canDecrease) return;
    if (_qty <= 0) return;
    setState(() => _qty -= 1);
  }

  void _showSnack(String msg) {
    final ctx = context;
    ScaffoldMessenger.of(ctx).clearSnackBars();
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 460,
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            bottomLeft: Radius.circular(18),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                title: 'Edit Final Reorder',
                subtitle: '${r.itemCode} • ${r.itemName}',
                onClose: widget.onClose,
              ),
              const Divider(height: 1),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isNonFormulary)
                        _InfoCard(
                          icon: Icons.info_outline,
                          title: 'NON Formulary',
                          body:
                              'This item is NON-formulary. Please send it to the Zone Manager to convert it to ESSENTIAL \n to ensure refill when the product is sold.',
                        ),

                      if (widget.isLimitedStock) const SizedBox(height: 12),

                      if (widget.isLimitedStock)
                        _InfoCard(
                          icon: Icons.warning_amber_rounded,
                          title: 'Limited Stock',
                          body:
                              'The stock for this item is limited, so you cannot increase the quantity. You can only decrease it.',
                        ),

                      const SizedBox(height: 14),

                      _SectionTitle('Final Reorder'),
                      const SizedBox(height: 10),

                      _TwoValuesRow(
                        leftTitle: 'Auto (Old)',
                        leftValue: widget.oldQty.toString(),
                        rightTitle: 'Your Edit (New)',
                        rightValue: _qty.toString(),
                      ),

                      const SizedBox(height: 12),

                      _Stepper(
                        value: _qty,
                        onDec: _dec,
                        onInc: _inc,
                        canInc: _canIncrease,
                        canDec: _qty > 0,
                      ),

                      const SizedBox(height: 10),

                      _DiffChip(oldQty: widget.oldQty, newQty: _qty),

                      const SizedBox(height: 18),

                      _MiniStats(row: r),

                      const SizedBox(height: 18),

                      const Divider(),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: widget.onReset,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset to Auto'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => widget.onSave(_qty),
                              icon: const Icon(Icons.save),
                              label: const Text('Save'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: widget.onClose,
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const _Header({
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

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF6B7280)),
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
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF374151),
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

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

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

class _TwoValuesRow extends StatelessWidget {
  final String leftTitle;
  final String leftValue;
  final String rightTitle;
  final String rightValue;

  const _TwoValuesRow({
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

class _Stepper extends StatelessWidget {
  final int value;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final bool canInc;
  final bool canDec;

  const _Stepper({
    required this.value,
    required this.onDec,
    required this.onInc,
    required this.canInc,
    required this.canDec,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _DiffChip extends StatelessWidget {
  final int oldQty;
  final int newQty;

  const _DiffChip({required this.oldQty, required this.newQty});

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

class _MiniStats extends StatelessWidget {
  final DailyOrderRow row;
  const _MiniStats({required this.row});

  @override
  Widget build(BuildContext context) {
    String t(dynamic v) =>
        (v ?? '').toString().trim().isEmpty ? '—' : v.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Quick info'),
        const SizedBox(height: 10),
        _kv('Store stock', t(row.storeStock)),
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
