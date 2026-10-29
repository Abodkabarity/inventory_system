import '../../domain/entities/stock_redistribution_plan.dart';
import 'store_branch_identity_registry.dart';

/// Decorate on the main isolate before generic Excel worker processing.
List<Map<String, dynamic>> stockRedistributionExportRows(
  StockRedistributionPlan plan,
) => [
  for (final t in plan.transfers)
    {
      'from_branch': StoreBranchIdentityRegistry.exportValue(
        'from_branch',
        t.from.branch,
      ),
      'to_branch': StoreBranchIdentityRegistry.exportValue(
        'to_branch',
        t.to.branch,
      ),
      'Suggested transfer Qty': t.qty,
      'Donor declared extra Qty': t.from.declaredExtra,
      'Donor protected Qty': t.from.retained,
      'Recipient unfilled need Qty': t.to.need,
      'Transfer reason': t.reason,
    },
];
