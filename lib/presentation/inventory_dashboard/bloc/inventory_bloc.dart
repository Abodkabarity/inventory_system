import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/max_adj_export.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../../../domain/entities/mismatch_item.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../orders/widgets/orders_table.dart';
import 'inventory_event.dart';
import 'inventory_state.dart';

class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  final InventoryRepository repo;
  late final RealtimeChannel additionalChannel;
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
    on<ExportMaxAdjTemplate>(_onExportTemplate);
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
    on<LoadMaxAdjustment>((event, emit) async {
      emit(state.copyWith(isLoading: true));

      final data = await repo.fetchMaxAdjustment();

      emit(
        state.copyWith(
          maxAdjustment: data,
          filteredMaxAdjustment: data,
          isLoading: false,
        ),
      );
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
    on<StartMismatchRealtime>((event, emit) {
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
    });

    add(StartMismatchRealtime());
    add(StartAdditionalRealtime());
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
            conflicts.add(data);
          }

          if (event.forceApply) {
            final ok = await repo.importMaxAdjRow(data: data, forceApply: true);

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
            importMessage: "Processing $i / $total",
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

      emit(
        state.copyWith(
          isImporting: false,
          importProgress: 1,
          importSuccess: errors.isEmpty && conflicts.isEmpty,
          importMessage: errors.isEmpty
              ? "Import completed successfully ✅"
              : "Completed with ${errors.length} errors ❌",
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
      await FilePicker.platform.saveFile(
        dialogTitle: "Save Template",
        fileName: "max_adjustment_template.csv",
        bytes: bytes,
      );
    } catch (e) {
      print("Export Template Error: $e");
    }
  }
}
