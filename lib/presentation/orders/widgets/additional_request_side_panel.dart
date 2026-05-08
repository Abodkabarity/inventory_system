import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/daily_order_row.dart';

class SentAdditionalRequest {
  final num qty;
  final String reason;
  final DateTime createdAt;

  const SentAdditionalRequest({
    required this.qty,
    required this.reason,
    required this.createdAt,
  });
}

class AdditionalRequestSidePanel extends StatefulWidget {
  final DailyOrderRow row;

  // existing draft (if any)
  final num? initialQty;
  final String initialReason;
  final bool initialIsUrgent;
  // NEW: full history for this item (today / run_date)
  final List<SentAdditionalRequest> sentHistory;

  final VoidCallback onClose;

  // save draft (local)
  final void Function(num qty, String reason, bool isUrgent) onSave;
  // remove draft
  final VoidCallback onRemove;

  const AdditionalRequestSidePanel({
    super.key,
    required this.row,
    required this.initialQty,
    required this.initialReason,
    required this.sentHistory,
    required this.onClose,
    required this.onSave,
    required this.onRemove,
    required this.initialIsUrgent,
  });

  @override
  State<AdditionalRequestSidePanel> createState() =>
      _AdditionalRequestSidePanelState();
}

class _AdditionalRequestSidePanelState
    extends State<AdditionalRequestSidePanel> {
  late final TextEditingController _qty;
  String? _selectedReason;
  String? _error;
  final List<String> reasons = [
    'Availability',
    'RX Demand',
    'High Demand',
    'For Shelf',
    'Stand',
    'RX',
    'Customer Request',
    'Urgent Customer Request',
  ];
  bool isUrgent = false;
  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(
      text: widget.initialQty == null ? '' : widget.initialQty.toString(),
    );
    _selectedReason = widget.initialReason.isEmpty
        ? null
        : widget.initialReason;
    isUrgent = widget.initialIsUrgent;
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _error = null);

    final qtyStr = _qty.text.trim();
    final reason = _selectedReason ?? '';
    if (qtyStr.isEmpty) {
      setState(() => _error = 'Qty is required.');
      return;
    }

    final q = num.tryParse(qtyStr.replaceAll(',', ''));
    if (q == null) {
      setState(() => _error = 'Qty must be a number.');
      return;
    }

    if (reason.isEmpty) {
      setState(() => _error = 'Reason is required.');
      return;
    }

    // NO LIMITS / NO CONSTRAINTS
    widget.onSave(q, reason, isUrgent);
  }

  num _sumSent(List<SentAdditionalRequest> list) {
    num total = 0;
    for (final x in list) {
      total += x.qty;
    }
    return total;
  }

  String _fmtDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final m = two(dt.month);
    final d = two(dt.day);
    final hh = two(dt.hour);
    final mm = two(dt.minute);
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.sentHistory;
    final totalSent = _sumSent(history);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 420,
        height: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(22),
            bottomLeft: Radius.circular(22),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 26,
              offset: Offset(-6, 0),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              title: 'Additional Request',
              subtitle: '${widget.row.itemCode} • ${widget.row.itemName}',
              onClose: widget.onClose,
            ),
            const SizedBox(height: 14),

            if (history.isNotEmpty) ...[
              _InfoBox(
                title: 'Previously sent',
                value: 'Count: ${history.length} • Total qty: $totalSent',
                icon: Icons.history_outlined,
              ),
              const SizedBox(height: 10),

              _FieldLabel('Today history'),
              const SizedBox(height: 6),

              // Scrollable history list (won’t push buttons off screen)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE6E8F0)),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: history.length,
                    separatorBuilder: (_, _) => const Divider(height: 14),
                    itemBuilder: (context, i) {
                      final h = history[i];
                      return _HistoryRow(
                        qty: h.qty,
                        reason: h.reason,
                        createdAt: _fmtDateTime(h.createdAt),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            _FieldLabel('Request Qty'),
            TextField(
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: 'Enter Your Additional Quantity',
                filled: true,
                fillColor: AppColors.backgroundWidget,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 12),

            _FieldLabel('Reason'),
            DropdownButtonFormField<String>(
              initialValue: _selectedReason,
              items: reasons
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(
                        r,
                        style: TextStyle(color: AppColors.secondaryColor),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _selectedReason = v;
                });
              },
              dropdownColor: AppColors.white,
              decoration: InputDecoration(
                hintText: 'Select reason...',
                filled: true,
                fillColor: AppColors.backgroundWidget,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primaryColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primaryColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Checkbox(
                  value: isUrgent,
                  activeColor: AppColors.primaryColor,

                  onChanged: (v) {
                    setState(() {
                      isUrgent = v ?? false;
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    "Urgent customer – We contacted logistics for delivery",
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],

            const Spacer(),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onRemove,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.white,
                    ),
                    label: const Text(
                      'Remove Draft',
                      style: TextStyle(color: AppColors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                    ),
                    label: const Text('Save Draft'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final num qty;
  final String reason;
  final String createdAt;

  const _HistoryRow({
    required this.qty,
    required this.reason,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: AppColors.primaryColor,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE6E8F0)),
          ),
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: AppColors.secondaryColor,
            ),
          ),
        ),
        title: Text(
          reason,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.secondaryColor,
          ),
        ),
        subtitle: Text(
          createdAt,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
            fontSize: 12,
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.secondaryColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _InfoBox({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundWidget,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF111827)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
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

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          color: Color(0xFF111827),
        ),
      ),
    );
  }
}
