import 'dart:typed_data';

abstract class TransferReportEvent {}

class ImportTransferFile extends TransferReportEvent {
  final Uint8List bytes;

  final String runDate;

  ImportTransferFile({required this.bytes, required this.runDate});
}

class ImportSeventyOneDvnFile extends TransferReportEvent {
  final Uint8List bytes;
  final String fileName;
  final String runDate;

  ImportSeventyOneDvnFile({
    required this.bytes,
    required this.fileName,
    required this.runDate,
  });
}

class ChangeStatusFilter extends TransferReportEvent {
  final String status;

  ChangeStatusFilter(this.status);
}
