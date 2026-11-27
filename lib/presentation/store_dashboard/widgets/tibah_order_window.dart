import 'package:flutter/material.dart';

import '../../../domain/entities/tibah_order.dart';

/// A timing explanation, not a clock gate: only fresh prepared results make an
/// upload ready. 9 PM is the user's approximate evening reference, not an SLA.
class TibahOrderWindow extends StatelessWidget {
  const TibahOrderWindow({
    super.key,
    required this.order,
    this.compact = false,
    this.selected = false,
  });

  final TibahOrder order;
  final bool compact;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ready = order.isReady;
    final color = selected
        ? Colors.white
        : ready
        ? const Color(0xFF166534)
        : const Color(0xFF7C2D12);
    final lines = ready
        ? 'Ready to prepare now\nUntil Store confirms completion'
        : 'Next calculation (~9 PM UAE)\nThen until Store confirms';
    const waitingMessage =
        'Printing starts only after the new file is calculated. '
        'If Max was uploaded after the current calculation, wait for the next cycle. '
        'The evening time is approximate.';
    return Tooltip(
      message: ready
          ? 'This file has been calculated. The request stays active until Store confirms preparation finished.'
          : waitingMessage,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ready ? Icons.task_alt : Icons.schedule,
                size: compact ? 12 : 16,
                color: color,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  lines,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 10 : 13,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (!compact && !ready) ...[
            const SizedBox(height: 6),
            const Text(
              'Max uploaded after the current calculation waits for the next cycle.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ],
        ],
      ),
    );
  }
}
