import 'dart:html' as html;
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/assortment_export.dart';
import '../../../core/utils/formulary_export.dart';
import '../../../core/utils/max_adj_export.dart';
import '../../../core/utils/mismatch_export.dart';
import '../../../core/utils/tma_export.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../../../domain/entities/mismatch_item.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../orders/widgets/orders_table.dart';
import 'inventory_event.dart';
import 'inventory_state.dart';

class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  final InventoryRepository repo;
  late final RealtimeChannel additionalChannel;
  late final RealtimeChannel maxAdjChannel;
  late final RealtimeChannel assortmentChannel;
  late final RealtimeChannel formularyChannel;
  String runDate = '';
  late final RealtimeChannel mismatchChannel;
  InventoryBloc(this.repo) : super(InventoryState.initial()) {
    on<LoadInventoryDashboard>(_onLoad);
    on<SelectBranch>(_onSelectBranch);
    on<LoadBranchAnalytics>(_onBranchAnalytics);
    on<ApproveInventoryRequest>(_onApproveInventory);
    on<LoadBranchAdditionalStats>(_onBranchAdditionalStats);

    on<ChangeInventoryPage>((event, emit) {
      emit(state.copyWith(currentPage: event.page));
    });
    on<ImportMaxAdjExcel>(_onImportExcel);
    on<LoadMismatchTracker>(_onLoadMismatchTracker);
    on<LoadMismatch>(_onLoadMismatch);
    on<SearchMismatch>(_onSearchMismatch);
    on<FilterMismatchBranch>(_onFilterMismatchBranch);
    on<UpdateMismatchColumnWidth>(_onUpdateMismatchColumnWidth);
    on<StoreApproveRequests>(_onStoreApprove);
    on<ApproveAllInventoryRequests>(_onApproveAllInventory);
    on<ExportMaxAdjCurrent>(_onExportCurrent);
    on<ExportMaxAdjWithHistory>(_onExportWithHistory);
    on<ImportAssortmentExcel>(_onImportAssortment);
    on<ExportAssortmentTemplate>(_onExportAssortmentTemplate);
    on<ExportAssortmentCurrent>(_onExportAssortmentCurrent);
    on<ExportAssortmentWithHistory>(_onExportAssortmentHistory);
    on<ExportFormularyCurrent>(_onExportFormularyCurrent);
    on<ExportFormularyWithHistory>(_onExportFormularyHistory);
    on<ExportFormularyTemplate>(_onExportFormularyTemplate);
    on<ImportFormularyExcel>(_onImportFormulary);
    on<ImportTmaExcel>(_onImportTma);
    on<ExportTmaTemplate>(_onExportTmaTemplate);
    on<ExportTmaCurrent>(_onExportTmaCurrent);
    on<ExportTmaWithHistory>(_onExportTmaHistory);
    on<ExportMaxAdjTemplate>(_onExportTemplate);
    on<StartFormularyRealtime>((event, emit) {
      formularyChannel = Supabase.instance.client
          .channel('formulary_live')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'branch_formulary',
            callback: (payload) {
              if (!state.isImporting) {
                add(LoadFormulary(silent: true));
              }
            },
          )
          .subscribe();
    });
    on<ExportMismatchCurrent>((event, emit) async {
      try {
        emit(
          state.copyWith(isExporting: true, exportMessage: "Loading data 0%"),
        );

        await Future.delayed(const Duration(milliseconds: 50));

        final data = await repo.fetchMismatchExport(
          onProgress: (p) {
            add(UpdateExportProgress(p));
          },
        );

        emit(state.copyWith(exportMessage: "Generating Excel 90%"));

        await Future.delayed(const Duration(milliseconds: 50));

        await MismatchExcelExporter.export(rows: data, includeHistory: false);

        emit(state.copyWith(isExporting: false));
      } catch (e) {
        emit(state.copyWith(isExporting: false));
      }
    });
    on<UpdateExportProgress>((event, emit) {
      final percent = (event.progress * 100).toStringAsFixed(0);

      emit(state.copyWith(exportMessage: "Loading data $percent%"));
    });
    on<ExportMismatchWithHistory>((event, emit) async {
      try {
        emit(
          state.copyWith(isExporting: true, exportMessage: "Fetching data..."),
        );

        await Future.delayed(const Duration(milliseconds: 50));

        final current = await repo.fetchMismatchExport();
        final log = await repo.fetchMismatchLogExport();

        final merged = [...current, ...log];

        emit(state.copyWith(exportMessage: "Generating Excel..."));

        await Future.delayed(const Duration(milliseconds: 50));

        await MismatchExcelExporter.export(rows: merged, includeHistory: true);

        emit(state.copyWith(isExporting: false, exportMessage: null));
      } catch (e) {
        emit(state.copyWith(isExporting: false));
      }
    });
    on<LoadMismatchStats>((event, emit) async {
      final stats = await repo.fetchMismatchStats(event.branch);

      emit(
        state.copyWith(
          mismatchTotalCount: stats['total'] ?? 0,
          mismatchDiffSum: stats['diff_sum'] ?? 0,
        ),
      );
    });
    on<ResetImportState>((event, emit) {
      emit(
        state.copyWith(
          isImporting: false,
          importProgress: 0,
          importMessage: null,
          importSuccess: false,
        ),
      );
    });
    on<LoadFormulary>((event, emit) async {
      if (!event.silent) {
        emit(state.copyWith(isLoading: true));
      }

      final data = await repo.fetchFormulary();

      emit(
        state.copyWith(
          formulary: data,
          filteredFormulary: data,
          isLoading: false,
        ),
      );
    });

    on<SearchFormulary>((event, emit) {
      final q = event.query.toLowerCase();

      final filtered = state.formulary.where((e) {
        return (e['item_name'] ?? '').toLowerCase().contains(q) ||
            (e['item_code'] ?? '').toLowerCase().contains(q);
      }).toList();

      emit(
        state.copyWith(
          formularySearch: event.query,
          filteredFormulary: filtered,
        ),
      );
    });

    on<LoadFormularyHistory>((event, emit) async {
      emit(state.copyWith(isHistoryLoading: true, formularyHistory: []));

      final data = await repo.fetchFormularyHistory(
        event.itemCode,
        event.branch,
      );

      emit(state.copyWith(isHistoryLoading: false, formularyHistory: data));
    });
    on<LoadAssortment>((event, emit) async {
      if (!event.silent) {
        emit(state.copyWith(isLoading: true));
      }

      final data = await repo.fetchAssortment();

      emit(
        state.copyWith(
          assortment: data,
          filteredAssortment: data,
          isLoading: false,
        ),
      );
    });
    on<SearchAssortment>((event, emit) {
      final q = event.query.toLowerCase();

      final filtered = state.assortment.where((e) {
        return (e['item_name'] ?? '').toString().toLowerCase().contains(q) ||
            (e['item_code'] ?? '').toString().toLowerCase().contains(q);
      }).toList();

      emit(
        state.copyWith(
          assortmentSearch: event.query,
          filteredAssortment: filtered,
        ),
      );
    });

    on<LoadAssortmentHistory>((event, emit) async {
      emit(state.copyWith(isHistoryLoading: true, assortmentHistory: []));

      final data = await repo.fetchAssortmentHistory(
        event.itemCode,
        event.branch,
      );

      emit(state.copyWith(isHistoryLoading: false, assortmentHistory: data));
    });

    on<LoadMaxAdjustment>((event, emit) async {
      emit(state.copyWith(isLoading: true, importMessage: state.importMessage));

      final data = await repo.fetchMaxAdjustment();

      emit(
        state.copyWith(
          maxAdjustment: data,
          filteredMaxAdjustment: data,
          isLoading: false,
          importMessage: state.importMessage,
        ),
      );
    });
    on<StartMaxAdjRealtime>((event, emit) {
      maxAdjChannel = Supabase.instance.client
          .channel('max_adj_live')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'max_adj',
            callback: (payload) {
              if (!state.isImporting) {
                add(LoadMaxAdjustment());
              }
            },
          )
          .subscribe();
    });
    on<LoadTma>((event, emit) async {
      if (!event.silent) {
        emit(state.copyWith(isLoading: true));
      }

      final data = await repo.fetchTma();

      emit(state.copyWith(tma: data, filteredTma: data, isLoading: false));
    });
    on<SearchTma>((event, emit) {
      final q = event.query.toLowerCase();

      final filtered = state.tma.where((e) {
        return (e['item_name'] ?? '').toLowerCase().contains(q) ||
            (e['item_code'] ?? '').toLowerCase().contains(q);
      }).toList();

      emit(state.copyWith(tmaSearch: event.query, filteredTma: filtered));
    });
    on<LoadTmaHistory>((event, emit) async {
      emit(state.copyWith(isHistoryLoading: true, tmaHistory: []));

      final data = await repo.fetchTmaHistory(event.itemCode, event.branch);

      emit(state.copyWith(isHistoryLoading: false, tmaHistory: data));
    });
    on<StartTmaRealtime>((event, emit) {
      Supabase.instance.client
          .channel('tma_live')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tma',
            callback: (payload) {
              if (!state.isImporting) {
                add(LoadTma(silent: true));
              }
            },
          )
          .subscribe();
    });
    on<SearchMaxAdjustment>((event, emit) {
      final q = event.query.toLowerCase();

      final filtered = state.maxAdjustment.where((e) {
        return (e['item_name'] ?? '').toString().toLowerCase().contains(q) ||
            (e['item_code'] ?? '').toString().toLowerCase().contains(q);
      }).toList();

      emit(
        state.copyWith(
          maxAdjSearch: event.query,
          filteredMaxAdjustment: filtered,
        ),
      );
    });
    on<LoadMaxAdjustmentHistory>((event, emit) async {
      emit(state.copyWith(isHistoryLoading: true, maxAdjHistory: []));

      try {
        final data = await repo.fetchMaxAdjustmentHistory(
          event.itemCode,
          event.branch,
        );

        emit(state.copyWith(isHistoryLoading: false, maxAdjHistory: data));
      } catch (e) {
        emit(state.copyWith(isHistoryLoading: false));
      }
    });
    on<StartAdditionalRealtime>((event, emit) {
      additionalChannel = Supabase.instance.client
          .channel('additional_live')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'additional_requests',
            callback: (payload) {
              add(LoadInventoryDashboard(runDate, silent: true));
            },
          )
          .subscribe();
    });
    on<LoadBranchAllChanges>((event, emit) async {
      final data = await repo.fetchBranchAllChanges(event.branch);
      emit(state.copyWith(allChanges: data));
    });
    on<InventorySetColumnVisible>((event, emit) {
      final updated = List<String>.from(state.visibleColumns);

      if (event.visible) {
        updated.add(event.columnKey);
      } else {
        updated.remove(event.columnKey);
      }

      emit(state.copyWith(visibleColumns: updated));
    });
    on<InventoryReorderColumns>((event, emit) {
      final list = List<String>.from(state.columnOrder);

      final item = list.removeAt(event.oldIndex);
      list.insert(event.newIndex, item);

      emit(state.copyWith(columnOrder: list));
    });
    on<InventoryResetColumns>((event, emit) {
      emit(
        state.copyWith(
          visibleColumns: OrdersTable.allColumns.toList(),
          columnOrder: OrdersTable.allColumns.toList(),
        ),
      );
    });
    on<LoadInventoryOrders>((event, emit) async {
      emit(state.copyWith(isOrdersLoading: true));

      final rows = await repo.fetchAllOrders(event.runDate);
      final mapped = rows.map((e) {
        return DailyOrderRow.fromMap(e);
      }).toList();

      emit(state.copyWith(allOrders: mapped, isOrdersLoading: false));
    });
    on<StartAssortmentRealtime>((event, emit) {
      assortmentChannel = Supabase.instance.client
          .channel('assortment_live')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'assortment',
            callback: (payload) {
              if (!state.isImporting) {
                add(LoadAssortment(silent: true));
              }
            },
          )
          .subscribe();
    });
    on<StartMismatchRealtime>((event, emit) {
      if (state.isMismatchRealtimeStarted) return;

      mismatchChannel = Supabase.instance.client
          .channel('mismatch_live_bloc')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'mismatch_log',
            callback: (payload) {
              add(LoadInventoryDashboard(runDate, silent: true));
            },
          )
          .subscribe();

      emit(state.copyWith(isMismatchRealtimeStarted: true));
    });

    add(StartMismatchRealtime());
    add(StartAdditionalRealtime());
    add(StartMaxAdjRealtime());
    add(StartAssortmentRealtime());
    add(StartTmaRealtime());
    add(StartFormularyRealtime());
  }

  /// ================================
  /// LOAD DASHBOARD
  /// ================================
  Future<void> _onLoad(
    LoadInventoryDashboard event,
    Emitter<InventoryState> emit,
  ) async {
    runDate = event.runDate;

    if (!event.silent) {
      emit(state.copyWith(isLoading: true));
    }

    try {
      final branches = await repo.fetchBranchesToday();

      final submitted = await repo.fetchSubmittedBranches(runDate);

      final additional = await repo.fetchAdditionalRequests();

      final mismatchToday = await repo.fetchMismatchToday();
      final mismatchMonth = await repo.fetchMismatchMonth();
      final mismatchTotal = await repo.fetchMismatchTotal();
      final mismatchDiff = await repo.fetchMismatchDiffSum();
      final mismatchData = await repo.fetchMismatch();
      final editsCount = await repo.fetchBranchEditsCount(runDate);

      /// NEW
      final additionalBranchToday = await repo.fetchAdditionalTodayByBranch(
        runDate,
      );

      final pending = additional
          .where((e) => e.status == 'pending_inventory')
          .length;

      final sentToStore = additional
          .where((e) => e.status == 'sent_to_store')
          .length;

      emit(
        state.copyWith(
          branches: branches,
          submittedBranches: submitted,
          additionalRequests: additional,
          editsCount: editsCount,
          additionalTodayBranchCount: additionalBranchToday,
          mismatchTotalCount: mismatchTotal,
          submittedCount: submitted.length,
          additionalCount: additional.length,
          additionalPendingCount: pending,
          additionalSentToStoreCount: sentToStore,
          mismatchTodayCount: mismatchToday,
          mismatchMonthCount: mismatchMonth,
          mismatch: mismatchData,
          mismatchDiffSum: mismatchDiff,
          filteredMismatch: mismatchData,
          isLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false));

      print("InventoryBloc Load Error: $e");
    }
  }

  /// ================================
  /// SELECT BRANCH
  /// ================================
  Future<void> _onSelectBranch(
    SelectBranch event,
    Emitter<InventoryState> emit,
  ) async {
    final branch = event.branch;

    if (state.selectedBranch == branch) return;

    final bool isSubmitted = state.submittedBranches.contains(branch);

    emit(
      state.copyWith(selectedBranch: branch, edits: [], isLoading: isSubmitted),
    );

    if (!isSubmitted) {
      return;
    }

    try {
      final edits = await repo.fetchBranchEdits(
        runDate: runDate,
        branch: branch,
      );

      emit(state.copyWith(edits: edits, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false));

      print("SelectBranch Inventory Error: $e");
    }
  }

  /// ================================
  /// APPROVE INVENTORY REQUEST
  /// ================================
  Future<void> _onApproveInventory(
    ApproveInventoryRequest event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      await repo.approveInventory(id: event.requestId, qty: event.qty);

      /// reload dashboard silently
      add(LoadInventoryDashboard(runDate, silent: true));
    } catch (e) {
      print("Inventory Approve Error: $e");
    }
  }

  Future<void> _onBranchAnalytics(
    LoadBranchAnalytics event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final edits = await repo.fetchBranchEdits(
        runDate: runDate,
        branch: event.branch,
      );

      emit(state.copyWith(selectedBranch: event.branch, edits: edits));
    } catch (e) {
      print("Branch Analytics Error: $e");
    }
  }

  Future<void> _onBranchAdditionalStats(
    LoadBranchAdditionalStats event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final month = await repo.fetchAdditionalMonthByBranch(event.branch);

      final today = await repo.fetchAdditionalTodayByBranchExact(event.branch);

      final monthMap = Map<String, int>.from(state.additionalMonthBranchCount);
      final todayMap = Map<String, int>.from(
        state.additionalTodayBranchExactCount,
      );

      monthMap[event.branch] = month;
      todayMap[event.branch] = today;

      emit(
        state.copyWith(
          additionalMonthBranchCount: monthMap,
          additionalTodayBranchExactCount: todayMap,
        ),
      );
    } catch (e) {
      print("Branch Additional Stats Error: $e");
    }
  }

  Future<void> _onLoadMismatch(
    LoadMismatch event,
    Emitter<InventoryState> emit,
  ) async {
    final data = await repo.fetchMismatch();

    emit(state.copyWith(mismatch: data, filteredMismatch: data));
  }

  void _onSearchMismatch(SearchMismatch event, Emitter<InventoryState> emit) {
    final filtered = _applyMismatchFilters(
      list: state.mismatch,
      search: event.query,
      branch: state.mismatchBranch,
    );

    emit(
      state.copyWith(mismatchSearch: event.query, filteredMismatch: filtered),
    );
  }

  void _onFilterMismatchBranch(
    FilterMismatchBranch event,
    Emitter<InventoryState> emit,
  ) {
    final filtered = _applyMismatchFilters(
      list: state.mismatch,
      search: state.mismatchSearch,
      branch: event.branch,
    );

    emit(
      state.copyWith(mismatchBranch: event.branch, filteredMismatch: filtered),
    );
  }

  List<MismatchItem> _applyMismatchFilters({
    required List<MismatchItem> list,
    required String search,
    required String branch,
  }) {
    var result = list;

    /// search
    if (search.isNotEmpty) {
      final q = search.toLowerCase();

      result = result.where((e) {
        return e.itemName.toLowerCase().contains(q) ||
            e.itemCode.toLowerCase().contains(q);
      }).toList();
    }

    /// branch
    if (branch != 'ALL') {
      result = result.where((e) => e.branchName == branch).toList();
    }

    return result;
  }

  void _onUpdateMismatchColumnWidth(
    UpdateMismatchColumnWidth event,
    Emitter<InventoryState> emit,
  ) {
    final updated = Map<String, double>.from(state.mismatchColumnWidths);

    updated[event.column] = event.width;

    emit(state.copyWith(mismatchColumnWidths: updated));
  }

  Future<void> _onLoadMismatchTracker(
    LoadMismatchTracker event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final data = await repo.fetchMismatchTracker(
        from: event.from,
        to: event.to,
        branch: event.branch,
      );

      emit(state.copyWith(mismatchTracker: data));
    } catch (e) {
      print("Mismatch Tracker Error: $e");
    }
  }

  @override
  Future<void> close() {
    Supabase.instance.client.removeChannel(mismatchChannel);
    Supabase.instance.client.removeChannel(maxAdjChannel);
    Supabase.instance.client.removeChannel(assortmentChannel);
    Supabase.instance.client.removeChannel(formularyChannel);

    return super.close();
  }

  Future<void> _onApproveAllInventory(
    ApproveAllInventoryRequests event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(state.copyWith(isBulkLoading: true));

      await repo.approveAllInventory(event.items);

      final additional = await repo.fetchAdditionalRequests();

      emit(
        state.copyWith(
          additionalRequests: additional,
          isBulkLoading: false,
          bulkSuccess: true,
          bulkMessage: "All requests approved successfully ✅",
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isBulkLoading: false,
          bulkSuccess: false,
          bulkMessage: "Failed to approve requests ❌",
        ),
      );
    }
  }

  Future<void> _onStoreApprove(
    StoreApproveRequests event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(state.copyWith(isBulkLoading: true));

      await repo.storeApprove(event.items);

      final additional = await repo.fetchAdditionalRequests();

      emit(
        state.copyWith(additionalRequests: additional, isBulkLoading: false),
      );
    } catch (e) {
      emit(state.copyWith(isBulkLoading: false));
      print("Store Approve Error: $e");
    }
  }

  Future<void> _onExportCurrent(
    ExportMaxAdjCurrent event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final data = await repo.fetchMaxAdjExport();
      await MaxAdjExcelExporter.export(rows: data, includeHistory: false);
    } catch (e) {
      print("Export Current Error: $e");
    }
  }

  Future<void> _onExportWithHistory(
    ExportMaxAdjWithHistory event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final current = await repo.fetchMaxAdjExport();
      final log = await repo.fetchMaxAdjLogExport();

      final merged = [...current, ...log];

      await MaxAdjExcelExporter.export(rows: merged, includeHistory: true);
    } catch (e) {
      print("Export History Error: $e");
    }
  }

  Future<void> _onImportExcel(
    ImportMaxAdjExcel event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(
        state.copyWith(
          isImporting: true,
          importProgress: 0,
          importMessage: "Picking file...",
          importSuccess: false,
        ),
      );

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) {
        emit(state.copyWith(isImporting: false));
        return;
      }

      final file = result.files.single;
      final content = String.fromCharCodes(file.bytes!);

      final rows = const CsvToListConverter().convert(content);
      // ===============================
      // ✅ HEADER VALIDATION (IMPORTANT)
      // ===============================
      final header = rows.first.map((e) => e.toString().trim()).toList();

      final expected = [
        "branch_name",
        "item_code",
        "item_name",
        "current_demand_30d",
        "max_adjustment_30d",
        "reason",
        "update_date",
        "end_date",
      ];

      if (header.length < expected.length ||
          !List.generate(
            expected.length,
            (i) => expected[i] == header[i],
          ).every((e) => e)) {
        emit(
          state.copyWith(
            isImporting: false,
            importMessage: "❌ Please use the template for import",
            importSuccess: false,
          ),
        );

        return;
      }
      if (rows.length <= 1) {
        emit(
          state.copyWith(isImporting: false, importMessage: "CSV is empty ❌"),
        );
        return;
      }

      final List<Map<String, dynamic>> conflicts = [];
      final List<Map<String, dynamic>> errors = [];

      final total = rows.length - 1;

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        if (row.length < 7) {
          errors.add({"row": row, "error": "Invalid columns"});
          continue;
        }

        try {
          final current = num.tryParse("${row[3]}") ?? 0;
          final max = num.tryParse("${row[4]}") ?? 0;

          final type = max > current
              ? 'INCREASE'
              : max < current
              ? 'DECREASE'
              : 'EQUAL';
          final branch = (row[0]?.toString() ?? '').trim();
          final itemCode = (row[1]?.toString() ?? '').trim();
          final data = {
            'branch_name': branch,
            'item_code': itemCode,
            'item_name': row[2]?.toString() ?? '',
            'current_demand_30d': current,
            'max_adjustment_30d': max,
            'adjustment_type': type,
            'reason': row.length > 5 ? row[5]?.toString() : '',
            'update_date': row.length > 6 ? _parseDate(row[6]) : null,
            'end_date': row.length > 7 ? _parseDate(row[7]) : null,
            'qty': max,
            'added_by': 'inventory',
          };

          final exists = await repo.checkIfExists(
            itemCode: itemCode,
            branch: branch,
          );

          if (exists) {
            final old = await repo.getMaxAdj(
              itemCode: itemCode,
              branch: branch,
            );

            conflicts.add({
              "branch_name": branch,
              "item_code": itemCode,
              "item_name": data['item_name'],

              /// 🔵 OLD
              "old_current_demand": old['current_demand_30d'],
              "old_max_adj": old['max_adjustment_30d'],
              "old_reason": old['reason'],
              "old_adjustment_type": old['adjustment_type'],
              "old_update_date": old['update_date'],
              "old_added_by": old['added_by'],
              "old_end_date": old['end_date'],

              /// 🟢 NEW
              "new_current_demand": data['current_demand_30d'],
              "new_max_adj": data['max_adjustment_30d'],
              "new_reason": data['reason'],
              "new_adjustment_type": data['adjustment_type'],
              "new_update_date": data['update_date'],
              "new_added_by": data['added_by'],
              "new_end_date": data['end_date'],
            });
          }

          if (!exists || event.forceApply) {
            final ok = await repo.importMaxAdjRow(
              data: data,
              forceApply: event.forceApply,
            );

            if (!ok) {
              errors.add(data);
            }
          }
        } catch (e) {
          errors.add({"row": row, "error": e.toString()});
        }

        emit(
          state.copyWith(
            importProgress: i / total,
            importMessage: state.importMessage,
          ),
        );
      }

      if (conflicts.isNotEmpty && !event.forceApply) {
        await MaxAdjExcelExporter.export(
          rows: conflicts,
          includeHistory: false,
        );

        emit(
          state.copyWith(
            isImporting: false,
            importMessage:
                "Found ${conflicts.length} duplicates ⚠️ (file downloaded)",
            importSuccess: false,
          ),
        );

        return;
      }

      if (errors.isNotEmpty) {
        await MaxAdjExcelExporter.export(rows: errors, includeHistory: false);
      }

      final hasErrors = errors.isNotEmpty;
      final hasConflicts = conflicts.isNotEmpty;

      emit(
        state.copyWith(
          isImporting: false,
          importProgress: 1,

          importSuccess: !hasErrors,

          importMessage: hasErrors
              ? "Completed with ${errors.length} errors ❌"
              : hasConflicts
              ? "Import completed successfully ✅"
              : "Import completed successfully ✅",
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isImporting: false,
          importMessage: "Error: $e",
          importSuccess: false,
        ),
      );
    }
  }

  String? _parseDate(dynamic value) {
    if (value == null) return null;

    try {
      final parts = value.toString().split('/'); // 20/04/2026

      return "${parts[2]}-${parts[1]}-${parts[0]}";
    } catch (e) {
      return null;
    }
  }

  Future<void> _onExportTemplate(
    ExportMaxAdjTemplate event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final rows = [
        [
          "branch_name",
          "item_code",
          "item_name",
          "current_demand_30d",
          "max_adjustment_30d",
          "reason",
          "update_date",
          "end_date",
        ],
      ];

      final csv = const ListToCsvConverter().convert(rows);

      final bytes = Uint8List.fromList(csv.codeUnits);

      /// 🔥 Web Download Fix
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);

      html.AnchorElement(href: url)
        ..setAttribute("download", "max_adjustment_template.csv")
        ..click();

      html.Url.revokeObjectUrl(url);
    } catch (e) {
      print("Export Template Error: $e");
    }
  }

  Future<void> _onExportAssortmentCurrent(
    ExportAssortmentCurrent event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(
        state.copyWith(isExporting: true, exportMessage: "Exporting data..."),
      );

      final data = await repo.fetchAssortmentExport();

      await AssortmentExcelExporter.export(rows: data, includeHistory: false);

      emit(
        state.copyWith(isExporting: false, exportMessage: "Export completed"),
      );
    } catch (e) {
      emit(state.copyWith(isExporting: false, exportMessage: "Export failed"));
    }
  }

  Future<void> _onExportAssortmentHistory(
    ExportAssortmentWithHistory event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(
        state.copyWith(
          isExporting: true,
          exportMessage: "Exporting with history...",
        ),
      );

      final current = await repo.fetchAssortmentExport();
      final log = await repo.fetchAssortmentLogExport();

      final merged = [...current, ...log];

      await AssortmentExcelExporter.export(rows: merged, includeHistory: true);

      emit(
        state.copyWith(isExporting: false, exportMessage: "Export completed"),
      );
    } catch (e) {
      emit(state.copyWith(isExporting: false, exportMessage: "Export failed"));
    }
  }

  Future<void> _onImportAssortment(
    ImportAssortmentExcel event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(
        state.copyWith(
          isImporting: true,
          importProgress: 0,
          importMessage: "Picking file...",
          importSuccess: false,
        ),
      );

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) {
        emit(state.copyWith(isImporting: false));
        return;
      }

      final file = result.files.single;
      final content = String.fromCharCodes(file.bytes!);

      final rows = const CsvToListConverter().convert(content);

      /// ===============================
      /// HEADER VALIDATION
      /// ===============================
      final header = rows.first.map((e) => e.toString().trim()).toList();

      final expected = [
        "branch_name",
        "item_code",
        "item_name",
        "reason",
        "assortment_qty",
        "assortment_by",
        "assortment_start",
        "assortment_end",
      ];

      if (header.length < expected.length ||
          !List.generate(
            expected.length,
            (i) => expected[i] == header[i],
          ).every((e) => e)) {
        emit(
          state.copyWith(
            isImporting: false,
            importMessage: "❌ Please use template",
            importSuccess: false,
          ),
        );
        return;
      }

      final total = rows.length - 1;

      final List<Map<String, dynamic>> conflicts = [];
      final List<Map<String, dynamic>> errors = [];

      /// 🔥 نسخة محلية لتحديث الجدول بدون reload
      final List<Map<String, dynamic>> updatedList = List.from(
        state.assortment,
      );

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        try {
          final branch = (row[0]?.toString() ?? '').trim();
          final itemCode = (row[1]?.toString() ?? '').trim();

          final data = {
            'branch_name': branch,
            'item_code': itemCode,
            'item_name': row[2]?.toString(),
            'reason': row[3]?.toString(),
            'assortment_qty': num.tryParse("${row[4]}") ?? 0,
            'assortment_by': row[5]?.toString(),
            'assortment_start': _parseDate(row[6]),
            'assortment_end': _parseDate(row[7]),
          };

          /// 🔥 CHECK EXIST
          final existing = await Supabase.instance.client
              .from('assortment')
              .select()
              .eq('item_code', itemCode)
              .eq('branch_name', branch);

          if (existing.isNotEmpty) {
            conflicts.add({
              "branch_name": branch,
              "item_code": itemCode,
              "item_name": data['item_name'],

              /// 🔴 OLD
              "old_qty": existing.first['assortment_qty'],
              "old_reason": existing.first['reason'],
              "old_by": existing.first['assortment_by'],
              "old_start": existing.first['assortment_start'],
              "old_end": existing.first['assortment_end'],

              /// 🟢 NEW
              "new_qty": data['assortment_qty'],
              "new_reason": data['reason'],
              "new_by": data['assortment_by'],
              "new_start": data['assortment_start'],
              "new_end": data['assortment_end'],
            });
          }

          if (existing.isEmpty || event.forceApply) {
            final ok = await repo.importAssortmentRow(
              data: data,
              forceApply: event.forceApply,
            );

            if (!ok) {
              errors.add(data);
            } else {
              final index = updatedList.indexWhere(
                (e) => e['item_code'] == itemCode && e['branch_name'] == branch,
              );

              if (index != -1) {
                updatedList[index] = {...updatedList[index], ...data};
              } else {
                updatedList.add(data);
              }
            }
          }
        } catch (e) {
          errors.add({"row": row, "error": e.toString()});
        }

        emit(state.copyWith(importProgress: i / total));
      }

      if (conflicts.isNotEmpty && !event.forceApply) {
        await AssortmentExcelExporter.export(
          rows: conflicts,
          includeHistory: false,
        );

        emit(
          state.copyWith(
            isImporting: false,
            importMessage:
                "Found ${conflicts.length} duplicates ⚠️ (file downloaded)",
            importSuccess: false,
          ),
        );

        return;
      }

      if (errors.isNotEmpty) {
        await AssortmentExcelExporter.export(
          rows: errors,
          includeHistory: false,
        );
      }

      emit(
        state.copyWith(
          isImporting: false,
          importProgress: 1,
          importSuccess: errors.isEmpty,
          importMessage: errors.isNotEmpty
              ? "Completed with ${errors.length} errors ❌"
              : "Import completed successfully ✅",

          assortment: updatedList,
          filteredAssortment: updatedList,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isImporting: false,
          importMessage: "Error: $e",
          importSuccess: false,
        ),
      );
    }
  }

  Future<void> _onExportAssortmentTemplate(
    ExportAssortmentTemplate event,
    Emitter<InventoryState> emit,
  ) async {
    final rows = [
      [
        "branch_name",
        "item_code",
        "item_name",
        "reason",
        "assortment_qty",
        "assortment_by",
        "assortment_start",
        "assortment_end",
      ],
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(csv.codeUnits);

    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute("download", "assortment_template.csv")
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  Future<void> _onExportTmaCurrent(
    ExportTmaCurrent event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(state.copyWith(isExporting: true));

      final data = await repo.fetchTmaExport();

      await TmaExcelExporter.export(rows: data, includeHistory: false);
      emit(state.copyWith(isExporting: false));
    } catch (e) {
      emit(state.copyWith(isExporting: false));
    }
  }

  Future<void> _onExportTmaHistory(
    ExportTmaWithHistory event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(state.copyWith(isExporting: true));

      final current = await repo.fetchTmaExport();
      final log = await repo.fetchTmaLogExport();

      final merged = [...current, ...log];

      await TmaExcelExporter.export(rows: merged, includeHistory: true);
      emit(state.copyWith(isExporting: false));
    } catch (e) {
      emit(state.copyWith(isExporting: false));
    }
  }

  Future<void> _onExportTmaTemplate(
    ExportTmaTemplate event,
    Emitter<InventoryState> emit,
  ) async {
    final rows = [
      [
        "branch_name",
        "item_code",
        "item_name",
        "qty_per_duration",
        "start_date",
        "end_date",
      ],
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(csv.codeUnits);

    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute("download", "tma_template.csv")
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  Future<void> _onImportTma(
    ImportTmaExcel event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(
        state.copyWith(
          isImporting: true,
          importProgress: 0,
          importMessage: "Picking file...",
          importSuccess: false,
        ),
      );

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) {
        emit(state.copyWith(isImporting: false));
        return;
      }

      final file = result.files.single;
      final content = String.fromCharCodes(file.bytes!);

      final rows = const CsvToListConverter().convert(content);

      /// ===============================
      /// HEADER VALIDATION
      /// ===============================
      final header = rows.first.map((e) => e.toString().trim()).toList();

      final expected = [
        "branch_name",
        "item_code",
        "item_name",
        "qty_per_duration",
        "start_date",
        "end_date",
      ];

      if (header.length < expected.length ||
          !List.generate(
            expected.length,
            (i) => expected[i] == header[i],
          ).every((e) => e)) {
        emit(
          state.copyWith(
            isImporting: false,
            importMessage: "❌ Please use template",
            importSuccess: false,
          ),
        );
        return;
      }

      final total = rows.length - 1;

      final List<Map<String, dynamic>> conflicts = [];
      final List<Map<String, dynamic>> errors = [];

      /// 🔥 نسخة محلية بدون reload
      final updatedList = List<Map<String, dynamic>>.from(state.tma);

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        try {
          final branch = (row[0]?.toString() ?? '').trim();
          final itemCode = (row[1]?.toString() ?? '').trim();

          final data = {
            'branch_name': branch,
            'item_code': itemCode,
            'item_name': row[2]?.toString(),
            'qty_per_duration': num.tryParse("${row[3]}") ?? 0,
            'start_date': _parseDate(row[4]),
            'end_date': _parseDate(row[5]),
          };

          /// 🔥 CHECK EXIST
          final existing = await Supabase.instance.client
              .from('tma')
              .select()
              .eq('item_code', itemCode)
              .eq('branch_name', branch);

          if (existing.isNotEmpty) {
            conflicts.add({
              "branch_name": branch,
              "item_code": itemCode,
              "item_name": data['item_name'],

              /// OLD
              "old_qty": existing.first['qty_per_duration'],
              "old_start": existing.first['start_date'],
              "old_end": existing.first['end_date'],

              /// NEW
              "new_qty": data['qty_per_duration'],
              "new_start": data['start_date'],
              "new_end": data['end_date'],
            });
          }

          if (existing.isEmpty || event.forceApply) {
            final ok = await repo.importTmaRow(
              data: data,
              forceApply: event.forceApply,
            );

            if (!ok) {
              errors.add(data);
            } else {
              final index = updatedList.indexWhere(
                (e) => e['item_code'] == itemCode && e['branch_name'] == branch,
              );

              if (index != -1) {
                updatedList[index] = {...updatedList[index], ...data};
              } else {
                updatedList.add(data);
              }
            }
          }
        } catch (e) {
          errors.add({"row": row, "error": e.toString()});
        }

        emit(state.copyWith(importProgress: i / total));
      }

      /// 🔥 conflicts
      if (conflicts.isNotEmpty && !event.forceApply) {
        await TmaExcelExporter.export(rows: conflicts, includeHistory: false);

        emit(
          state.copyWith(
            isImporting: false,
            importMessage:
                "Found ${conflicts.length} duplicates ⚠️ (file downloaded)",
            importSuccess: false,
          ),
        );

        return;
      }

      /// 🔥 errors
      if (errors.isNotEmpty) {
        await AssortmentExcelExporter.export(
          rows: errors,
          includeHistory: false,
        );
      }

      emit(
        state.copyWith(
          isImporting: false,
          importProgress: 1,
          importSuccess: errors.isEmpty,
          importMessage: errors.isNotEmpty
              ? "Completed with ${errors.length} errors ❌"
              : "Import completed successfully ✅",

          tma: updatedList,
          filteredTma: updatedList,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isImporting: false,
          importMessage: "Error: $e",
          importSuccess: false,
        ),
      );
    }
  }

  Future<void> _onExportFormularyCurrent(
    ExportFormularyCurrent event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(state.copyWith(isExporting: true));

      final csv = await repo.fetchFormularyExportCsv();

      final bytes = Uint8List.fromList(csv.codeUnits);

      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);

      html.AnchorElement(href: url)
        ..setAttribute("download", "formulary.csv")
        ..click();

      html.Url.revokeObjectUrl(url);

      emit(state.copyWith(isExporting: false));
    } catch (e) {
      emit(state.copyWith(isExporting: false));
      print("Export Formulary Current Error: $e");
    }
  }

  Future<void> _onExportFormularyHistory(
    ExportFormularyWithHistory event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(state.copyWith(isExporting: true));

      /// 🔥 CSV فقط (خفيف جداً)
      final csv = await repo.fetchFormularyLogExportCsv();

      /// 🔥 تحويل CSV → rows
      final lines = csv.split('\n');

      /// حذف header
      if (lines.isNotEmpty) {
        lines.removeAt(0);
      }

      final rows = lines.map((line) {
        final parts = line.split(',');

        return {
          'branch_name': parts.isNotEmpty ? parts[0] : '',
          'item_code': parts.length > 1 ? parts[1] : '',
          'item_name': parts.length > 2 ? parts[2] : '',
          'revised_branch_formulary': parts.length > 3 ? parts[3] : '',
          'revised_date': parts.length > 4 ? parts[4] : '',
          'reason': parts.length > 5 ? parts[5] : '',
        };
      }).toList();

      await FormularyExcelExporter.export(rows: rows, includeHistory: true);

      emit(state.copyWith(isExporting: false));
    } catch (e) {
      emit(state.copyWith(isExporting: false));
      print("Export Formulary History Error: $e");
    }
  }

  Future<void> _onExportFormularyTemplate(
    ExportFormularyTemplate event,
    Emitter<InventoryState> emit,
  ) async {
    final rows = [
      [
        "branch_name",
        "item_code",
        "item_name",
        "revised_branch_formulary",
        "revised_date",
        "reason",
      ],
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(csv.codeUnits);

    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute("download", "formulary_template.csv")
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  Future<void> _onImportFormulary(
    ImportFormularyExcel event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(
        state.copyWith(
          isImporting: true,
          importProgress: 0,
          importMessage: "Picking file...",
          importSuccess: false,
        ),
      );

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) {
        emit(state.copyWith(isImporting: false));
        return;
      }

      final content = String.fromCharCodes(result.files.single.bytes!);
      final rows = const CsvToListConverter().convert(content);

      /// ✅ HEADER VALIDATION
      final header = rows.first.map((e) => e.toString().trim()).toList();

      final expected = [
        "branch_name",
        "item_code",
        "item_name",
        "revised_branch_formulary",
        "revised_date",
        "reason",
      ];

      if (header.length < expected.length ||
          !List.generate(
            expected.length,
            (i) => expected[i] == header[i],
          ).every((e) => e)) {
        emit(
          state.copyWith(
            isImporting: false,
            importMessage: "❌ Please use template",
            importSuccess: false,
          ),
        );
        return;
      }

      final total = rows.length - 1;

      final List<Map<String, dynamic>> conflicts = [];
      final List<Map<String, dynamic>> errors = [];

      final updatedList = List<Map<String, dynamic>>.from(state.formulary);

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        try {
          final branch = (row[0] ?? '').toString().trim();
          final itemCode = (row[1] ?? '').toString().trim();

          final data = {
            'branch_name': branch,
            'item_code': itemCode,
            'item_name': row[2],
            'revised_branch_formulary': row[3],
            'revised_date': _parseDate(row[4]),
            'reason': row[5],
          };

          /// 🔥 CHECK EXIST
          final existing = await Supabase.instance.client
              .from('branch_formulary')
              .select()
              .eq('item_code', itemCode)
              .eq('branch_name', branch);

          if (existing.isNotEmpty) {
            conflicts.add({
              "branch_name": branch,
              "item_code": itemCode,
              "item_name": data['item_name'],

              /// OLD
              "old_formulary": existing.first['revised_branch_formulary'],
              "old_date": existing.first['revised_date'],
              "old_reason": existing.first['reason'],

              /// NEW
              "new_formulary": data['revised_branch_formulary'],
              "new_date": data['revised_date'],
              "new_reason": data['reason'],
            });
          }

          if (existing.isEmpty || event.forceApply) {
            final ok = await repo.importFormularyRow(
              data: data,
              forceApply: event.forceApply,
            );

            if (!ok) {
              errors.add(data);
            } else {
              final index = updatedList.indexWhere(
                (e) => e['item_code'] == itemCode && e['branch_name'] == branch,
              );

              if (index != -1) {
                updatedList[index] = {...updatedList[index], ...data};
              } else {
                updatedList.add(data);
              }
            }
          }
        } catch (e) {
          errors.add({"row": row, "error": e.toString()});
        }

        emit(state.copyWith(importProgress: i / total));
      }

      /// 🔥 conflicts export
      if (conflicts.isNotEmpty && !event.forceApply) {
        await FormularyExcelExporter.export(
          rows: conflicts,
          includeHistory: false,
        );

        emit(
          state.copyWith(
            isImporting: false,
            importMessage:
                "Found ${conflicts.length} duplicates ⚠️ (file downloaded)",
            importSuccess: false,
          ),
        );

        return;
      }

      /// 🔥 errors export
      if (errors.isNotEmpty) {
        await FormularyExcelExporter.export(
          rows: errors,
          includeHistory: false,
        );
      }

      emit(
        state.copyWith(
          isImporting: false,
          importProgress: 1,
          importSuccess: errors.isEmpty,
          importMessage: errors.isNotEmpty
              ? "Completed with ${errors.length} errors ❌"
              : "Import completed successfully ✅",

          formulary: updatedList,
          filteredFormulary: updatedList,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isImporting: false,
          importMessage: "Error: $e",
          importSuccess: false,
        ),
      );
    }
  }
}
