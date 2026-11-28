@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:daily_order/domain/repositories/inventory_repository.dart';
import 'package:daily_order/presentation/inventory_dashboard/bloc/inventory_bloc.dart';
import 'package:daily_order/presentation/inventory_dashboard/bloc/inventory_event.dart';
import 'package:daily_order/presentation/inventory_dashboard/bloc/inventory_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MaxPerformanceRepository implements InventoryRepository {
  int reads = 0;
  int currentExports = 0;
  int historyExports = 0;
  int count = 9001;
  Completer<void>? hold;
  bool fail = false;
  Map<String, dynamic> row(int i) => {
    'id': i,
    'branch_name': 'City',
    'item_code': '00$i',
    'item_name': 'Item $i',
    'current_demand_30d': 1,
    'max_adjustment_30d': 3,
    'qty': 3,
    'adjustment_type': 'INCREASE',
    'update_date': '2026-11-01',
    'added_by': 'inventory',
  };
  @override
  Future<Map<String, dynamic>> fetchMaxAdjustmentPage({
    required int from,
    required int to,
    String query = '',
  }) async {
    reads++;
    if (hold != null) await hold!.future;
    await Future<void>.delayed(const Duration(milliseconds: 3));
    final total = query.isEmpty ? count : 1;
    return {
      'total': total,
      'rows': [for (var i = from; i <= to && i < total; i++) row(i)],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMaxAdjExport({
    void Function(int, int)? onProgress,
  }) async {
    currentExports++;
    onProgress?.call(0, 1);
    await Future<void>.delayed(const Duration(milliseconds: 3));
    onProgress?.call(1, 1);
    return [row(1)];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMaxAdjLogExport({
    void Function(int, int)? onProgress,
  }) async {
    historyExports++;
    onProgress?.call(0, 1);
    await Future<void>.delayed(const Duration(milliseconds: 3));
    if (fail) throw StateError('History changed. Please retry.');
    onProgress?.call(1, 1);
    return [
      {...row(2), 'action_type': 'UPDATE', 'moved_at': '2026-11-20T10:12:35'},
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<InventoryState> loaded(InventoryBloc bloc) => bloc.stream
    .firstWhere((s) => !s.isMaxAdjLoading)
    .timeout(const Duration(seconds: 15));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Browser unit tests have no native asset channel. Serve the same pinned
    // files through the local test server rather than mock the Excel worker.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          if (!key.startsWith('assets/workers/')) return null;
          final response = await http.get(
            Uri.parse(
              const String.fromEnvironment(
                'MAX_EXPORT_TEST_ASSETS',
                defaultValue: 'http://127.0.0.1:8767/',
              ),
            ).resolve(key.split('/').last),
          );
          if (response.statusCode != 200)
            throw StateError('Test export asset unavailable: $key');
          return ByteData.sublistView(response.bodyBytes);
        });
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    await Supabase.instance.dispose();
  });

  test(
    'loads 9,001 rows in three requests; progress advances and recent reopens reuse rows',
    () async {
      final repo = MaxPerformanceRepository();
      final bloc = InventoryBloc(repo);
      final states = <InventoryState>[];
      final subscription = bloc.stream.listen(states.add);
      final finished = loaded(bloc);
      bloc.add(LoadMaxAdjustment());
      final result = await finished;
      expect(repo.reads, 3);
      expect(result.filteredMaxAdjustment.length, 9001);
      expect(
        states.where((s) => s.isMaxAdjLoading).map((s) => s.maxAdjLoadedRows),
        [0, 4000, 8000, 9001],
      );
      expect(result.maxAdjLoadedRows, 9001);
      bloc.add(LoadMaxAdjustment(silent: true, reuseRecent: true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repo.reads, 3);
      expect(
        identical(
          bloc.state.filteredMaxAdjustment,
          result.filteredMaxAdjustment,
        ),
        true,
      );
      final refreshed = loaded(bloc);
      bloc.add(LoadMaxAdjustment(silent: true));
      await refreshed;
      expect(repo.reads, 6);
      final search = loaded(bloc);
      bloc.add(LoadMaxAdjustment(query: 'search', reuseRecent: true));
      await search;
      expect(bloc.state.filteredMaxAdjustment.length, 1);
      await subscription.cancel();
      await bloc.close();
    },
  );

  test(
    'duplicate opens share the in-flight read and empty snapshots are reusable',
    () async {
      final repo = MaxPerformanceRepository()
        ..count = 0
        ..hold = Completer<void>();
      final bloc = InventoryBloc(repo);
      final finished = loaded(bloc);
      bloc.add(LoadMaxAdjustment());
      await bloc.stream.firstWhere((s) => s.isMaxAdjLoading);
      bloc.add(LoadMaxAdjustment(reuseRecent: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.reads, 1);
      repo.hold!.complete();
      await finished;
      bloc.add(LoadMaxAdjustment(reuseRecent: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.reads, 1);
      expect(bloc.state.maxAdjTotalRows, 0);
      await bloc.close();
    },
  );

  test(
    'real browser worker exports history with monotonic progress and retry after failure',
    () async {
      final repo = MaxPerformanceRepository()..fail = true;
      final bloc = InventoryBloc(repo);
      final states = <InventoryState>[];
      final subscription = bloc.stream.listen(states.add);
      Future<InventoryState> exported() => bloc.stream
          .firstWhere((s) => !s.isExporting && s.exportMessage != null)
          .timeout(const Duration(seconds: 60));
      final failed = exported();
      bloc.add(ExportMaxAdjWithHistory());
      final failure = await failed;
      expect(failure.exportMessage, contains('History changed'));
      expect(failure.maxAdjExportProgress, lessThan(1));
      repo.fail = false;
      states.clear();
      final finished = exported();
      bloc.add(ExportMaxAdjWithHistory());
      bloc.add(ExportMaxAdjWithHistory());
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => ticks++,
      );
      final result = await finished;
      timer.cancel();
      expect(result.exportMessage, 'Export completed');
      expect(result.maxAdjExportProgress, 1);
      expect(repo.currentExports, 2);
      expect(repo.historyExports, 2);
      expect(ticks, greaterThan(0));
      expect(
        states.any((s) => (s.exportMessage ?? '').contains('Writing Excel:')),
        true,
      );
      expect(
        states.any(
          (s) => (s.exportMessage ?? '').contains('Compressing Excel file'),
        ),
        true,
      );
      final progress = states.map((s) => s.maxAdjExportProgress).toList();
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      expect(
        states
            .where((s) => s.isExporting)
            .every((s) => s.maxAdjExportProgress < 1),
        true,
      );
      await subscription.cancel();
      await bloc.close();
    },
  );
}
