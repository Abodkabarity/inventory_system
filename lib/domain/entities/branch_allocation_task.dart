import 'package:equatable/equatable.dart';

class BranchAllocationTask extends Equatable {
  final String id;
  final String batchId;
  final String runDate;
  final String fromBranch;
  final String toBranch;
  final String itemCode;
  final String itemName;
  final num qty;
  final num qtySend;
  final String category;
  final String senderNote;
  final String senderStatus;
  final String receiverStatus;
  final DateTime? sentAt;
  final DateTime? senderConfirmedAt;
  final DateTime? senderBatchFinishedAt;

  const BranchAllocationTask({
    required this.id,
    required this.batchId,
    required this.runDate,
    required this.fromBranch,
    required this.toBranch,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.qtySend,
    required this.category,
    required this.senderNote,
    required this.senderStatus,
    required this.receiverStatus,
    required this.sentAt,
    required this.senderConfirmedAt,
    required this.senderBatchFinishedAt,
  });

  String get normalizedSenderStatus => senderStatus.trim().toLowerCase();

  bool get isSenderPending =>
      normalizedSenderStatus.isEmpty || normalizedSenderStatus == 'pending';
  bool get isSenderConfirmed => normalizedSenderStatus == 'confirmed';
  bool get isNoSend =>
      normalizedSenderStatus == 'no_send' ||
      normalizedSenderStatus == 'rejected' ||
      normalizedSenderStatus == 'reject';
  bool get isSenderDone => isSenderConfirmed || isNoSend;
  bool get isQtyChanged => qtySend != qty;
  bool get isBatchFinished => senderBatchFinishedAt != null;

  BranchAllocationTask copyWith({
    String? id,
    String? batchId,
    String? runDate,
    String? fromBranch,
    String? toBranch,
    String? itemCode,
    String? itemName,
    num? qty,
    num? qtySend,
    String? category,
    String? senderNote,
    String? senderStatus,
    String? receiverStatus,
    DateTime? sentAt,
    DateTime? senderConfirmedAt,
    DateTime? senderBatchFinishedAt,
  }) {
    return BranchAllocationTask(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      runDate: runDate ?? this.runDate,
      fromBranch: fromBranch ?? this.fromBranch,
      toBranch: toBranch ?? this.toBranch,
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      qty: qty ?? this.qty,
      qtySend: qtySend ?? this.qtySend,
      category: category ?? this.category,
      senderNote: senderNote ?? this.senderNote,
      senderStatus: senderStatus ?? this.senderStatus,
      receiverStatus: receiverStatus ?? this.receiverStatus,
      sentAt: sentAt ?? this.sentAt,
      senderConfirmedAt: senderConfirmedAt ?? this.senderConfirmedAt,
      senderBatchFinishedAt:
          senderBatchFinishedAt ?? this.senderBatchFinishedAt,
    );
  }

  static num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse((value ?? '0').toString().replaceAll(',', '')) ?? 0;
  }

  static DateTime? _dt(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  factory BranchAllocationTask.fromMap(Map<String, dynamic> map) {
    return BranchAllocationTask(
      id: (map['id'] ?? '').toString(),
      batchId: (map['batch_id'] ?? '').toString(),
      runDate: (map['run_date'] ?? '').toString(),
      fromBranch: (map['from_branch'] ?? '').toString(),
      toBranch: (map['to_branch'] ?? '').toString(),
      itemCode: (map['item_code'] ?? '').toString(),
      itemName: (map['item_name'] ?? '').toString(),
      qty: _num(map['qty']),
      qtySend: _num(map['qty_send'] ?? map['qty']),
      category: (map['category'] ?? '').toString(),
      senderNote: (map['sender_note'] ?? '').toString(),
      senderStatus: (map['sender_status'] ?? 'pending').toString(),
      receiverStatus: (map['receiver_status'] ?? 'pending').toString(),
      sentAt: _dt(map['sent_at']),
      senderConfirmedAt: _dt(map['sender_confirmed_at']),
      senderBatchFinishedAt: _dt(map['sender_batch_finished_at']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    batchId,
    runDate,
    fromBranch,
    toBranch,
    itemCode,
    itemName,
    qty,
    qtySend,
    category,
    senderNote,
    senderStatus,
    receiverStatus,
    sentAt,
    senderConfirmedAt,
    senderBatchFinishedAt,
  ];
}
