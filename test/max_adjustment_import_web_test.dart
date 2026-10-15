@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:daily_order/core/utils/max_adjustment_import.dart';
import 'package:daily_order/domain/repositories/inventory_repository.dart';
import 'package:daily_order/presentation/inventory_dashboard/bloc/inventory_bloc.dart';
import 'package:daily_order/presentation/inventory_dashboard/bloc/inventory_event.dart';
import 'package:daily_order/presentation/inventory_dashboard/bloc/inventory_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CsvPicker extends FilePicker {
  CsvPicker(this.bytes);
  final Uint8List bytes;
  int picks = 0;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    picks++;
    await Future<void>.delayed(Duration.zero);
    return FilePickerResult([
      PlatformFile(name: 'fixture.csv', size: bytes.length, bytes: bytes),
    ]);
  }
}

class ImportRepository implements InventoryRepository {
  final records = <String, Map<String, dynamic>>{};
  final batches = <int>[];
  int reads = 0;
  int writes = 0;
  int? failBatch;
  bool failReadsAfterWrite = false;
  Completer<void>? holdFirstRead;
  Completer<void>? firstReadStarted;
  @override
  Future<Map<String, dynamic>> fetchMaxAdjustmentPage({
    required int from,
    required int to,
    String query = '',
  }) async {
    reads++;
    final snapshot = records.values
        .where(
          (r) => query.isEmpty || r['item_code'].toString().contains(query),
        )
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    if (reads == 1 && holdFirstRead != null) {
      firstReadStarted?.complete();
      await holdFirstRead!.future;
    }
    if (failReadsAfterWrite && writes > 0) {
      throw StateError('Read unavailable');
    }
    final end = (to + 1).clamp(0, snapshot.length);
    return {
      'rows': from >= snapshot.length
          ? <Map<String, dynamic>>[]
          : snapshot.sublist(from, end),
      'total': snapshot.length,
    };
  }

  @override
  Future<void> importMaxAdjBulk(List<Map<String, dynamic>> rows) async {
    writes++;
    if (writes == failBatch) throw StateError('Simulated failed batch');
    batches.add(rows.length);
    for (final row in rows) {
      records[row['item_code'].toString()] = {
        ...row,
        'id': 'server-${row['item_code']}',
        'created_at': '2026-10-15T10:00:00+04:00',
      };
    }
  }

  @override
  Future<void> deleteMaxAdjBulk(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      records.remove(row['item_code']);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CsvPicker pickRows(List<String> codes) {
  final csv = const ListToCsvConverter(eol: '\n').convert([
    maxAdjustmentImportHeaders,
    for (final code in codes)
      ['ADD', 'City', code, 'Item $code', 1, 3, 'Reason', '2026-10-15', ''],
  ]);
  final picker = CsvPicker(Uint8List.fromList(utf8.encode(csv)));
  FilePicker.platform = picker;
  return picker;
}

Future<InventoryState> waitFinished(InventoryBloc bloc) => bloc.stream
    .firstWhere(
      (s) =>
          !s.isImporting &&
          (s.importMessage ?? '').isNotEmpty &&
          !(s.importMessage ?? '').contains('Picking'),
    )
    .timeout(const Duration(seconds: 15));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (!request.url.path.endsWith('/branches')) {
          throw StateError('Unexpected external request');
        }
        return http.Response(
          jsonEncode([
            {'branch_name': 'City'},
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  test(
    'large browser import refreshes all server rows before 100% and ignores double uploads',
    () async {
      final repo = ImportRepository();
      final bloc = InventoryBloc(repo);
      final picker = pickRows([for (var i = 0; i < 1501; i++) '$i']);
      final states = <InventoryState>[];
      final subscription = bloc.stream.listen(states.add);
      final finished = waitFinished(bloc);
      bloc.add(ImportMaxAdjExcel(forceApply: true));
      bloc.add(ImportMaxAdjExcel(forceApply: true));
      final result = await finished;
      expect(result.importSuccess, true, reason: result.importMessage);
      expect(picker.picks, 1);
      expect(repo.batches, [250, 250, 250, 250, 250, 250, 1]);
      expect(repo.reads, 4);
      expect(result.maxAdjTotalRows, 1501);
      expect(result.filteredMaxAdjustment.last['id'], 'server-1500');
      expect(
        states.where((s) => s.isImporting).every((s) => s.importProgress < 1),
        true,
      );
      final progress = states.map((s) => s.importProgress).toList();
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1] - 1e-12));
      }
      await subscription.cancel();
      await bloc.close();
    },
  );

  test('old in-flight loads cannot overwrite imported records', () async {
    final repo = ImportRepository()
      ..holdFirstRead = Completer<void>()
      ..firstReadStarted = Completer<void>();
    final bloc = InventoryBloc(repo);
    bloc.add(LoadMaxAdjustment());
    await repo.firstReadStarted!.future;
    pickRows(['new']);
    final finished = waitFinished(bloc);
    bloc.add(ImportMaxAdjExcel(forceApply: true));
    await finished;
    repo.holdFirstRead!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bloc.state.filteredMaxAdjustment.single['item_code'], 'new');
    await bloc.close();
  });

  test(
    'duplicate scan reads beyond one API page and skip keeps existing values',
    () async {
      final repo = ImportRepository();
      for (var i = 0; i < 600; i++) {
        repo.records['$i'] = {
          'branch_name': 'City',
          'item_code': '$i',
          'max_adjustment_30d': 99,
        };
      }
      final bloc = InventoryBloc(repo);
      pickRows(['599', 'new']);
      var finished = waitFinished(bloc);
      bloc.add(ImportMaxAdjExcel(forceApply: false));
      final decision = await finished;
      expect(decision.importDuplicateCount, 1);
      expect(repo.writes, 0);
      finished = waitFinished(bloc);
      bloc.add(
        ResolveImportDuplicates(ImportDuplicateAction.applyWithoutDuplicates),
      );
      final result = await finished;
      expect(result.importSuccess, true, reason: result.importMessage);
      expect(result.maxAdjTotalRows, 601);
      expect(repo.records['599']!['max_adjustment_30d'], 99);
      expect(repo.records.containsKey('new'), true);
      await bloc.close();
    },
  );

  test(
    'failed batch resyncs confirmed changes and always releases importing state',
    () async {
      final repo = ImportRepository()..failBatch = 2;
      final bloc = InventoryBloc(repo);
      pickRows([for (var i = 0; i < 700; i++) '$i']);
      final finished = waitFinished(bloc);
      bloc.add(ImportMaxAdjExcel(forceApply: true));
      final result = await finished;
      expect(result.importSuccess, false);
      expect(result.isImporting, false);
      expect(repo.writes, 2);
      expect(result.maxAdjTotalRows, 250);
      expect(result.importMessage, contains('250 confirmed records'));
      await bloc.close();
    },
  );

  test(
    'failed post-save refresh exposes retry without reapplying writes',
    () async {
      final repo = ImportRepository()..failReadsAfterWrite = true;
      final bloc = InventoryBloc(repo);
      pickRows(['new']);
      final finished = waitFinished(bloc);
      bloc.add(ImportMaxAdjExcel(forceApply: true));
      final result = await finished;
      expect(result.importSuccess, false);
      expect(result.maxAdjLoadError, isNotEmpty);
      expect(result.importMessage, contains('1 records confirmed saved'));
      repo.failReadsAfterWrite = false;
      final refreshed = bloc.stream.firstWhere(
        (s) => !s.isMaxAdjLoading && s.maxAdjTotalRows == 1,
      );
      bloc.add(LoadMaxAdjustment());
      await refreshed;
      expect(bloc.state.maxAdjLoadError, isEmpty);
      expect(repo.writes, 1);
      await bloc.close();
    },
  );
}
