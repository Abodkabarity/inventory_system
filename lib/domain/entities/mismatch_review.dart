import '../../core/utils/store_branch_identity_registry.dart';

/// Server classifications deliberately separate evidence gaps from suspicion.
class MismatchReview {
  MismatchReview(this.raw);
  final Map<String, dynamic> raw;
  late final int id = (raw['id'] as num).toInt();
  late final String branch = '${raw['branch_name'] ?? ''}';
  late final String code = '${raw['item_code'] ?? ''}';
  late final String name = '${raw['item_name'] ?? ''}';
  late final Map<String, dynamic> analysis = Map<String, dynamic>.unmodifiable(
    raw['analysis'] as Map? ?? const {},
  );
  late final bool stale =
      raw['review_stale'] == true || raw['analysis'] == null;
  late final String status = stale
      ? 'pending'
      : '${analysis['status'] ?? 'pending'}';
  double number(String field) => double.tryParse('${raw[field]}') ?? 0;
  double? evidenceNumber(String field) => double.tryParse('${analysis[field]}');
  late final DateTime? eventAt = DateTime.tryParse(
    '${analysis['event_at'] ?? raw['created_at']}',
  );
  bool get needsFollowup =>
      const ['priority_followup', 'recent_receipt_followup'].contains(status);
  late final int priority =
      const {
        'priority_followup': 0,
        'recent_receipt_followup': 1,
        'adjustment_review': 2,
        'pending': 3,
        'analysis_error': 3,
        'data_review': 4,
        'surplus_review': 5,
        'historical_review': 6,
        'unchanged_discrepancy': 7,
        'resolved': 8,
      }[status] ??
      4;
  bool matches(String search) {
    final q = search.trim().toLowerCase();
    return q.isEmpty ||
        '$name $code $branch ${StoreBranchIdentityRegistry.displayName(branch)}'
            .toLowerCase()
            .contains(q);
  }

  Map<String, dynamic> exportRow() => {
    'branch_name': StoreBranchIdentityRegistry.exportValue(
      'branch_name',
      branch,
    ),
    'item_code': code,
    'item_name': name,
    'system_stock': raw['system_stock'],
    'actual_stock': raw['actual_stock'],
    'diff': raw['diff'],
    'review': reviewTitle(status),
    'event_at': analysis['event_at'],
    'baseline': analysis['baseline_qty'],
    'reconstructed': analysis['reconstructed_before'],
    'last_zero': analysis['last_zero'],
    'last_in': analysis['last_receipt'],
    'last_in_qty': analysis['receipt_qty'],
    'in_type': (analysis['receipt_types'] as List? ?? []).join(', '),
    'out_since_in': analysis['out_since_receipt'],
    'old_shortage': analysis['old_shortage'],
    'added_shortage': analysis['added_shortage'],
    'adjustments': analysis['adjustment_count'],
    'coverage_through': analysis['coverage_through'],
    'issues': (analysis['issues'] as List? ?? [])
        .map((v) => reviewIssue('$v'))
        .join('; '),
  };
}

String reviewTitle(String status) =>
    const {
      'priority_followup': 'Priority follow-up',
      'recent_receipt_followup': 'Check recent receipt',
      'adjustment_review': 'Review adjustment',
      'data_review': 'Evidence incomplete',
      'unchanged_discrepancy': 'No new discrepancy',
      'surplus_review': 'Extra stock',
      'historical_review': 'Historical discrepancy',
      'resolved': 'No difference',
      'pending': 'Analysis pending',
      'analysis_error': 'Analysis unavailable',
    }[status] ??
    'Evidence incomplete';

String reviewIssue(String code) =>
    const {
      'duplicate_active_counts':
          'More than one active mismatch entry exists for this branch and item.',
      'missing_baseline':
          'No unique 1-1-2026 stock reference. Missing stock is not zero.',
      'incomplete_coverage':
          'Movement history does not cover the mismatch report date. Refresh the stock statement source.',
      'opening_boundary':
          '1-1-2026 has movements. Confirm whether the reference is opening or closing stock.',
      'negative_balance':
          'Reconstructed stock becomes negative. Check the reference and missing movements.',
      'same_day_order':
          'Movements exist on the mismatch report date without times. We do not know if they happened before or after the report entry.',
      'system_balance_mismatch':
          'Calculated stock does not match the system stock recorded in this mismatch entry.',
      'company_mismatch':
          'Reference or movement company differs from the authoritative branch group.',
      'unknown_branch_group':
          'Branch group metadata is missing or unsupported.',
      'unexpected_movement':
          'An unexpected movement mode or quantity sign needs review.',
      'invalid_count':
          'Stock values are incomplete or the difference does not match.',
      'missing_previous_diff':
          'The previous discrepancy is missing from the update history.',
      'missing_event_history':
          'No reliable add/update event was found for this active mismatch.',
      'event_values_changed':
          'Current stock values differ from the latest logged event.',
      'overlapping_add':
          'An add event overlaps an earlier discrepancy without a recorded deletion.',
      'unsupported_reference_year':
          'The mismatch report date is outside the 2026 reference period.',
      'analysis_failed':
          'The server could not complete the analysis. Retry the review.',
    }[code] ??
    code;

String reviewRecommendation(String status, {bool customerReturn = false}) {
  final action =
      const {
        'priority_followup':
            'Check the physical stock and the receipt document. System stock reached zero before fresh stock arrived, and no later outgoing movement explains the new shortage.',
        'recent_receipt_followup':
            'Check the recent incoming quantity and the physical stock. Separate the older shortage from the additional missing quantity.',
        'adjustment_review':
            'Check the INVAdjustment document, direction and quantity before following up with the branch. An adjustment does not automatically resolve a discrepancy.',
        'data_review':
            'Resolve the evidence gaps before attributing the shortage to the branch.',
        'unchanged_discrepancy':
            'This update did not increase the discrepancy. Refer to the original event before treating it as a new loss.',
        'surplus_review':
            'Check the physical stock, unposted receipts, returns and item selection. The branch reported extra stock.',
        'historical_review':
            'Use the normal reconciliation process. Available evidence does not establish that the shortage is recent.',
        'resolved': 'This event records no stock difference.',
        'pending':
            'Waiting for a current server analysis. No risk conclusion has been made.',
        'analysis_error':
            'Retry the analysis. Do not treat a failed check as a clear result.',
      }[status] ??
      'Review the available evidence.';
  return customerReturn
      ? '$action The latest incoming movement includes ReturnPOS: verify receipt of the customer return against the sale document.'
      : action;
}
