enum TransferStatus { complete, partial, missing, extra, notInDailyOrder }

class TransferReportRow {
  final String branch;
  final String itemCode;
  final String itemName;

  final double requiredQty;
  final double transferredQty;

  final TransferStatus status;

  const TransferReportRow({
    required this.branch,
    required this.itemCode,
    required this.itemName,
    required this.requiredQty,
    required this.transferredQty,
    required this.status,
  });

  double get diff => transferredQty - requiredQty;

  double get completion {
    switch (status) {
      case TransferStatus.complete:
        return 100;

      case TransferStatus.partial:
        return requiredQty == 0 ? 0 : (transferredQty / requiredQty) * 100;

      case TransferStatus.missing:
        return 0;

      case TransferStatus.extra:
        return requiredQty == 0 ? 0 : (transferredQty / requiredQty) * 100;

      case TransferStatus.notInDailyOrder:
        return 0;
    }
  }
}
