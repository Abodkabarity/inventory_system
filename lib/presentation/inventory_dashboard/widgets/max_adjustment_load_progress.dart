import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Counts refer to validated transport batches; the table is published only
/// after the complete result has arrived, so filters never see a partial view.
class MaxAdjustmentLoadProgress extends StatelessWidget {
  const MaxAdjustmentLoadProgress({
    super.key,
    required this.loaded,
    required this.total,
  });
  final int loaded;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0 ? (loaded / total).clamp(0.0, 1.0) : null;
    final format = NumberFormat.decimalPattern('en');
    final label = fraction == null
        ? 'Counting max adjustments...'
        : 'Loaded ${format.format(loaded)} of ${format.format(total)} records (${(fraction * 100).floor()}%)';
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF9A3412)),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            color: const Color(0xFFEA580C),
            backgroundColor: const Color(0xFFFFEBDD),
          ),
          if (fraction != null && fraction >= 1) ...[
            const SizedBox(height: 6),
            const Text(
              'Preparing the table...',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
