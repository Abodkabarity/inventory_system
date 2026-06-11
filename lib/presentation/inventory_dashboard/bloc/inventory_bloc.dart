import 'dart:convert';
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
  static final Map<String, List<DailyOrderRow>> ordersCache = {};
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
    on<LoadAdditionalOrderAnalysis>(_onLoadAdditionalOrderAnalysis);
    on<ExportMaxAdjCurrent>(_onExportCurrent);
    on<ExportMaxAdjWithHistory>(_onExportWithHistory);
    on<ImportAssortmentExcel>(_onImportAssortment);
    on<ExportAssortmentTemplate>(_onExportAssortmentTemplate);
    on<ExportAssortmentCurrent>(_onExportAssortmentCurrent);
    on<ExportAssortmentWithHistory>(_onExportAssortmentHistory);
    on<ExportFormularyCurrent>(_onExportFormularyCurrent);
    on<ExportFormularyWithHistory>(_onExportFormularyHistory);
    on<ExportInventoryOrders>(_onExportInventoryOrders);
    on<ExportFormularyTemplate>(_onExportFormularyTemplate);
    on<ImportFormularyExcel>(_onImportFormulary);
    on<LoadOrdersPage>(_onLoadOrdersPage);
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
    on<UpdateExportDailyProgress>((event, emit) {
      emit(
        state.copyWith(
          isExporting: true,
          importProgress: event.progress,
          exportMessage: event.message,
        ),
      );
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

      final cacheKey = event.runDate;

      // CACHE HIT
      if (ordersCache.containsKey(cacheKey)) {
        emit(
          state.copyWith(
            cachedOrders: ordersCache[cacheKey]!,
            allOrders: ordersCache[cacheKey]!,
            loadedCount: ordersCache[cacheKey]!.length,
            currentOrdersPage: 0,
            hasMorePages: false,
            isOrdersLoading: false,
            allDataLoaded: true,
          ),
        );
        return;
      }

      try {
        // FIRST 10K
        final firstBatch = await repo.fetchOrdersPage(
          runDate: event.runDate,
          from: 0,
          to: 9999,
        );

        final firstRows = firstBatch.map(DailyOrderRow.fromMap).toList();

        emit(
          state.copyWith(
            cachedOrders: firstRows,
            allOrders: firstRows,
            loadedCount: firstRows.length,
            isOrdersLoading: false,
          ),
        );

        // LOAD REMAINING DATA
        List<DailyOrderRow> all = List.from(firstRows);

        int offset = 10000;

        const int batchSize = 10000;
        const int concurrent = 8;

        while (true) {
          if (emit.isDone) return;

          final offsets = List.generate(
            concurrent,
            (i) => offset + i * batchSize,
          );

          final results = await Future.wait(
            offsets.map(
              (from) => repo.fetchOrdersPage(
                runDate: event.runDate,
                from: from,
                to: from + batchSize - 1,
              ),
            ),
          );

          bool anyData = false;
          bool lastWasShort = false;

          for (final batch in results) {
            if (batch.isEmpty) {
              lastWasShort = true;
              break;
            }

            anyData = true;

            all.addAll(batch.map(DailyOrderRow.fromMap));

            if (batch.length < batchSize) {
              lastWasShort = true;
              break;
            }
          }

          if (emit.isDone) return;

          emit(
            state.copyWith(
              cachedOrders: all,
              allOrders: all,
              loadedCount: all.length,
              isBackgroundLoading: true,
            ),
          );

          if (!anyData || lastWasShort) {
            break;
          }

          offset += concurrent * batchSize;
        }

        ordersCache[cacheKey] = all;

        if (emit.isDone) return;

        emit(
          state.copyWith(
            cachedOrders: all,
            allOrders: all,
            loadedCount: all.length,
            isBackgroundLoading: false,
            allDataLoaded: true,
          ),
        );
      } catch (e) {
        if (emit.isDone) return;

        emit(
          state.copyWith(isOrdersLoading: false, isBackgroundLoading: false),
        );

        print("LOAD ORDERS ERROR = $e");
      }
    });
    on<SearchInventoryOrders>((event, emit) async {
      final q = event.query.trim();

      // ── CLEAR → restore page 0 from cache ─────────────────────
      if (q.isEmpty) {
        const pageSize = 1000;
        final total = state.cachedOrders.length;
        final pageRows = total == 0
            ? <DailyOrderRow>[]
            : state.cachedOrders.sublist(0, total.clamp(0, pageSize));
        emit(state.copyWith(allOrders: pageRows, currentOrdersPage: 0));
        return;
      }

      // ── LOCAL SEARCH — search everything in cache ──────────────
      final ql = q.toLowerCase();
      final local = state.cachedOrders.where((e) {
        return e.itemName.toLowerCase().contains(ql) ||
            e.itemCode.toLowerCase().contains(ql) ||
            e.branch.toLowerCase().contains(ql) ||
            (e.barcode?.toLowerCase().contains(ql) ?? false);
      }).toList();

      // If we have local results OR all data is loaded → return local
      if (local.isNotEmpty || state.allDataLoaded) {
        emit(state.copyWith(allOrders: local, currentOrdersPage: 0));
        return;
      }

      // ── SERVER FALLBACK — only when cache is still loading ─────
      emit(state.copyWith(isSearching: true));

      try {
        final remote = await repo.searchOrders(runDate: runDate, query: q);
        final rows = remote.map(DailyOrderRow.fromMap).toList();
        emit(
          state.copyWith(
            allOrders: rows,
            currentOrdersPage: 0,
            isSearching: false,
          ),
        );
      } catch (_) {
        emit(state.copyWith(allOrders: local, isSearching: false));
      }
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

      String csvText;
      try {
        csvText = utf8.decode(file.bytes!);
      } catch (_) {
        csvText = latin1.decode(file.bytes!);
      }

      final rows = const CsvToListConverter().convert(csvText);

      if (rows.isEmpty) {
        emit(
          state.copyWith(isImporting: false, importMessage: "CSV is empty ❌"),
        );
        return;
      }

      // ===============================
      // HEADER VALIDATION
      // ===============================
      final header = rows.first.map((e) => e.toString().trim()).toList();

      const expected = [
        "action",
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

      // ===============================
      // FAST FETCH — branches + existing data at the same time
      // ===============================
      emit(state.copyWith(importMessage: "Validating..."));

      final fetchResults = await Future.wait([
        Supabase.instance.client
            .from('branches')
            .select('branch_name')
            .eq('is_active', true),
        Supabase.instance.client
            .from('max_adj')
            .select(
              'branch_name, item_code, item_name, '
              'current_demand_30d, max_adjustment_30d, '
              'adjustment_type, reason, update_date, end_date, added_by',
            ),
      ]);

      final branchesResult = fetchResults[0] as List;
      final existingRaw = fetchResults[1] as List;

      // ===============================
      // BRANCH VALIDATION (memory only — instant)
      // ===============================
      final validBranches = branchesResult
          .map((e) => (e['branch_name'] ?? '').toString().trim().toUpperCase())
          .toSet();

      final invalidBranches = <Map<String, dynamic>>[];

      for (int r = 1; r < rows.length; r++) {
        final row = rows[r];
        if (row.length < 2) continue;
        final branch = (row[1] ?? '').toString().trim();
        if (!validBranches.contains(branch.toUpperCase())) {
          invalidBranches.add({
            'branch_name': branch,
            'error': 'Branch not found',
          });
        }
      }

      if (invalidBranches.isNotEmpty) {
        final exportRows = [
          ['branch_name', 'error'],
        ];
        for (final e in invalidBranches) {
          exportRows.add([e['branch_name'], e['error']]);
        }
        final csv = const ListToCsvConverter().convert(exportRows);
        final bytes = Uint8List.fromList(utf8.encode(csv));
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute("download", "invalid_branches.csv")
          ..click();
        html.Url.revokeObjectUrl(url);

        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage: "${invalidBranches.length} invalid branches found",
          ),
        );
        return;
      }

      // ===============================
      // BUILD EXISTING MAP (existingRaw already in memory — no wait)
      // ===============================
      final Map<String, Map<String, dynamic>> existingMap = {
        for (final e in existingRaw)
          '${e['branch_name']}|${e['item_code']}': Map<String, dynamic>.from(e),
      };

      // ===============================
      // BUILD LISTS
      // ===============================
      final rowsToImport = <Map<String, dynamic>>[];
      final rowsToDelete = <Map<String, dynamic>>[];
      final conflicts = <Map<String, dynamic>>[];
      final errors = <Map<String, dynamic>>[];
      final updatedList = List<Map<String, dynamic>>.from(state.maxAdjustment);
      final total = rows.length - 1;

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        try {
          if (row.length < 9) {
            errors.add({"row": row, "error": "Invalid columns count"});
            continue;
          }

          final action = (row[0] ?? '').toString().trim().toUpperCase();

          if (!['ADD', 'UPDATE', 'DELETE'].contains(action)) {
            errors.add({"row": row, "error": "Invalid action: $action"});
            continue;
          }

          final branch = (row[1] ?? '').toString().trim();
          final itemCode = (row[2] ?? '').toString().trim();
          final key = '$branch|$itemCode';

          if (action == 'DELETE') {
            rowsToDelete.add({'branch_name': branch, 'item_code': itemCode});
            updatedList.removeWhere(
              (e) => e['item_code'] == itemCode && e['branch_name'] == branch,
            );
            continue;
          }

          final current = num.tryParse("${row[4]}") ?? 0;
          final max = num.tryParse("${row[5]}") ?? 0;
          final type = max > current
              ? 'INCREASE'
              : max < current
              ? 'DECREASE'
              : 'EQUAL';

          final data = {
            'branch_name': branch,
            'item_code': itemCode,
            'item_name': row[3]?.toString() ?? '',
            'current_demand_30d': current,
            'max_adjustment_30d': max,
            'adjustment_type': type,
            'reason': row[6]?.toString() ?? '',
            'update_date': _parseDate(row[7]),
            'end_date': _parseDate(row[8]),
            'qty': max,
            'added_by': 'inventory',
          };

          final existing = existingMap[key];

          if (existing != null && !event.forceApply) {
            conflicts.add({
              'branch_name': branch,
              'item_code': itemCode,
              'item_name': data['item_name'],
              'old_current_demand': existing['current_demand_30d'],
              'old_max_adj': existing['max_adjustment_30d'],
              'old_reason': existing['reason'],
              'old_adjustment_type': existing['adjustment_type'],
              'old_update_date': existing['update_date'],
              'old_added_by': existing['added_by'],
              'old_end_date': existing['end_date'],
              'new_current_demand': data['current_demand_30d'],
              'new_max_adj': data['max_adjustment_30d'],
              'new_reason': data['reason'],
              'new_adjustment_type': data['adjustment_type'],
              'new_update_date': data['update_date'],
              'new_added_by': data['added_by'],
              'new_end_date': data['end_date'],
            });
            continue;
          }

          rowsToImport.add(data);

          final index = updatedList.indexWhere(
            (e) => e['item_code'] == itemCode && e['branch_name'] == branch,
          );
          if (index != -1) {
            updatedList[index] = {...updatedList[index], ...data};
          } else {
            updatedList.add(data);
          }
        } catch (e) {
          errors.add({"row": row, "error": e.toString()});
        }

        if (i % 100 == 0) {
          emit(state.copyWith(importProgress: i / total));
        }
      }

      // ===============================
      // EXPORT DUPLICATES
      // ===============================
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

      // ===============================
      // EXPORT ERRORS
      // ===============================
      if (errors.isNotEmpty) {
        await MaxAdjExcelExporter.export(rows: errors, includeHistory: false);
      }

      // ===============================
      // FAST UPLOAD — delete + import at the same time
      // ===============================
      emit(state.copyWith(importMessage: "Uploading..."));

      await Future.wait([
        if (rowsToDelete.isNotEmpty) repo.deleteMaxAdjBulk(rowsToDelete),
        if (rowsToImport.isNotEmpty) repo.importMaxAdjBulk(rowsToImport),
      ]);

      // ===============================
      // FINISH
      // ===============================
      emit(
        state.copyWith(
          isImporting: false,
          importProgress: 1,
          importSuccess: errors.isEmpty,
          importMessage: errors.isEmpty
              ? "Import completed successfully ✅"
              : "Completed with ${errors.length} errors ❌",
          maxAdjustment: updatedList,
          filteredMaxAdjustment: updatedList,
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
          "action",

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

      String csvText;

      try {
        csvText = utf8.decode(file.bytes!);
      } catch (_) {
        csvText = latin1.decode(file.bytes!);
      }

      final rows = const CsvToListConverter().convert(csvText);

      if (rows.isEmpty) {
        emit(state.copyWith(isImporting: false, importMessage: "CSV is empty"));
        return;
      }

      final header = rows.first.map((e) => e.toString().trim()).toList();

      const expected = [
        "action",
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

      /// ==================================
      /// VALIDATE BRANCHES
      /// ==================================

      final branchesResult = await Supabase.instance.client
          .from('branches')
          .select('branch_name')
          .eq('is_active', true);

      final validBranches = branchesResult
          .map((e) => (e['branch_name'] ?? '').toString().trim().toUpperCase())
          .toSet();

      final invalidBranches = <Map<String, dynamic>>[];

      for (int r = 1; r < rows.length; r++) {
        final row = rows[r];

        if (row.length < 2) continue;

        final branch = (row[1] ?? '').toString().trim();

        if (!validBranches.contains(branch.toUpperCase())) {
          invalidBranches.add({
            'branch_name': branch,
            'error': 'Branch not found',
          });
        }
      }

      if (invalidBranches.isNotEmpty) {
        final exportRows = [
          ['branch_name', 'error'],
        ];

        for (final e in invalidBranches) {
          exportRows.add([e['branch_name'], e['error']]);
        }

        final csv = const ListToCsvConverter().convert(exportRows);

        final bytes = Uint8List.fromList(utf8.encode(csv));

        final blob = html.Blob([bytes]);

        final url = html.Url.createObjectUrlFromBlob(blob);

        html.AnchorElement(href: url)
          ..setAttribute("download", "invalid_branches.csv")
          ..click();

        html.Url.revokeObjectUrl(url);

        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage: "${invalidBranches.length} invalid branches found",
          ),
        );

        return;
      }

      /// ==================================
      /// LOAD CURRENT ASSORTMENT
      /// ==================================

      final existingRows = await repo.fetchAssortment();

      final Map<String, Map<String, dynamic>> existingMap = {
        for (final e in existingRows)
          '${e['branch_name']}|${e['item_code']}': e,
      };

      /// ==================================
      /// BUILD LISTS
      /// ==================================

      final rowsToImport = <Map<String, dynamic>>[];

      final rowsToDelete = <Map<String, dynamic>>[];

      final conflicts = <Map<String, dynamic>>[];

      final errors = <Map<String, dynamic>>[];

      final updatedList = List<Map<String, dynamic>>.from(state.assortment);

      final total = rows.length - 1;

      /// ==================================
      /// LOOP
      /// ==================================

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        try {
          if (row.length < 9) {
            errors.add({"row": row, "error": "Invalid columns count"});
            continue;
          }

          final action = (row[0] ?? '').toString().trim().toUpperCase();

          if (!['ADD', 'UPDATE', 'DELETE'].contains(action)) {
            errors.add({"row": row, "error": "Invalid action: $action"});
            continue;
          }

          final branch = (row[1] ?? '').toString().trim();

          final itemCode = (row[2] ?? '').toString().trim();

          final itemName = row[3]?.toString() ?? '';

          final key = '$branch|$itemCode';

          /// ==========================
          /// DELETE
          /// ==========================

          if (action == 'DELETE') {
            rowsToDelete.add({'branch_name': branch, 'item_code': itemCode});

            updatedList.removeWhere(
              (e) => e['item_code'] == itemCode && e['branch_name'] == branch,
            );

            continue;
          }

          final data = {
            'branch_name': branch,
            'item_code': itemCode,
            'item_name': itemName,
            'reason': row[4]?.toString() ?? '',
            'assortment_qty': num.tryParse("${row[5]}") ?? 0,
            'assortment_by': row[6]?.toString() ?? '',
            'assortment_start': _parseDate(row[7]),
            'assortment_end': _parseDate(row[8]),
          };

          /// ==========================
          /// DUPLICATES
          /// ==========================

          final existing = existingMap[key];

          if (existing != null && !event.forceApply) {
            conflicts.add({
              'branch_name': branch,
              'item_code': itemCode,
              'item_name': itemName,

              /// OLD
              'old_qty': existing['assortment_qty'],
              'old_reason': existing['reason'],

              /// NEW
              'new_qty': data['assortment_qty'],
              'new_reason': data['reason'],
            });

            continue;
          }

          rowsToImport.add(data);

          final index = updatedList.indexWhere(
            (e) => e['item_code'] == itemCode && e['branch_name'] == branch,
          );

          if (index != -1) {
            updatedList[index] = {...updatedList[index], ...data};
          } else {
            updatedList.add(data);
          }
        } catch (e) {
          errors.add({"row": row, "error": e.toString()});
        }

        if (i % 100 == 0) {
          emit(state.copyWith(importProgress: i / total));
        }
      }

      /// ==================================
      /// EXPORT DUPLICATES
      /// ==================================

      if (conflicts.isNotEmpty && !event.forceApply) {
        await AssortmentExcelExporter.export(
          rows: conflicts,
          includeHistory: false,
        );

        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage:
                "Found ${conflicts.length} duplicates ⚠️ (file downloaded)",
          ),
        );

        return;
      }

      emit(state.copyWith(importMessage: "Uploading..."));

      /// ==================================
      /// DELETE
      /// ==================================

      if (rowsToDelete.isNotEmpty) {
        await repo.deleteAssortmentBulk(rowsToDelete);
      }

      /// ==================================
      /// IMPORT
      /// ==================================

      if (rowsToImport.isNotEmpty) {
        await repo.importAssortmentBulk(rowsToImport);
      }

      /// ==================================
      /// FINISH
      /// ==================================

      emit(
        state.copyWith(
          isImporting: false,
          importProgress: 1,
          importSuccess: errors.isEmpty,
          importMessage: errors.isEmpty
              ? "Import completed successfully ✅"
              : "Completed with ${errors.length} errors ❌",
          assortment: updatedList,
          filteredAssortment: updatedList,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isImporting: false,
          importSuccess: false,
          importMessage: "Error: $e",
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
        "action",

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
        "action",

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

      String csvText;
      try {
        csvText = utf8.decode(file.bytes!);
      } catch (_) {
        csvText = latin1.decode(file.bytes!);
      }

      final rows = const CsvToListConverter().convert(csvText);

      if (rows.isEmpty) {
        emit(state.copyWith(isImporting: false, importMessage: "CSV is empty"));
        return;
      }

      // ===============================
      // HEADER VALIDATION
      // ===============================
      final header = rows.first.map((e) => e.toString().trim()).toList();

      const expected = [
        "action",
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

      // ===============================
      // VALIDATE BRANCHES
      // ===============================
      final branchesResult = await Supabase.instance.client
          .from('branches')
          .select('branch_name')
          .eq('is_active', true);

      final validBranches = branchesResult
          .map((e) => (e['branch_name'] ?? '').toString().trim().toUpperCase())
          .toSet();

      final invalidBranches = <Map<String, dynamic>>[];

      for (int r = 1; r < rows.length; r++) {
        final row = rows[r];
        if (row.length < 2) continue;
        final branch = (row[1] ?? '').toString().trim();
        if (!validBranches.contains(branch.toUpperCase())) {
          invalidBranches.add({
            'branch_name': branch,
            'error': 'Branch not found',
          });
        }
      }

      if (invalidBranches.isNotEmpty) {
        final exportRows = [
          ['branch_name', 'error'],
        ];
        for (final e in invalidBranches) {
          exportRows.add([e['branch_name'], e['error']]);
        }

        final csv = const ListToCsvConverter().convert(exportRows);
        final bytes = Uint8List.fromList(utf8.encode(csv));
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);

        html.AnchorElement(href: url)
          ..setAttribute("download", "invalid_branches.csv")
          ..click();
        html.Url.revokeObjectUrl(url);

        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage: "${invalidBranches.length} invalid branches found",
          ),
        );
        return;
      }

      // ===============================
      // LOAD EXISTING TMA — only needed columns (faster than SELECT *)
      // ===============================
      final existingRaw = await Supabase.instance.client
          .from('tma')
          .select(
            'branch_name, item_code, qty_per_duration, start_date, end_date',
          );

      final Map<String, Map<String, dynamic>> existingMap = {
        for (final e in existingRaw)
          '${e['branch_name']}|${e['item_code']}': Map<String, dynamic>.from(e),
      };

      // ===============================
      // BUILD LISTS
      // ===============================
      final rowsToImport = <Map<String, dynamic>>[];
      final rowsToDelete = <Map<String, dynamic>>[];
      final conflicts = <Map<String, dynamic>>[];
      final errors = <Map<String, dynamic>>[];
      final updatedList = List<Map<String, dynamic>>.from(state.tma);
      final total = rows.length - 1;

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        try {
          if (row.length < 7) {
            errors.add({"row": row, "error": "Invalid columns count"});
            continue;
          }

          final action = (row[0] ?? '').toString().trim().toUpperCase();

          if (!['ADD', 'UPDATE', 'DELETE'].contains(action)) {
            errors.add({"row": row, "error": "Invalid action: $action"});
            continue;
          }

          final branch = (row[1] ?? '').toString().trim();
          final itemCode = (row[2] ?? '').toString().trim();
          final key = '$branch|$itemCode';

          // ==========================
          // DELETE
          // ==========================
          if (action == 'DELETE') {
            rowsToDelete.add({'branch_name': branch, 'item_code': itemCode});
            updatedList.removeWhere(
              (e) => e['item_code'] == itemCode && e['branch_name'] == branch,
            );
            continue;
          }

          final data = {
            'branch_name': branch,
            'item_code': itemCode,
            'item_name': row[3]?.toString() ?? '',
            'qty_per_duration': num.tryParse("${row[4]}") ?? 0,
            'start_date': _parseDate(row[5]),
            'end_date': _parseDate(row[6]),
          };

          // ==========================
          // DUPLICATES
          // ==========================
          final existing = existingMap[key];

          if (existing != null && !event.forceApply) {
            conflicts.add({
              'branch_name': branch,
              'item_code': itemCode,
              'item_name': data['item_name'],
              'old_qty': existing['qty_per_duration'],
              'old_start': existing['start_date'],
              'old_end': existing['end_date'],
              'new_qty': data['qty_per_duration'],
              'new_start': data['start_date'],
              'new_end': data['end_date'],
            });
            continue;
          }

          rowsToImport.add(data);

          final index = updatedList.indexWhere(
            (e) => e['item_code'] == itemCode && e['branch_name'] == branch,
          );

          if (index != -1) {
            updatedList[index] = {...updatedList[index], ...data};
          } else {
            updatedList.add(data);
          }
        } catch (e) {
          errors.add({"row": row, "error": e.toString()});
        }

        if (i % 100 == 0) {
          emit(state.copyWith(importProgress: i / total));
        }
      }

      // ===============================
      // EXPORT DUPLICATES
      // ===============================
      if (conflicts.isNotEmpty && !event.forceApply) {
        await TmaExcelExporter.export(rows: conflicts, includeHistory: false);

        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage:
                "Found ${conflicts.length} duplicates ⚠️ (file downloaded)",
          ),
        );
        return;
      }

      // ===============================
      // EXPORT ERRORS
      // ===============================
      if (errors.isNotEmpty) {
        await TmaExcelExporter.export(rows: errors, includeHistory: false);
      }

      emit(state.copyWith(importMessage: "Uploading..."));

      // ===============================
      // DELETE
      // ===============================
      if (rowsToDelete.isNotEmpty) {
        await repo.deleteTmaBulk(rowsToDelete);
      }

      // ===============================
      // IMPORT
      // ===============================
      if (rowsToImport.isNotEmpty) {
        await repo.importTmaBulk(rowsToImport);
      }

      // ===============================
      // FINISH
      // ===============================
      emit(
        state.copyWith(
          isImporting: false,
          importProgress: 1,
          importSuccess: errors.isEmpty,
          importMessage: errors.isEmpty
              ? "Import completed successfully ✅"
              : "Completed with ${errors.length} errors ❌",
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

      final csv = await repo.fetchFormularyLogExportCsv();

      final lines = csv.split('\n');

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
        "action",

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
        "action",

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
        final action = (row[0]?.toString() ?? 'ADD').trim().toUpperCase();
        if (!['ADD', 'UPDATE', 'DELETE'].contains(action)) {
          errors.add({"row": row, "error": "Invalid action: $action"});

          continue;
        }
        try {
          final branch = (row[1] ?? '').toString().trim();
          final itemCode = (row[2] ?? '').toString().trim();

          final data = {
            'branch_name': branch,
            'item_code': itemCode,
            'item_name': row[3],
            'revised_branch_formulary': row[4],
            'revised_date': _parseDate(row[5]),
            'reason': row[6],
          };
          if (action == 'DELETE') {
            await repo.deleteFormularyRow(itemCode: itemCode, branch: branch);
            updatedList.removeWhere(
              (e) => e['item_code'] == itemCode && e['branch_name'] == branch,
            );
            continue;
          }

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

  Future<void> _onExportInventoryOrders(
    ExportInventoryOrders event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(
        state.copyWith(
          isExporting: true,
          importProgress: 0.05,
          exportMessage: "Preparing CSV...",
        ),
      );

      /// =========================
      /// UI -> DB COLUMN MAPPING
      /// =========================

      final Map<String, String?> dbColumnMap = {
        'row_no': null,
        'additional_request': null,

        'reason_for_max_adjustment_30d': 'reason',

        'total_sold_qty_cash_last_90': null,
        'total_sold_qty_online_last_90': null,
        'total_sold_qty_insurance_last_90': null,

        'upp_thiqa': null,
        'upp_basic': null,
        'tier': null,
      };

      /// =========================
      /// DB COLUMNS
      /// =========================

      final dbColumns = event.visibleColumns
          .map((e) {
            if (dbColumnMap.containsKey(e)) {
              return dbColumnMap[e];
            }

            return e;
          })
          .whereType<String>()
          .toList();

      /// =========================
      /// HEADERS
      /// =========================

      final headers = event.visibleColumns
          .where((e) {
            final mapped = dbColumnMap[e];

            if (mapped == null && dbColumnMap.containsKey(e)) {
              return false;
            }

            return true;
          })
          .map((e) {
            return (OrdersTable.titles[e] ?? e)
                .replaceAll('\n', ' ')
                .replaceAll(',', ' ');
          })
          .toList();

      /// =========================
      /// BATCH EXPORT
      /// =========================

      const batchSize = 50000;

      int offset = 0;

      final List<String> csvParts = [];

      while (true) {
        emit(
          state.copyWith(
            importProgress: (0.05 + ((offset / 800000) * 0.85)).clamp(0, 0.9),
            exportMessage: "Loading rows $offset...",
          ),
        );

        final csvChunk = await Supabase.instance.client.rpc(
          'export_daily_order_csv',
          params: {
            'p_run_date': event.runDate,
            'p_columns': dbColumns,
            'p_limit': batchSize,
            'p_offset': offset,
          },
        );

        final lines = csvChunk.toString().split('\n');

        if (lines.length <= 1) {
          break;
        }

        /// =========================
        /// FIRST BATCH
        /// =========================

        if (offset == 0) {
          lines[0] = headers.join(',');

          csvParts.add(lines.join('\n'));
        } else {
          csvParts.add(lines.skip(1).join('\n'));
        }

        offset += batchSize;

        await Future.delayed(const Duration(milliseconds: 5));
      }

      /// =========================
      /// GENERATE FINAL CSV
      /// =========================

      emit(
        state.copyWith(
          importProgress: 0.95,
          exportMessage: "Generating file...",
        ),
      );

      final finalCsv = csvParts.join('\n');

      /// =========================
      /// UTF8 BOM FIX
      /// =========================

      final bytes = utf8.encode('\uFEFF$finalCsv');

      emit(
        state.copyWith(importProgress: 0.98, exportMessage: "Downloading..."),
      );

      final blob = html.Blob([
        Uint8List.fromList(bytes),
      ], 'text/csv;charset=utf-8;');

      final url = html.Url.createObjectUrlFromBlob(blob);

      html.AnchorElement(href: url)
        ..setAttribute(
          'download',
          'daily_order_${DateTime.now().millisecondsSinceEpoch}.csv',
        )
        ..click();

      html.Url.revokeObjectUrl(url);

      emit(
        state.copyWith(
          isExporting: false,
          importProgress: 1,
          exportMessage: "Export completed",
        ),
      );
    } catch (e) {
      print(e);

      emit(state.copyWith(isExporting: false, exportMessage: "Export failed"));
    }
  }

  Future<void> _onLoadOrdersPage(
    LoadOrdersPage event,
    Emitter<InventoryState> emit,
  ) async {
    // Pure local slice — zero network calls, instant page flip
    const pageSize = 1000;

    final total = state.cachedOrders.length;
    final page = event.page.clamp(
      0,
      ((total / pageSize).ceil() - 1).clamp(0, 999999),
    );

    final start = page * pageSize;
    final end = (start + pageSize).clamp(0, total);

    final pageRows = total == 0
        ? <DailyOrderRow>[]
        : state.cachedOrders.sublist(start, end);

    emit(
      state.copyWith(
        currentOrdersPage: page,
        hasMorePages: false,
        isOrdersLoading: false,
      ),
    );
  }

  Future<void> _onLoadAdditionalOrderAnalysis(
    LoadAdditionalOrderAnalysis event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      print("START ANALYSIS");

      final data = await repo.fetchAdditionalOrderAnalysis(
        from: event.from,
        to: event.to,
      );

      print(data);

      emit(state.copyWith(additionalAnalysis: data));
    } catch (e) {
      print("ANALYSIS ERROR = $e");
    }
  }
}
