// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/services.dart';

enum KpiExportStage { preparing, writing, packaging, downloading }

class KpiExportProgress {
  final KpiExportStage stage;
  final int processed;
  final int total;

  const KpiExportProgress(this.stage, {this.processed = 0, this.total = 0});
}

class KpiExportCancelled implements Exception {
  const KpiExportCancelled();
}

class KpiExportJob {
  final _cancellation = Completer<void>();
  bool get cancelled => _cancellation.isCompleted;
  void cancel() {
    if (!cancelled) _cancellation.complete();
  }

  void checkCancelled() {
    if (cancelled) throw const KpiExportCancelled();
  }

  Future<T> waitFor<T>(Future<T> operation) async {
    checkCancelled();
    final result = await Future.any<T>([
      operation,
      _cancellation.future.then<T>((_) => throw const KpiExportCancelled()),
    ]);
    checkCancelled();
    return result;
  }
}

/// Builds and compresses Excel in a real browser worker. Flutter web's compute
/// still runs on the UI thread, so it cannot keep this export responsive.
class StockCheckKpiExportWorker {
  static const _libraryAsset = 'assets/workers/exceljs-4.4.0.min.js';
  static const _workerAsset = 'assets/workers/stock_check_kpi_export_worker.js';
  static const _stockReportWorkerAsset =
      'assets/workers/stock_report_export_worker.js';

  static Future<Uint8List> build({
    required List<String> summaryHeaders,
    required List<String> detailHeaders,
    List<List<String>> projectColors = const [],
    required List<int> summaryWidths,
    required List<int> detailWidths,
    required List<List<Object>> summaryRows,
    required Iterable<List<Object>> detailRows,
    required int totalRows,
    required KpiExportJob job,
    bool singleReport = false,
    String sheetName = 'Stock Overview',
    List<String> columnTypes = const [],
    void Function(KpiExportProgress)? onProgress,
  }) async {
    job.checkCancelled();
    onProgress?.call(
      KpiExportProgress(KpiExportStage.preparing, total: totalRows),
    );
    job.checkCancelled();
    // Cache the pinned library, but reload our small worker script for each
    // export. Static and rootBundle string caches survive Flutter hot reload
    // and otherwise keep running an older exporter after its assets change.
    final scriptLoad =
        Future.wait([
          rootBundle.loadString(_libraryAsset),
          // A separate asset also avoids cached KPI scripts being reused for
          // stock reports after an app update. This worker has no summary tab.
          rootBundle.loadString(
            singleReport ? _stockReportWorkerAsset : _workerAsset,
            cache: false,
          ),
        ]).timeout(const Duration(minutes: 5)).catchError((Object error) {
          rootBundle.evict(_libraryAsset); // Failed loads must be retryable.
          throw error;
        });
    final scripts = await Future.any<List<String>>([
      scriptLoad,
      job._cancellation.future.then((_) => throw const KpiExportCancelled()),
    ]);
    job.checkCancelled();
    if (!singleReport &&
        !scripts.last.contains('STOCK_CHECK_KPI_EXPORT_VERSION = 2')) {
      throw StateError(
        'KPI export assets are outdated. Restart the application to load the updated exporter.',
      );
    }
    final url = html.Url.createObjectUrlFromBlob(
      html.Blob([scripts.first, '\n', scripts.last], 'text/javascript'),
    );
    html.Worker? worker;
    StreamSubscription<html.MessageEvent>? messages;
    StreamSubscription<html.Event>? errors;
    Timer? timeout;
    var finished = false;
    Completer<void>? acknowledgement;
    final result = Completer<Uint8List>();
    // Errors can arrive while an acknowledgement is being awaited.
    result.future.ignore();

    void fail(Object error) {
      if (finished) return;
      if (!result.isCompleted) result.completeError(error);
      if (acknowledgement != null && !acknowledgement!.isCompleted) {
        acknowledgement!.completeError(error);
      }
      worker?.terminate();
    }

    void resetTimeout() {
      timeout?.cancel();
      timeout = Timer(const Duration(minutes: 5), () {
        fail(TimeoutException('Export took too long. Please retry.'));
      });
    }

    Future<void> send(Map<String, Object> message) async {
      job.checkCancelled();
      if (result.isCompleted) {
        await result.future; // Surface any earlier worker failure.
        return;
      }
      acknowledgement = Completer<void>();
      acknowledgement!.future.ignore();
      worker!.postMessage(message);
      await acknowledgement!.future;
      acknowledgement = null;
    }

    try {
      worker = html.Worker(url);
      messages = worker.onMessage.listen((event) {
        try {
          resetTimeout();
          final data = event.data as Map;
          switch (data['type']) {
            case 'ready':
              acknowledgement?.complete();
            case 'written':
              onProgress?.call(
                KpiExportProgress(
                  KpiExportStage.writing,
                  processed: data['processed'] as int,
                  total: totalRows,
                ),
              );
              acknowledgement?.complete();
            case 'packaging':
              onProgress?.call(
                KpiExportProgress(
                  KpiExportStage.packaging,
                  processed: totalRows,
                  total: totalRows,
                ),
              );
            case 'done':
              final bytes = data['bytes'];
              result.complete(
                bytes is ByteBuffer ? bytes.asUint8List() : bytes as Uint8List,
              );
            case 'error':
              fail(StateError(data['message'].toString()));
          }
        } catch (error) {
          fail(error);
        }
      });
      errors = worker.onError.listen((event) {
        fail(
          StateError('Excel worker could not run. Please retry the export.'),
        );
      });
      job._cancellation.future.then((_) => fail(const KpiExportCancelled()));
      resetTimeout();
      await send({
        'type': 'start',
        'singleReport': singleReport,
        'sheetName': sheetName,
        'columnTypes': columnTypes,
        'summaryHeaders': summaryHeaders,
        'detailHeaders': detailHeaders,
        'projectColors': projectColors,
        'summaryWidths': summaryWidths,
        'detailWidths': detailWidths,
        'summaryRows': summaryRows,
        'totalRows': totalRows,
      });
      var batch = <List<Object>>[];
      for (final row in detailRows) {
        job.checkCancelled();
        batch.add(row);
        if (batch.length == 250) {
          await send({'type': 'rows', 'rows': batch});
          batch = [];
          // Keep row preparation bounded and let input/animation frames run.
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (batch.isNotEmpty) await send({'type': 'rows', 'rows': batch});
      job.checkCancelled();
      worker.postMessage({'type': 'finish'});
      final bytes = await result.future;
      job.checkCancelled();
      return bytes;
    } finally {
      finished = true;
      timeout?.cancel();
      worker?.terminate();
      await messages?.cancel();
      await errors?.cancel();
      html.Url.revokeObjectUrl(url);
    }
  }
}
