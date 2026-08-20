import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/cache/daily_order_cache_service.dart';
import '../../../core/utils/allocation_excel_exporter.dart';
import '../../../core/utils/assortment_export.dart';
import '../../../core/utils/formulary_export.dart';
import '../../../core/utils/max_adj_export.dart';
import '../../../core/utils/mismatch_export.dart';
import '../../../core/utils/purchase_shortage_excel_exporter.dart';
import '../../../core/utils/tma_export.dart';
import '../../../core/utils/web_notification.dart';
import '../../../domain/entities/additional_request_group.dart';
import '../../../domain/entities/allocation_result_row.dart';
import '../../../domain/entities/allocation_source_row.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../../../domain/entities/inventory_page.dart';
import '../../../domain/entities/mismatch_item.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../orders/bloc/order_bloc/orders_state.dart' as orders_state;
import '../../orders/widgets/orders_table.dart';
import 'inventory_event.dart';
import 'inventory_state.dart';

class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  final InventoryRepository repo;
  late final RealtimeChannel additionalChannel;
  final AudioPlayer _player = AudioPlayer();
  late final RealtimeChannel maxAdjChannel;
  late final RealtimeChannel assortmentChannel;
  late final RealtimeChannel formularyChannel;
  static final Map<String, List<DailyOrderRow>> ordersCache = {};
  String? _ordersLoadingRunDate;
  int _ordersLoadToken = 0;
  int _formularyLoadToken = 0;
  int _maxAdjLoadToken = 0;
  int _mismatchLoadToken = 0;
  int _assortmentLoadToken = 0;
  int _tmaLoadToken = 0;
  Uint8List? _pendingImportBytes;
  String? _pendingImportSource;
  List<Map<String, dynamic>> _pendingImportDuplicates = const [];
  String runDate = '';
  RealtimeChannel? mismatchChannel;
  final Set<String> _notifiedAdditionalRequestGroups = <String>{};
  InventoryBloc(this.repo) : super(InventoryState.initial()) {
    on<LoadInventoryDashboard>(_onLoad);
    on<SelectBranch>(_onSelectBranch);
    on<SubmitBranchFromInventory>(_onSubmitBranchFromInventory);
    on<DeleteBranchSubmissionFromInventory>(
      _onDeleteBranchSubmissionFromInventory,
    );
    on<LoadBranchAnalytics>(_onBranchAnalytics);
    on<ApproveInventoryRequest>(_onApproveInventory);
    on<LoadBranchAdditionalStats>(_onBranchAdditionalStats);
    on<AdditionalRequestRealtimeUpdated>(_onAdditionalRealtimeUpdate);
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
    on<LoadAdditionalOrderHistory>(_onLoadAdditionalOrderHistory);
    on<LoadOrderEditAnalysis>(_onLoadOrderEditAnalysis);
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
    on<LoadRequestEffectiveness>(_onLoadRequestEffectiveness);
    on<LoadOrderEditSalesPerformance>(_onLoadOrderEditSalesPerformance);
    on<ImportFormularyExcel>(_onImportFormulary);
    on<ResolveImportDuplicates>(_onResolveImportDuplicates);
    on<LoadOrdersPage>(_onLoadOrdersPage);
    on<ImportTmaExcel>(_onImportTma);
    on<AdditionalRequestInsertedRealtime>(_onAdditionalInsertedRealtime);
    on<AdditionalRequestDeletedRealtime>(_onAdditionalDeletedRealtime);
    on<LoadAllocationFilters>(_onLoadAllocationFilters);
    on<RunAllocation>(_onRunAllocation);
    on<ExportAllocationResults>(_onExportAllocationResults);
    on<ExportAllocationShortage>(_onExportAllocationShortage);
    on<SendAllocationToBranches>(_onSendAllocationToBranches);
    on<LoadSentBranchAllocations>(_onLoadSentBranchAllocations);
    on<ImportAllocationFile>(_onImportAllocationFile);
    on<AllocationProgressUpdated>((event, emit) {
      emit(state.copyWith(allocationLoadedRows: event.loadedRows));
    });
    on<LoadPurchaseShortage>(_onLoadPurchaseShortage);
    on<ExportPurchaseShortage>(_onExportPurchaseShortage);
    on<LoadBranchSettings>(_onLoadBranchSettings);
    on<SaveBranchSetting>(_onSaveBranchSetting);
    on<ExportTmaTemplate>(_onExportTmaTemplate);
    on<ExportTmaCurrent>(_onExportTmaCurrent);
    on<ExportTmaWithHistory>(_onExportTmaHistory);
    on<ExportMaxAdjTemplate>(_onExportTemplate);
    on<LoadFormulary>((event, emit) async {
      const pageSize = 10000;
      final requestToken = ++_formularyLoadToken;

      if (!event.silent) {
        emit(state.copyWith(isFormularyLoading: true, isLoading: true));
      }

      try {
        final from = event.page * pageSize;
        final to = from + pageSize - 1;

        final result = await repo.fetchFormularyPage(
          from: from,
          to: to,
          query: event.query,
        );

        if (requestToken != _formularyLoadToken) return;

        final pageData = List<Map<String, dynamic>>.from(result['rows'] ?? []);
        final totalRows = (result['total'] ?? 0) as int;
        final totalPages = totalRows == 0 ? 1 : (totalRows / pageSize).ceil();
        final hasMore = event.page < totalPages - 1;

        emit(
          state.copyWith(
            formulary: pageData,
            filteredFormulary: pageData,
            formularySearch: event.query,
            formularyTotalRows: totalRows,
            formularyPage: event.page,
            formularyPageSize: pageSize,
            formularyHasMore: hasMore,
            isFormularyLoading: false,
            isLoading: false,
          ),
        );
      } catch (e) {
        if (requestToken != _formularyLoadToken) return;
        emit(state.copyWith(isFormularyLoading: false, isLoading: false));
      }
    });

    on<SearchFormulary>((event, emit) async {
      add(LoadFormulary(page: 0, query: event.query));
    });
    on<StartFormularyRealtime>((event, emit) {
      formularyChannel = Supabase.instance.client
          .channel('formulary_live')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'branch_formulary',
            callback: (payload) {
              if (!state.isImporting) {
                add(
                  LoadFormulary(
                    page: state.formularyPage,
                    query: state.formularySearch,
                    silent: true,
                  ),
                );
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
      _pendingImportBytes = null;
      _pendingImportSource = null;
      _pendingImportDuplicates = const [];
      emit(
        state.copyWith(
          isImporting: false,
          importProgress: 0,
          importMessage: null,
          importSuccess: false,
          importDuplicateCount: 0,
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
      final requestToken = ++_assortmentLoadToken;

      if (!event.silent) {
        emit(state.copyWith(isLoading: true));
      }

      try {
        final data = await repo.fetchAssortment();
        if (requestToken != _assortmentLoadToken) return;

        final filtered = _filterAssortmentRows(data, state.assortmentSearch);

        emit(
          state.copyWith(
            assortment: data,
            filteredAssortment: filtered,
            isLoading: false,
          ),
        );
      } catch (e) {
        if (requestToken != _assortmentLoadToken) return;
        emit(state.copyWith(isLoading: false));
        print("LoadAssortment Error: $e");
      }
    });
    on<SearchAssortment>((event, emit) {
      final filtered = _filterAssortmentRows(state.assortment, event.query);

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
      // Avoid building thousands of web grid cells at once.
      const pageSize = 500;
      final requestToken = ++_maxAdjLoadToken;

      if (!event.silent) {
        emit(
          state.copyWith(
            isLoading: true,
            isMaxAdjLoading: true,
            importMessage: state.importMessage,
          ),
        );
      } else {
        emit(state.copyWith(isMaxAdjLoading: true));
      }

      try {
        final page = event.page < 0 ? 0 : event.page;
        final from = page * pageSize;
        final to = from + pageSize - 1;

        final result = await repo.fetchMaxAdjustmentPage(
          from: from,
          to: to,
          query: event.query,
        );

        if (requestToken != _maxAdjLoadToken) return;

        final rows = List<Map<String, dynamic>>.from(result['rows'] ?? []);
        final total = (result['total'] ?? 0) as int;
        final totalPages = total == 0 ? 1 : (total / pageSize).ceil();

        emit(
          state.copyWith(
            maxAdjustment: rows,
            filteredMaxAdjustment: rows,
            maxAdjSearch: event.query,
            maxAdjPage: page,
            maxAdjPageSize: pageSize,
            maxAdjTotalRows: total,
            maxAdjHasMore: page < totalPages - 1,
            isLoading: false,
            isMaxAdjLoading: false,
            importMessage: state.importMessage,
          ),
        );
      } catch (e) {
        if (requestToken != _maxAdjLoadToken) return;
        emit(state.copyWith(isLoading: false, isMaxAdjLoading: false));
      }
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
                add(
                  LoadMaxAdjustment(
                    page: state.maxAdjPage,
                    query: state.maxAdjSearch,
                    silent: true,
                  ),
                );
              }
            },
          )
          .subscribe();
    });
    on<LoadTma>((event, emit) async {
      final requestToken = ++_tmaLoadToken;

      if (!event.silent) {
        emit(state.copyWith(isLoading: true));
      }

      try {
        final data = await repo.fetchTma();
        if (requestToken != _tmaLoadToken) return;

        final filtered = _filterTmaRows(data, state.tmaSearch);

        emit(
          state.copyWith(tma: data, filteredTma: filtered, isLoading: false),
        );
      } catch (e) {
        if (requestToken != _tmaLoadToken) return;
        emit(state.copyWith(isLoading: false));
        print("LoadTma Error: $e");
      }
    });
    on<SearchTma>((event, emit) {
      final filtered = _filterTmaRows(state.tma, event.query);

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
      add(LoadMaxAdjustment(page: 0, query: event.query));
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
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'additional_requests',
            callback: (payload) async {
              final row = payload.newRecord;

              add(AdditionalRequestInsertedRealtime(row));

              if (!_isPendingAdditionalStatus(
                (row['status'] ?? '').toString(),
              )) {
                return;
              }

              final groupKey = _additionalRealtimeNotificationKey(row);
              if (!_notifiedAdditionalRequestGroups.add(groupKey)) {
                return;
              }

              final branch = (row['branch_name'] ?? '').toString();

              try {
                await _player.play(AssetSource('sounds/notification.mp3'));
              } catch (e) {
                print(e);
              }

              WebNotification.show(
                title: 'New Additional Order',
                body: '$branch\nAdditional request group received.',
              );
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'additional_requests',
            callback: (payload) {
              add(AdditionalRequestRealtimeUpdated(payload.newRecord));
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'additional_requests',
            callback: (payload) {
              final oldId = payload.oldRecord['id']?.toString();
              if (oldId == null || oldId.isEmpty) return;
              add(AdditionalRequestDeletedRealtime(oldId));
            },
          )
          .subscribe();
    });
    on<LoadBranchAllChanges>((event, emit) async {
      final data = await repo.fetchBranchAllChanges(event.branch);
      emit(state.copyWith(allChanges: data));
    });
    on<InventorySetColumnVisible>((event, emit) {
      if ((event.columnKey == 'item_code' || event.columnKey == 'item_name') &&
          !event.visible) {
        return;
      }

      final updated = state.visibleColumns.isEmpty
          ? List<String>.from(orders_state.OrdersState.defaultVisibleInTable)
          : List<String>.from(state.visibleColumns);

      if (event.visible) {
        if (!updated.contains(event.columnKey)) {
          updated.add(event.columnKey);
        }
      } else {
        updated.remove(event.columnKey);
      }

      emit(state.copyWith(visibleColumns: updated));
    });
    on<InventoryReorderColumns>((event, emit) {
      final list = state.columnOrder.isEmpty
          ? List<String>.from(orders_state.OrdersState.defaultColumnOrder)
          : List<String>.from(state.columnOrder);

      final filtered = list.where((e) => e != 'additional_request').toList();

      final oldIndex = event.oldIndex.clamp(0, filtered.length - 1);
      final newIndex = event.newIndex.clamp(0, filtered.length);

      final item = filtered.removeAt(oldIndex);
      filtered.insert(newIndex, item);

      if (list.contains('additional_request')) {
        filtered.add('additional_request');
      }

      emit(state.copyWith(columnOrder: filtered));
    });
    on<InventoryResetColumns>((event, emit) {
      emit(
        state.copyWith(
          visibleColumns: orders_state.OrdersState.defaultVisibleInTable
              .toList(),
          columnOrder: orders_state.OrdersState.defaultColumnOrder.toList(),
        ),
      );
    });
    on<LoadInventoryOrders>((event, emit) async {
      final cacheKey = event.runDate;

      if (_ordersLoadingRunDate == cacheKey) {
        final rows = state.cachedOrders;
        emit(
          state.copyWith(
            allOrders: rows.take(1000).toList(),
            loadedCount: rows.length,
            isOrdersLoading: false,
            isBackgroundLoading: true,
          ),
        );
        return;
      }

      emit(state.copyWith(isOrdersLoading: true));

      // CACHE HIT
      if (ordersCache.containsKey(cacheKey)) {
        const pageSize = 1000;
        final rows = ordersCache[cacheKey]!;
        emit(
          state.copyWith(
            cachedOrders: rows,
            allOrders: rows.take(pageSize).toList(),
            loadedCount: rows.length,
            currentOrdersPage: 0,
            hasMorePages: false,
            isOrdersLoading: false,
            allDataLoaded: true,
          ),
        );
        return;
      }

      try {
        final diskRows = await DailyOrderCacheService.instance.readRows(
          event.runDate,
        );

        if (diskRows != null && diskRows.isNotEmpty) {
          const pageSize = 1000;
          ordersCache[cacheKey] = diskRows;

          emit(
            state.copyWith(
              cachedOrders: diskRows,
              allOrders: diskRows.take(pageSize).toList(),
              loadedCount: diskRows.length,
              currentOrdersPage: 0,
              hasMorePages: false,
              isOrdersLoading: false,
              isBackgroundLoading: false,
              allDataLoaded: true,
            ),
          );
          return;
        }

        const int batchSize = 10000;
        const int concurrent = 3;
        _ordersLoadingRunDate = cacheKey;
        final loadToken = ++_ordersLoadToken;

        // FIRST BATCH
        final firstBatch = await _fetchOrdersPageSafe(
          runDate: event.runDate,
          from: 0,
          to: batchSize - 1,
        );
        if (!_isCurrentOrdersLoad(cacheKey, loadToken) || emit.isDone) return;

        final firstRows = firstBatch.map(DailyOrderRow.fromMap).toList();
        await DailyOrderCacheService.instance.startWrite(event.runDate);
        if (!_isCurrentOrdersLoad(cacheKey, loadToken) || emit.isDone) return;
        await DailyOrderCacheService.instance.appendBatch(
          event.runDate,
          firstBatch,
        );
        if (!_isCurrentOrdersLoad(cacheKey, loadToken) || emit.isDone) return;

        emit(
          state.copyWith(
            cachedOrders: firstRows,
            allOrders: firstRows.take(1000).toList(),
            loadedCount: firstRows.length,
            isOrdersLoading: false,
            isBackgroundLoading: firstRows.length >= batchSize,
          ),
        );

        // LOAD REMAINING DATA
        List<DailyOrderRow> all = List.from(firstRows);

        int offset = batchSize;

        while (true) {
          if (!_isCurrentOrdersLoad(cacheKey, loadToken) || emit.isDone) {
            return;
          }

          final offsets = List.generate(
            concurrent,
            (i) => offset + i * batchSize,
          );

          final results = await Future.wait(
            offsets.map(
              (from) => _fetchOrdersPageSafe(
                runDate: event.runDate,
                from: from,
                to: from + batchSize - 1,
              ),
            ),
          );
          if (!_isCurrentOrdersLoad(cacheKey, loadToken) || emit.isDone) {
            return;
          }

          bool anyData = false;
          bool lastWasShort = false;

          for (final batch in results) {
            if (batch.isEmpty) {
              lastWasShort = true;
              break;
            }

            anyData = true;

            all.addAll(batch.map(DailyOrderRow.fromMap));
            await DailyOrderCacheService.instance.appendBatch(
              event.runDate,
              batch,
            );
            if (!_isCurrentOrdersLoad(cacheKey, loadToken) || emit.isDone) {
              return;
            }

            if (batch.length < batchSize) {
              lastWasShort = true;
              break;
            }
          }

          if (!_isCurrentOrdersLoad(cacheKey, loadToken) || emit.isDone) {
            return;
          }

          emit(
            state.copyWith(
              cachedOrders: all,
              allOrders: all.take(1000).toList(),
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
        await DailyOrderCacheService.instance.markComplete(event.runDate);

        if (!_isCurrentOrdersLoad(cacheKey, loadToken) || emit.isDone) return;

        emit(
          state.copyWith(
            cachedOrders: all,
            allOrders: all.take(1000).toList(),
            loadedCount: all.length,
            isBackgroundLoading: false,
            allDataLoaded: true,
          ),
        );
        if (_isCurrentOrdersLoad(cacheKey, loadToken)) {
          _ordersLoadingRunDate = null;
        }
      } catch (e) {
        if (emit.isDone) return;
        if (_ordersLoadingRunDate == cacheKey) {
          _ordersLoadingRunDate = null;
        }

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
              if (state.currentPage != InventoryPageType.mismatch) return;
              add(LoadMismatch());
            },
          )
          .subscribe();

      emit(state.copyWith(isMismatchRealtimeStarted: true));
    });
    WebNotification.init();
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
      final branches = await repo.fetchBranchesToday(runDate);
      final branchSettings = await repo.fetchBranchSettings();
      final submitStartHours = {
        for (final branch in branchSettings)
          branch.branchName: branch.submitStartHour,
      };
      final submitEndHours = {
        for (final branch in branchSettings)
          branch.branchName: branch.submitEndHour,
      };

      final submitted = await repo.fetchSubmittedBranches(runDate);
      final submittedTimes = await repo.fetchSubmittedBranchTimes(runDate);

      final additional = await repo.fetchAdditionalRequests();
      final counters = _additionalCounters(additional);

      final editsCount = await repo.fetchBranchEditsCount(runDate);

      /// NEW
      final additionalBranchToday = await repo.fetchAdditionalTodayByBranch(
        runDate,
      );

      emit(
        state.copyWith(
          branches: branches,
          submittedBranches: submitted,
          submittedBranchTimes: submittedTimes,
          submitStartHours: submitStartHours,
          submitEndHours: submitEndHours,
          additionalRequests: additional,
          editsCount: editsCount,
          additionalTodayBranchCount: additionalBranchToday,
          submittedCount: submitted.length,
          additionalCount: additional.length,
          additionalPendingCount: counters.pending,
          additionalSentToStoreCount: counters.sentToStore,
          additionalTodayCount: counters.today,
          additionalMonthCount: counters.rejected,
          isLoading: false,
          isDashboardLoaded: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, isDashboardLoaded: true));

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

  Future<void> _onSubmitBranchFromInventory(
    SubmitBranchFromInventory event,
    Emitter<InventoryState> emit,
  ) async {
    final branch = event.branch.trim();
    if (branch.isEmpty) return;

    final alreadySubmitted = state.submittedBranches.any(
      (e) => _normalizeBranch(e) == _normalizeBranch(branch),
    );
    if (alreadySubmitted) return;

    emit(
      state.copyWith(
        isBulkLoading: true,
        bulkMessage: 'Submitting $branch...',
        bulkSuccess: null,
      ),
    );

    try {
      await repo.submitBranchOrder(runDate: runDate, branch: branch);

      final submitted = [...state.submittedBranches, branch];
      final submittedTimes = Map<String, DateTime>.from(
        state.submittedBranchTimes,
      )..[branch] = DateTime.now();

      emit(
        state.copyWith(
          submittedBranches: submitted,
          submittedBranchTimes: submittedTimes,
          submittedCount: submitted.length,
          isBulkLoading: false,
          bulkMessage: '$branch submitted successfully',
          bulkSuccess: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isBulkLoading: false,
          bulkMessage: 'Submit failed: $e',
          bulkSuccess: false,
        ),
      );
    }
  }

  Future<void> _onDeleteBranchSubmissionFromInventory(
    DeleteBranchSubmissionFromInventory event,
    Emitter<InventoryState> emit,
  ) async {
    final branch = event.branch.trim();
    if (branch.isEmpty) return;

    emit(
      state.copyWith(
        isBulkLoading: true,
        bulkMessage: 'Removing submit for $branch...',
        bulkSuccess: null,
      ),
    );

    try {
      await repo.deleteBranchSubmission(runDate: runDate, branch: branch);

      final branchKey = _normalizeBranch(branch);
      final submitted = state.submittedBranches
          .where((e) => _normalizeBranch(e) != branchKey)
          .toList();

      final submittedTimes = Map<String, DateTime>.from(
        state.submittedBranchTimes,
      )..removeWhere((key, _) => _normalizeBranch(key) == branchKey);

      emit(
        state.copyWith(
          submittedBranches: submitted,
          submittedBranchTimes: submittedTimes,
          submittedCount: submitted.length,
          isBulkLoading: false,
          bulkMessage: '$branch submit removed successfully',
          bulkSuccess: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isBulkLoading: false,
          bulkMessage: 'Remove submit failed for $branch: $e',
          bulkSuccess: false,
        ),
      );
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
      await repo.approveInventory(
        id: event.requestId,
        qty: event.qty,
        note: event.note,
      );

      /// reload dashboard silently
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
    final requestToken = ++_mismatchLoadToken;

    try {
      final results = await Future.wait<Object>([
        repo.fetchMismatch(),
        repo.fetchMismatchToday(),
        repo.fetchMismatchMonth(),
        repo.fetchMismatchStats(state.mismatchBranch),
      ]);

      if (requestToken != _mismatchLoadToken) return;

      final data = results[0] as List<MismatchItem>;
      final today = results[1] as int;
      final month = results[2] as int;
      final stats = results[3] as Map<String, dynamic>;
      final filtered = _applyMismatchFilters(
        list: data,
        search: state.mismatchSearch,
        branch: state.mismatchBranch,
      );

      emit(
        state.copyWith(
          mismatch: data,
          filteredMismatch: filtered,
          mismatchTodayCount: today,
          mismatchMonthCount: month,
          mismatchTotalCount: stats['total'] ?? 0,
          mismatchDiffSum: stats['diff_sum'] ?? 0,
        ),
      );
    } catch (e) {
      print("LoadMismatch Error: $e");
    }
  }

  List<Map<String, dynamic>> _filterAssortmentRows(
    List<Map<String, dynamic>> list,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;

    return list.where((e) {
      return (e['item_name'] ?? '').toString().toLowerCase().contains(q) ||
          (e['item_code'] ?? '').toString().toLowerCase().contains(q) ||
          (e['branch_name'] ?? '').toString().toLowerCase().contains(q) ||
          (e['assortment_by'] ?? '').toString().toLowerCase().contains(q) ||
          (e['reason'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> _filterTmaRows(
    List<Map<String, dynamic>> list,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;

    return list.where((e) {
      return (e['item_name'] ?? '').toString().toLowerCase().contains(q) ||
          (e['item_code'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
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
    final channel = mismatchChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
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
      final counters = _additionalCounters(additional);

      emit(
        state.copyWith(
          additionalRequests: additional,
          additionalCount: additional.length,
          additionalPendingCount: counters.pending,
          additionalSentToStoreCount: counters.sentToStore,
          additionalTodayCount: counters.today,
          additionalMonthCount: counters.rejected,
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
      final counters = _additionalCounters(additional);

      emit(
        state.copyWith(
          additionalRequests: additional,
          additionalCount: additional.length,
          additionalPendingCount: counters.pending,
          additionalSentToStoreCount: counters.sentToStore,
          additionalTodayCount: counters.today,
          additionalMonthCount: counters.rejected,
          isBulkLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isBulkLoading: false));
      print("Store Approve Error: $e");
    }
  }

  Future<void> _onLoadAllocationFilters(
    LoadAllocationFilters event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(
        state.copyWith(isAllocationFiltersLoading: true, allocationError: ''),
      );

      final branches = await repo.fetchAllocationBranches();
      final categories = await repo.fetchAllocationCategories(event.runDate);
      final itemStatuses = await repo.fetchAllocationItemStatuses(
        event.runDate,
      );
      final stockCoverOptions = await repo.fetchAllocationStockCoverOptions(
        event.runDate,
      );

      emit(
        state.copyWith(
          allocationBranches: branches,
          allocationCategories: categories,
          allocationItemStatuses: itemStatuses,
          allocationStockCoverOptions: stockCoverOptions,
          isAllocationFiltersLoading: false,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          allocationError: e.toString(),
          isAllocationFiltersLoading: false,
        ),
      );
    }
  }

  Future<void> _onRunAllocation(
    RunAllocation event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(
        state.copyWith(
          isAllocationLoading: true,
          allocationLoadedRows: 0,
          allocationError: '',
          allocationResults: [],
          allocationSourceRows: [],
        ),
      );

      final shouldUseLocalAllocation =
          event.donorStockCovers.isNotEmpty ||
          event.receiverStockCovers.isNotEmpty ||
          event.minimumDemandFor30Days != null;

      final sourceDonorBranches =
          event.donorBranches.isEmpty || event.receiverBranches.isEmpty
          ? <String>[]
          : event.donorBranches;
      final sourceReceiverBranches =
          event.donorBranches.isEmpty || event.receiverBranches.isEmpty
          ? <String>[]
          : event.receiverBranches;

      final sourceRows = await repo.fetchAllocationSourceRows(
        runDate: event.runDate,
        donorBranches: sourceDonorBranches,
        receiverBranches: sourceReceiverBranches,
        categories: event.categories,
        itemStatuses: event.itemStatuses,
      );

      final results = shouldUseLocalAllocation
          ? _buildFilteredAllocationResults(
              sourceRows: sourceRows,
              donorBranches: event.donorBranches,
              receiverBranches: event.receiverBranches,
              priorityBranches: event.priorityBranches,
              donorStockCovers: event.donorStockCovers,
              receiverStockCovers: event.receiverStockCovers,
              minimumDemandFor30Days: event.minimumDemandFor30Days,
            )
          : await repo.fetchAllocationResults(
              runDate: event.runDate,
              donorBranches: event.donorBranches,
              receiverBranches: event.receiverBranches,
              priorityBranches: event.priorityBranches,
              categories: event.categories,
              itemStatuses: event.itemStatuses,
            );

      final shortageSourceRows = sourceRows.where((row) {
        return _allocationBranchAllowed(event.receiverBranches, row.branch) &&
            _allocationReceiverCoverAllowed(
              event.receiverStockCovers,
              row.stockCoverText,
            ) &&
            _allocationDemandAllowed(
              event.minimumDemandFor30Days,
              row.demandFor30Days,
            ) &&
            row.itemPurchaseType.trim() == '1#NORMAL PURCHASE';
      }).toList();

      emit(
        state.copyWith(
          allocationResults: results,
          allocationSourceRows: shortageSourceRows,
          isAllocationLoading: false,
          allocationLoadedRows: results.length,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isAllocationLoading: false,
          allocationError: e.toString(),
        ),
      );
    }
  }

  List<AllocationResultRow> _buildFilteredAllocationResults({
    required List<AllocationSourceRow> sourceRows,
    required List<String> donorBranches,
    required List<String> receiverBranches,
    required List<String> priorityBranches,
    required List<String> donorStockCovers,
    required List<String> receiverStockCovers,
    required int? minimumDemandFor30Days,
  }) {
    final rowsByItem = <String, List<AllocationSourceRow>>{};
    for (final row in sourceRows) {
      if (row.itemCode.trim().isEmpty) continue;
      rowsByItem.putIfAbsent(row.itemCode, () => []).add(row);
    }

    final priority = priorityBranches.map(_allocationKey).toSet();
    final output = <AllocationResultRow>[];

    for (final itemRows in rowsByItem.values) {
      final donors =
          itemRows.where((row) {
            return row.extraQtyMoreThanMonth > 0 &&
                _allocationBranchAllowed(donorBranches, row.branch) &&
                _allocationDonorCoverAllowed(
                  donorStockCovers,
                  row.stockCoverText,
                );
          }).toList()..sort((a, b) {
            final extraCompare = b.extraQtyMoreThanMonth.compareTo(
              a.extraQtyMoreThanMonth,
            );
            if (extraCompare != 0) return extraCompare;
            return a.branch.toLowerCase().compareTo(b.branch.toLowerCase());
          });

      final receivers =
          itemRows.where((row) {
            return row.shortage > 0 &&
                _allocationBranchAllowed(receiverBranches, row.branch) &&
                _allocationReceiverCoverAllowed(
                  receiverStockCovers,
                  row.stockCoverText,
                ) &&
                _allocationDemandAllowed(
                  minimumDemandFor30Days,
                  row.demandFor30Days,
                );
          }).toList()..sort((a, b) {
            final aPriority = priority.contains(_allocationKey(a.branch));
            final bPriority = priority.contains(_allocationKey(b.branch));
            if (aPriority != bPriority) return aPriority ? -1 : 1;

            final shortageCompare = b.shortage.compareTo(a.shortage);
            if (shortageCompare != 0) return shortageCompare;
            return a.branch.toLowerCase().compareTo(b.branch.toLowerCase());
          });

      final donorRemaining = {
        for (final donor in donors) donor.branch: donor.extraQtyMoreThanMonth,
      };

      for (final receiver in receivers) {
        var need = receiver.shortage;
        if (need <= 0) continue;

        for (final donor in donors) {
          if (_allocationKey(donor.branch) == _allocationKey(receiver.branch)) {
            continue;
          }

          final available = donorRemaining[donor.branch] ?? 0;
          if (available <= 0) continue;

          final qty = available < need ? available : need;
          if (qty <= 0) continue;

          output.add(
            AllocationResultRow(
              fromBranch: donor.branch,
              itemCode: receiver.itemCode,
              itemName: receiver.itemName,
              qty: qty,
              toBranch: receiver.branch,
              category: receiver.category,
            ),
          );

          donorRemaining[donor.branch] = available - qty;
          need -= qty;
          if (need <= 0) break;
        }
      }
    }

    return output;
  }

  bool _allocationBranchAllowed(List<String> selectedBranches, String branch) {
    const noSelection = '__NO_ALLOCATION_SELECTION__';
    if (selectedBranches.contains(noSelection)) return false;
    if (selectedBranches.isEmpty) return true;
    return selectedBranches
        .map(_allocationKey)
        .contains(_allocationKey(branch));
  }

  bool _allocationDonorCoverAllowed(List<String> selectedCovers, String cover) {
    if (selectedCovers.isEmpty) return true;
    if (_allocationKey(cover) == 'no demand') return false;
    final coverDays = _allocationStockCoverDays(cover);
    var minimumDays = _allocationStockCoverDays(selectedCovers.first);
    for (final selected in selectedCovers.skip(1)) {
      final days = _allocationStockCoverDays(selected);
      if (days < minimumDays) minimumDays = days;
    }
    return coverDays >= minimumDays;
  }

  bool _allocationReceiverCoverAllowed(
    List<String> selectedCovers,
    String cover,
  ) {
    if (selectedCovers.isEmpty) return true;
    if (_allocationKey(cover) == 'no demand') return false;
    final coverDays = _allocationStockCoverDays(cover);
    var maximumDays = _allocationStockCoverDays(selectedCovers.first);
    for (final selected in selectedCovers.skip(1)) {
      final days = _allocationStockCoverDays(selected);
      if (days > maximumDays) maximumDays = days;
    }
    return coverDays <= maximumDays;
  }

  num _allocationStockCoverDays(String label) {
    final text = label.trim().toLowerCase();
    final match = RegExp(r'\d+(\.\d+)?').firstMatch(text);
    final value = num.tryParse(match?.group(0) ?? '') ?? 0;

    if (text.contains('no stock')) return 0;
    if (text.contains('less than')) return value == 0 ? .5 : value;
    if (text.contains('day')) return value;
    if (text.contains('week')) return value * 7;
    if (text.contains('month')) return value * 30;
    if (text.contains('year')) return value * 365;
    return value;
  }

  bool _allocationDemandAllowed(int? minimumDemand, num demand) {
    if (minimumDemand == null) return true;
    return demand >= minimumDemand;
  }

  String _allocationKey(String value) => value.trim().toLowerCase();

  Future<void> _onExportAllocationResults(
    ExportAllocationResults event,
    Emitter<InventoryState> emit,
  ) async {
    if (state.allocationResults.isEmpty) return;
    await AllocationExcelExporter.export(state.allocationResults);
  }

  Future<void> _onExportAllocationShortage(
    ExportAllocationShortage event,
    Emitter<InventoryState> emit,
  ) async {
    if (state.allocationSourceRows.isEmpty) return;

    final rows = _buildAllocationShortageRows(
      sourceRows: state.allocationSourceRows,
      allocatedRows: state.allocationResults,
    );

    if (rows.isEmpty) {
      emit(
        state.copyWith(
          allocationError:
              'No remaining shortage. Allocation covered all selected shortage.',
        ),
      );
      return;
    }

    await AllocationExcelExporter.exportShortage(rows);
  }

  Future<void> _onSendAllocationToBranches(
    SendAllocationToBranches event,
    Emitter<InventoryState> emit,
  ) async {
    if (state.allocationResults.isEmpty) return;

    try {
      emit(
        state.copyWith(
          isAllocationSending: true,
          allocationError: '',
          allocationMessage: '',
        ),
      );

      await repo.sendBranchAllocationTasks(
        runDate: event.runDate,
        batchTitle: event.batchTitle,
        expiresAt: event.expiresAt,
        rows: state.allocationResults,
      );

      final sent = await repo.fetchSentBranchAllocationTasks(
        runDate: event.runDate,
      );

      emit(
        state.copyWith(
          isAllocationSending: false,
          sentBranchAllocations: sent,
          allocationMessage:
              'Allocation sent to branches successfully (${state.allocationResults.length} transfers).',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isAllocationSending: false,
          allocationError: e.toString(),
        ),
      );
    }
  }

  Future<void> _onLoadSentBranchAllocations(
    LoadSentBranchAllocations event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final sent = await repo.fetchSentBranchAllocationTasks(
        runDate: event.runDate,
      );
      emit(state.copyWith(sentBranchAllocations: sent));
    } catch (_) {
      // Keep the allocation page usable even if the sent-history table is not
      // available yet.
    }
  }

  List<AllocationShortageExportRow> _buildAllocationShortageRows({
    required List<AllocationSourceRow> sourceRows,
    required List<AllocationResultRow> allocatedRows,
  }) {
    String key(String branch, String itemCode) {
      return '${_allocationBranchKey(branch)}|${itemCode.trim().toLowerCase()}';
    }

    final allocatedByReceiver = <String, num>{};
    for (final row in allocatedRows) {
      final mapKey = key(row.toBranch, row.itemCode);
      allocatedByReceiver[mapKey] =
          (allocatedByReceiver[mapKey] ?? 0) + row.qty;
    }

    final shortageByItem = <String, AllocationShortageExportRow>{};
    for (final row in sourceRows) {
      if (row.itemPurchaseType.trim() != '1#NORMAL PURCHASE') continue;

      final originalShortage = row.shortage;
      if (originalShortage <= 0) continue;

      final remaining =
          originalShortage -
          (allocatedByReceiver[key(row.branch, row.itemCode)] ?? 0);
      if (remaining <= 0) continue;

      final mapKey = key(row.branch, row.itemCode);
      shortageByItem[mapKey] = AllocationShortageExportRow(
        branch: row.branch,
        itemCode: row.itemCode,
        itemName: row.itemName,
        shortageQty: remaining,
      );
    }

    final rows = shortageByItem.values.toList()
      ..sort((a, b) {
        final branchCompare = a.branch.toLowerCase().compareTo(
          b.branch.toLowerCase(),
        );
        if (branchCompare != 0) return branchCompare;
        return a.itemCode.compareTo(b.itemCode);
      });

    return rows;
  }

  Future<void> _onLoadPurchaseShortage(
    LoadPurchaseShortage event,
    Emitter<InventoryState> emit,
  ) async {
    emit(
      state.copyWith(
        isPurchaseShortageLoading: true,
        purchaseShortageError: '',
      ),
    );

    try {
      final rows = await repo.fetchPurchaseShortage(runDate: event.runDate);
      emit(
        state.copyWith(
          purchaseShortageRows: rows,
          isPurchaseShortageLoading: false,
          purchaseShortageError: '',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isPurchaseShortageLoading: false,
          purchaseShortageError: e.toString(),
        ),
      );
    }
  }

  Future<void> _onExportPurchaseShortage(
    ExportPurchaseShortage event,
    Emitter<InventoryState> emit,
  ) async {
    if (state.purchaseShortageRows.isEmpty) return;
    if (state.isExporting) return;

    emit(
      state.copyWith(
        isExporting: true,
        purchaseShortageError: '',
        exportMessage: 'Preparing export...',
      ),
    );

    try {
      emit(state.copyWith(exportMessage: 'Generating shortage Excel...'));

      await PurchaseShortageExcelExporter.export(
        rows: state.purchaseShortageRows,
        loadBranchStockRows: (onRow) {
          return repo.forEachPurchaseShortageBranchStock(
            runDate: event.runDate,
            onRow: onRow,
          );
        },
        onBranchStockProgress: (written, total) {
          final message = total > 0
              ? 'Writing branches stock CSV: $written / $total'
              : 'Writing branches stock CSV: $written rows...';
          emit(state.copyWith(exportMessage: message));
        },
      );

      emit(
        state.copyWith(
          isExporting: false,
          exportMessage: 'Export completed: Shortage XLSX + Branches Stock CSV',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isExporting: false,
          purchaseShortageError: e.toString(),
          exportMessage: 'Export failed',
        ),
      );
    }
  }

  Future<void> _onLoadBranchSettings(
    LoadBranchSettings event,
    Emitter<InventoryState> emit,
  ) async {
    emit(
      state.copyWith(
        isBranchSettingsLoading: true,
        branchSettingsError: '',
        branchSettingsMessage: '',
      ),
    );

    try {
      final rows = await repo.fetchBranchSettings();
      emit(
        state.copyWith(
          branchSettings: rows,
          isBranchSettingsLoading: false,
          branchSettingsError: '',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isBranchSettingsLoading: false,
          branchSettingsError: e.toString(),
        ),
      );
    }
  }

  Future<void> _onSaveBranchSetting(
    SaveBranchSetting event,
    Emitter<InventoryState> emit,
  ) async {
    emit(
      state.copyWith(
        isBranchSettingsSaving: true,
        branchSettingsError: '',
        branchSettingsMessage: '',
      ),
    );

    try {
      await repo.saveBranchSetting(
        branch: event.branch,
        originalBranchName: event.originalBranchName,
      );
      final rows = await repo.fetchBranchSettings();
      emit(
        state.copyWith(
          branchSettings: rows,
          isBranchSettingsSaving: false,
          branchSettingsMessage: 'Branch settings saved successfully',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isBranchSettingsSaving: false,
          branchSettingsError: e.toString(),
        ),
      );
    }
  }

  Future<void> _onImportAllocationFile(
    ImportAllocationFile event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) return;

      emit(
        state.copyWith(
          isAllocationLoading: true,
          allocationError: '',
          allocationResults: [],
          allocationSourceRows: [],
          allocationLoadedRows: 0,
        ),
      );

      final bytes = result.files.single.bytes!;
      String csvText;
      try {
        csvText = utf8.decode(bytes);
      } catch (_) {
        csvText = latin1.decode(bytes);
      }

      final rows = const CsvToListConverter().convert(csvText);
      if (rows.length < 2) {
        throw Exception('Allocation import file is empty.');
      }

      const branchCol = 0;
      const codeCol = 1;
      const nameCol = 2;
      const extraCol = 3;
      const reorderCol = 4;
      const finalCol = 5;

      final imported = <_AllocationImportRow>[];
      for (final rawRow in rows.skip(1)) {
        final row = List<dynamic>.from(rawRow);
        String cell(int index) =>
            index >= 0 && index < row.length ? row[index].toString() : '';

        if (row.length < 6) continue;

        final branch = cell(branchCol).trim();
        final itemCode = cell(codeCol).trim();
        if (branch.isEmpty || itemCode.isEmpty) continue;

        final reorderQty = _allocationNum(cell(reorderCol));
        final finalReorder = _allocationNum(cell(finalCol));
        final extraQty = _allocationNum(cell(extraCol));

        imported.add(
          _AllocationImportRow(
            branch: branch,
            itemCode: itemCode,
            itemName: cell(nameCol).trim(),
            extraQty: extraQty,
            shortage: (reorderQty - finalReorder).clamp(0, double.infinity),
          ),
        );
      }

      final results = _buildImportedAllocationResults(
        rows: imported,
        priorityBranches: event.priorityBranches,
      );
      final sourceRows = imported
          .map(
            (row) => AllocationSourceRow(
              branch: row.branch,
              itemCode: row.itemCode,
              itemName: row.itemName,
              category: '',
              itemPurchaseType: '1#NORMAL PURCHASE',
              reorderQty: row.shortage,
              finalReorderQty: 0,
              extraQtyMoreThanMonth: row.extraQty,
              branchStock: 0,
              demandFor30Days: 0,
              branchStockDays: 0,
              stockCoverText: '',
            ),
          )
          .toList();

      emit(
        state.copyWith(
          isAllocationLoading: false,
          allocationResults: results,
          allocationSourceRows: sourceRows,
          allocationLoadedRows: results.length,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isAllocationLoading: false,
          allocationError: e.toString(),
        ),
      );
    }
  }

  int _allocationPriorityRank(String branch, Set<String> priorityBranches) {
    return priorityBranches.contains(_allocationBranchKey(branch)) ? 0 : 1;
  }

  String _allocationBranchKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  List<AllocationResultRow> _buildImportedAllocationResults({
    required List<_AllocationImportRow> rows,
    required List<String> priorityBranches,
  }) {
    final byItem = <String, List<_AllocationImportRow>>{};
    final prioritySet = priorityBranches
        .map(_allocationBranchKey)
        .where((branch) => branch.isNotEmpty)
        .toSet();

    for (final row in rows) {
      byItem.putIfAbsent(row.itemCode, () => []).add(row);
    }

    final results = <AllocationResultRow>[];

    for (final itemRows in byItem.values) {
      final receivers = itemRows.where((row) => row.shortage > 0).toList()
        ..sort((a, b) {
          final pa = _allocationPriorityRank(a.branch, prioritySet);
          final pb = _allocationPriorityRank(b.branch, prioritySet);
          if (pa != pb) return pa.compareTo(pb);
          final shortageCompare = b.shortage.compareTo(a.shortage);
          if (shortageCompare != 0) return shortageCompare;
          return a.branch.compareTo(b.branch);
        });

      final donors = itemRows.where((row) => row.extraQty > 0).toList()
        ..sort((a, b) {
          final extraCompare = b.extraQty.compareTo(a.extraQty);
          if (extraCompare != 0) return extraCompare;
          return a.branch.compareTo(b.branch);
        });

      final donorRemaining = <String, num>{
        for (final donor in donors) donor.branch: donor.extraQty,
      };

      for (final receiver in receivers) {
        var need = receiver.shortage;
        if (need <= 0) continue;

        for (final donor in donors) {
          if (donor.branch == receiver.branch) continue;

          final available = donorRemaining[donor.branch] ?? 0;
          if (available <= 0) continue;

          final qty = available >= need ? need : available;
          if (qty <= 0) continue;

          results.add(
            AllocationResultRow(
              fromBranch: donor.branch,
              itemCode: receiver.itemCode,
              itemName: receiver.itemName.isNotEmpty
                  ? receiver.itemName
                  : donor.itemName,
              qty: qty,
              toBranch: receiver.branch,
              category: '',
            ),
          );

          donorRemaining[donor.branch] = available - qty;
          need -= qty;
          if (need <= 0) break;
        }
      }
    }

    results.sort((a, b) {
      final priorityCompare = _allocationPriorityRank(
        a.toBranch,
        prioritySet,
      ).compareTo(_allocationPriorityRank(b.toBranch, prioritySet));
      if (priorityCompare != 0) return priorityCompare;
      final toCompare = a.toBranch.compareTo(b.toBranch);
      if (toCompare != 0) return toCompare;
      final codeCompare = a.itemCode.compareTo(b.itemCode);
      if (codeCompare != 0) return codeCompare;
      return a.fromBranch.compareTo(b.fromBranch);
    });

    return results;
  }

  num _allocationNum(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9\.\-]'), '');
    if (!RegExp(r'^-?[0-9]+(\.[0-9]+)?$').hasMatch(cleaned)) return 0;
    return num.tryParse(cleaned) ?? 0;
  }

  Future<void> _onExportCurrent(
    ExportMaxAdjCurrent event,
    Emitter<InventoryState> emit,
  ) async {
    if (state.isExporting) return;
    try {
      emit(
        state.copyWith(
          isExporting: true,
          exportMessage: 'Fetching current adjustment records...',
        ),
      );
      final data = await repo.fetchMaxAdjExport();
      emit(
        state.copyWith(
          isExporting: true,
          exportMessage: 'Building Excel file for ${data.length} records...',
        ),
      );
      await MaxAdjExcelExporter.export(rows: data, includeHistory: false);
      emit(
        state.copyWith(isExporting: false, exportMessage: 'Export completed'),
      );
    } catch (e) {
      emit(state.copyWith(isExporting: false, exportMessage: 'Export failed'));
      print("Export Current Error: $e");
    }
  }

  Future<void> _onExportWithHistory(
    ExportMaxAdjWithHistory event,
    Emitter<InventoryState> emit,
  ) async {
    if (state.isExporting) return;
    try {
      emit(
        state.copyWith(
          isExporting: true,
          exportMessage: 'Fetching current adjustments and history...',
        ),
      );
      final current = await repo.fetchMaxAdjExport();
      final log = await repo.fetchMaxAdjLogExport();

      final merged = [...current, ...log];

      emit(
        state.copyWith(
          isExporting: true,
          exportMessage: 'Building Excel file for ${merged.length} records...',
        ),
      );
      await MaxAdjExcelExporter.export(rows: merged, includeHistory: true);
      emit(
        state.copyWith(isExporting: false, exportMessage: 'Export completed'),
      );
    } catch (e) {
      emit(state.copyWith(isExporting: false, exportMessage: 'Export failed'));
      print("Export History Error: $e");
    }
  }

  Future<void> _onResolveImportDuplicates(
    ResolveImportDuplicates event,
    Emitter<InventoryState> emit,
  ) async {
    final source = _pendingImportSource;
    if (source == null || _pendingImportBytes == null) {
      emit(
        state.copyWith(
          importMessage:
              'The selected import file is no longer available. Please upload it again.',
          importSuccess: false,
          importDuplicateCount: 0,
        ),
      );
      return;
    }

    if (event.action == ImportDuplicateAction.download) {
      switch (source) {
        case 'max_adjustment':
          await MaxAdjExcelExporter.export(
            rows: _pendingImportDuplicates,
            includeHistory: false,
          );
        case 'assortment':
          await AssortmentExcelExporter.export(
            rows: _pendingImportDuplicates,
            includeHistory: false,
          );
        case 'tma':
          await TmaExcelExporter.export(
            rows: _pendingImportDuplicates,
            includeHistory: false,
          );
        case 'formulary':
          await FormularyExcelExporter.export(
            rows: _pendingImportDuplicates,
            includeHistory: false,
          );
      }
      emit(state.copyWith(importMessage: 'Duplicate report downloaded.'));
      return;
    }

    final overwrite = event.action == ImportDuplicateAction.applyWithDuplicates;
    switch (source) {
      case 'max_adjustment':
        add(
          ImportMaxAdjExcel(
            forceApply: overwrite,
            reusePickedFile: true,
            skipDuplicates: !overwrite,
          ),
        );
      case 'assortment':
        add(
          ImportAssortmentExcel(
            forceApply: overwrite,
            reusePickedFile: true,
            skipDuplicates: !overwrite,
          ),
        );
      case 'tma':
        add(
          ImportTmaExcel(
            forceApply: overwrite,
            reusePickedFile: true,
            skipDuplicates: !overwrite,
          ),
        );
      case 'formulary':
        add(
          ImportFormularyExcel(
            forceApply: overwrite,
            reusePickedFile: true,
            skipDuplicates: !overwrite,
          ),
        );
    }
  }

  void _cachePendingImport(String source, Uint8List bytes) {
    _pendingImportSource = source;
    _pendingImportBytes = bytes;
    _pendingImportDuplicates = const [];
  }

  void _cacheImportDuplicates(String source, List<Map<String, dynamic>> rows) {
    _pendingImportSource = source;
    _pendingImportDuplicates = List<Map<String, dynamic>>.from(rows);
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
          importDuplicateCount: 0,
        ),
      );

      Uint8List? bytes;
      if (event.reusePickedFile) {
        bytes = _pendingImportBytes;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv'],
          withData: true,
        );
        if (result == null) {
          emit(state.copyWith(isImporting: false));
          return;
        }
        bytes = result.files.single.bytes;
        if (bytes != null) _cachePendingImport('max_adjustment', bytes);
      }
      if (bytes == null) {
        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage:
                'Import file is unavailable. Please upload it again.',
          ),
        );
        return;
      }

      // Give the web renderer one frame to show the progress UI first.
      await Future<void>.delayed(Duration.zero);

      String csvText;
      try {
        csvText = utf8.decode(bytes);
      } catch (_) {
        csvText = latin1.decode(bytes);
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
      emit(
        state.copyWith(
          importProgress: 0.05,
          importMessage: 'Validating branches and existing adjustments...',
        ),
      );

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

      await Future<void>.delayed(Duration.zero);

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
          final type = max <= current ? 'DECREASE' : 'INCREASE';

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
          await Future<void>.delayed(Duration.zero);
        }
      }

      // ===============================
      // EXPORT DUPLICATES
      // ===============================
      if (conflicts.isNotEmpty && !event.forceApply && !event.skipDuplicates) {
        _cacheImportDuplicates('max_adjustment', conflicts);
        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage:
                'Found ${conflicts.length} duplicate item(s). Choose how to continue.',
            importDuplicateCount: conflicts.length,
            importDuplicateSource: 'max_adjustment',
          ),
        );
        return;
      }

      if (conflicts.isNotEmpty && !event.forceApply && !event.skipDuplicates) {
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
      emit(
        state.copyWith(
          importProgress: .96,
          importMessage: 'Uploading changes...',
        ),
      );

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

    if (value is DateTime) {
      return _dateOnly(value);
    }

    if (value is num) {
      final excelDate = DateTime(
        1899,
        12,
        30,
      ).add(Duration(days: value.floor()));
      return _dateOnly(excelDate);
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final iso = DateTime.tryParse(raw);
    if (iso != null) return _dateOnly(iso);

    final dateOnly = raw.split(RegExp(r'\s+')).first;
    final parts = dateOnly
        .replaceAll('\\', '/')
        .replaceAll('-', '/')
        .replaceAll('.', '/')
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (parts.length != 3) return null;

    int? year;
    int? month;
    int? day;

    if (parts[0].length == 4) {
      year = int.tryParse(parts[0]);
      month = int.tryParse(parts[1]);
      day = int.tryParse(parts[2]);
    } else {
      day = int.tryParse(parts[0]);
      month = int.tryParse(parts[1]);
      year = int.tryParse(parts[2]);
    }

    if (year == null || month == null || day == null) return null;
    if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }

    return _dateOnly(DateTime(year, month, day));
  }

  String _dateOnly(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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
          importDuplicateCount: 0,
        ),
      );

      Uint8List? bytes;
      if (event.reusePickedFile) {
        bytes = _pendingImportBytes;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv'],
          withData: true,
        );
        if (result == null) {
          emit(state.copyWith(isImporting: false));
          return;
        }
        bytes = result.files.single.bytes;
        if (bytes != null) _cachePendingImport('assortment', bytes);
      }
      if (bytes == null) {
        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage:
                'Import file is unavailable. Please upload it again.',
          ),
        );
        return;
      }

      String csvText;

      try {
        csvText = utf8.decode(bytes);
      } catch (_) {
        csvText = latin1.decode(bytes);
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

      if (conflicts.isNotEmpty && !event.forceApply && !event.skipDuplicates) {
        _cacheImportDuplicates('assortment', conflicts);
        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage:
                'Found ${conflicts.length} duplicate item(s). Choose how to continue.',
            importDuplicateCount: conflicts.length,
            importDuplicateSource: 'assortment',
          ),
        );
        return;
      }

      if (conflicts.isNotEmpty && !event.forceApply && !event.skipDuplicates) {
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
          importDuplicateCount: 0,
        ),
      );

      Uint8List? bytes;
      if (event.reusePickedFile) {
        bytes = _pendingImportBytes;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv'],
          withData: true,
        );
        if (result == null) {
          emit(state.copyWith(isImporting: false));
          return;
        }
        bytes = result.files.single.bytes;
        if (bytes != null) _cachePendingImport('tma', bytes);
      }
      if (bytes == null) {
        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage:
                'Import file is unavailable. Please upload it again.',
          ),
        );
        return;
      }

      String csvText;
      try {
        csvText = utf8.decode(bytes);
      } catch (_) {
        csvText = latin1.decode(bytes);
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
      if (conflicts.isNotEmpty && !event.forceApply && !event.skipDuplicates) {
        _cacheImportDuplicates('tma', conflicts);
        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage:
                'Found ${conflicts.length} duplicate item(s). Choose how to continue.',
            importDuplicateCount: conflicts.length,
            importDuplicateSource: 'tma',
          ),
        );
        return;
      }

      if (conflicts.isNotEmpty && !event.forceApply && !event.skipDuplicates) {
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
          importDuplicateCount: 0,
        ),
      );

      Uint8List? bytes;
      if (event.reusePickedFile) {
        bytes = _pendingImportBytes;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv'],
          withData: true,
        );
        if (result == null) {
          emit(state.copyWith(isImporting: false));
          return;
        }
        bytes = result.files.single.bytes;
        if (bytes != null) _cachePendingImport('formulary', bytes);
      }
      if (bytes == null) {
        emit(
          state.copyWith(
            isImporting: false,
            importSuccess: false,
            importMessage:
                'Import file is unavailable. Please upload it again.',
          ),
        );
        return;
      }

      final content = String.fromCharCodes(bytes);
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

      if (!event.forceApply && !event.skipDuplicates) {
        final existingRows = await Supabase.instance.client
            .from('branch_formulary')
            .select(
              'branch_name, item_code, item_name, revised_branch_formulary, revised_date, reason',
            );
        final existingByKey = {
          for (final row in existingRows)
            '${row['branch_name']}|${row['item_code']}': row,
        };
        final conflicts = <Map<String, dynamic>>[];
        for (var i = 1; i < rows.length; i++) {
          final row = rows[i];
          if (row.length < 7 ||
              (row[0]?.toString().trim().toUpperCase() == 'DELETE')) {
            continue;
          }
          final branch = (row[1] ?? '').toString().trim();
          final itemCode = (row[2] ?? '').toString().trim();
          final existing = existingByKey['$branch|$itemCode'];
          if (existing != null) {
            conflicts.add({
              'branch_name': branch,
              'item_code': itemCode,
              'item_name': row[3]?.toString() ?? '',
              'old_formulary': existing['revised_branch_formulary'],
              'old_date': existing['revised_date'],
              'old_reason': existing['reason'],
              'new_formulary': row[4],
              'new_date': _parseDate(row[5]),
              'new_reason': row[6],
            });
          }
        }
        if (conflicts.isNotEmpty) {
          _cacheImportDuplicates('formulary', conflicts);
          emit(
            state.copyWith(
              isImporting: false,
              importSuccess: false,
              importMessage:
                  'Found ${conflicts.length} duplicate item(s). Choose how to continue.',
              importDuplicateCount: conflicts.length,
              importDuplicateSource: 'formulary',
            ),
          );
          return;
        }
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
      if (conflicts.isNotEmpty && !event.forceApply && !event.skipDuplicates) {
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

  bool _isCurrentOrdersLoad(String runDate, int token) {
    return _ordersLoadingRunDate == runDate && _ordersLoadToken == token;
  }

  Future<List<Map<String, dynamic>>> _fetchOrdersPageSafe({
    required String runDate,
    required int from,
    required int to,
    int attempt = 0,
  }) async {
    try {
      return await repo.fetchOrdersPage(runDate: runDate, from: from, to: to);
    } catch (e) {
      final isTimeout =
          e is PostgrestException &&
          (e.code == '57014' ||
              e.message.toLowerCase().contains('statement timeout'));

      if (!isTimeout) rethrow;

      final size = to - from + 1;

      if (size > 1000) {
        final mid = from + (size ~/ 2) - 1;
        final left = await _fetchOrdersPageSafe(
          runDate: runDate,
          from: from,
          to: mid,
          attempt: 0,
        );
        final right = await _fetchOrdersPageSafe(
          runDate: runDate,
          from: mid + 1,
          to: to,
          attempt: 0,
        );
        return [...left, ...right];
      }

      if (attempt < 3) {
        await Future.delayed(Duration(milliseconds: 450 * (attempt + 1)));
        return _fetchOrdersPageSafe(
          runDate: runDate,
          from: from,
          to: to,
          attempt: attempt + 1,
        );
      }

      rethrow;
    }
  }

  Future<void> _onLoadOrdersPage(
    LoadOrdersPage event,
    Emitter<InventoryState> emit,
  ) async {
    // Pure local slice — zero network calls, instant page flip
    const pageSize = 30000;

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
        allOrders: pageRows,
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

  Future<void> _onLoadAdditionalOrderHistory(
    LoadAdditionalOrderHistory event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(state.copyWith(isAdditionalHistoryLoading: true));

      final rows = await repo.fetchAdditionalOrderHistory(
        from: event.from,
        to: event.to,
      );

      emit(
        state.copyWith(
          additionalOrderHistory: rows,
          isAdditionalHistoryLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isAdditionalHistoryLoading: false));
      print('LoadAdditionalOrderHistory error: $e');
    }
  }

  Future<void> _onLoadOrderEditAnalysis(
    LoadOrderEditAnalysis event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(state.copyWith(isOrderEditAnalysisLoading: true));

      final data = await repo.fetchOrderEditAnalysis(
        from: event.from,
        to: event.to,
      );

      emit(
        state.copyWith(
          orderEditAnalysis: data,
          isOrderEditAnalysisLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isOrderEditAnalysisLoading: false));
      print('LoadOrderEditAnalysis error: $e');
    }
  }

  Future<void> _onLoadRequestEffectiveness(
    LoadRequestEffectiveness event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(state.copyWith(isEffectivenessLoading: true));

      final data = await repo.fetchRequestEffectiveness(
        from: event.from,
        to: event.to,
        branch: event.branch,
      );

      emit(
        state.copyWith(
          requestEffectiveness: data,
          isEffectivenessLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isEffectivenessLoading: false));
      print('LoadRequestEffectiveness error: $e');
    }
  }

  Future<void> _onLoadOrderEditSalesPerformance(
    LoadOrderEditSalesPerformance event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      emit(state.copyWith(isOrderEditSalesLoading: true));

      final data = await repo.fetchOrderEditSalesPerformance(
        from: event.from,
        to: event.to,
        branch: event.branch,
      );

      emit(
        state.copyWith(
          orderEditSalesPerformance: data,
          isOrderEditSalesLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isOrderEditSalesLoading: false));
      print('LoadOrderEditSalesPerformance error: $e');
    }
  }

  Future<void> _onAdditionalRealtimeUpdate(
    AdditionalRequestRealtimeUpdated event,
    Emitter<InventoryState> emit,
  ) async {
    if (!_shouldDisplayAdditionalRealtimeRow(event.row)) {
      final id = (event.row['id'] ?? '').toString();
      if (id.isEmpty) return;

      final updated = state.additionalRequests
          .where((e) => e.groupId != id)
          .toList();

      _emitAdditionalRequests(emit, updated);
      return;
    }

    final item = _additionalFromRealtimeRow(event.row);
    final updated = _mergeAdditionalRequest(state.additionalRequests, item);

    _emitAdditionalRequests(emit, updated);
  }

  Future<void> _onAdditionalInsertedRealtime(
    AdditionalRequestInsertedRealtime event,
    Emitter<InventoryState> emit,
  ) async {
    if (!_shouldDisplayAdditionalRealtimeRow(event.row)) return;

    final item = _additionalFromRealtimeRow(event.row);
    final updated = _mergeAdditionalRequest(state.additionalRequests, item);
    final branchCounts = _updatedBranchAdditionalCounts(
      row: event.row,
      delta: 1,
    );

    _emitAdditionalRequests(
      emit,
      updated,
      additionalTodayBranchCount: branchCounts,
    );
  }

  Future<void> _onAdditionalDeletedRealtime(
    AdditionalRequestDeletedRealtime event,
    Emitter<InventoryState> emit,
  ) async {
    final updated = state.additionalRequests
        .where((e) => e.groupId != event.id)
        .toList();

    _emitAdditionalRequests(emit, updated);
  }

  AdditionalRequestGroup _additionalFromRealtimeRow(Map<String, dynamic> row) {
    return AdditionalRequestGroup(
      groupId: (row['id'] ?? '').toString(),
      branchName: (row['branch_name'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now(),
      inventoryApprovedAt: DateTime.tryParse(
        (row['inventory_approved_at'] ?? '').toString(),
      ),
      doneAt: DateTime.tryParse((row['done_at'] ?? '').toString()),
      itemsCount: 1,
      status: (row['status'] ?? 'pending').toString(),
      itemNames: (row['item_name'] ?? '').toString(),
      itemCodes: (row['item_code'] ?? '').toString(),
      contactLogistic: (row['contact_logistic'] ?? '').toString(),
      requestQty: row['request_qty'] ?? 0,
      branchStock: row['branch_stock'] ?? 0,
      storeStock: row['store_stock'] ?? 0,
      sales: row['sales_45d'] ?? 0,
      finalReorder: row['final_reorder_qty'] ?? '',
      itemStatus: row['item_purchase_type'] ?? '',
      todayCount: 1,
      fulfilledQty: row['fulfilled_qty'] ?? 0,
      storeNote: row['store_note'] ?? '',
      inventoryQty: row['inventory_qty'] ?? 0,
      inventoryNote: row['inventory_note'] ?? '',
    );
  }

  List<AdditionalRequestGroup> _mergeAdditionalRequest(
    List<AdditionalRequestGroup> current,
    AdditionalRequestGroup item,
  ) {
    final list = current.where((e) => e.groupId != item.groupId).toList();
    list.insert(0, item);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  ({int pending, int sentToStore, int today, int rejected}) _additionalCounters(
    List<AdditionalRequestGroup> requests,
  ) {
    final pending = requests
        .where((e) => _isPendingAdditionalStatus(e.status))
        .length;
    final sentToStore = requests
        .where((e) => e.status.toLowerCase().trim() == 'sent_to_store')
        .length;
    final today = requests
        .where((e) => _isInCurrentOperationDate(e.createdAt))
        .length;
    final rejected = requests
        .where(
          (e) =>
              e.status.toLowerCase().trim() == 'rejected' &&
              _isInCurrentOperationDate(
                e.doneAt ?? e.inventoryApprovedAt ?? e.createdAt,
              ),
        )
        .length;

    return (
      pending: pending,
      sentToStore: sentToStore,
      today: today,
      rejected: rejected,
    );
  }

  void _emitAdditionalRequests(
    Emitter<InventoryState> emit,
    List<AdditionalRequestGroup> requests, {
    Map<String, int>? additionalTodayBranchCount,
  }) {
    final counters = _additionalCounters(requests);

    emit(
      state.copyWith(
        additionalRequests: requests,
        additionalCount: requests.length,
        additionalPendingCount: counters.pending,
        additionalSentToStoreCount: counters.sentToStore,
        additionalTodayCount: counters.today,
        additionalMonthCount: counters.rejected,
        additionalTodayBranchCount:
            additionalTodayBranchCount ?? state.additionalTodayBranchCount,
      ),
    );
  }

  Map<String, int>? _updatedBranchAdditionalCounts({
    required Map<String, dynamic> row,
    required int delta,
  }) {
    if ((row['run_date'] ?? '').toString() != runDate) return null;

    final branch = (row['branch_name'] ?? '').toString();
    if (branch.isEmpty) return null;

    final updated = Map<String, int>.from(state.additionalTodayBranchCount);
    updated[branch] = ((updated[branch] ?? 0) + delta)
        .clamp(0, 1 << 31)
        .toInt();
    return updated;
  }

  static bool _isInCurrentOperationDate(DateTime value) {
    final now = DateTime.now();
    final todayNinePm = DateTime(now.year, now.month, now.day, 21);
    final start = now.isBefore(todayNinePm)
        ? todayNinePm.subtract(const Duration(days: 1))
        : todayNinePm;
    final end = start.add(const Duration(days: 1));
    final local = value.toLocal();
    return !local.isBefore(start) && local.isBefore(end);
  }

  static bool _isPendingAdditionalStatus(String status) {
    final value = status.toLowerCase().trim();
    return value == 'pending' || value == 'pending_inventory';
  }

  static String _additionalRealtimeNotificationKey(Map<String, dynamic> row) {
    final groupId = (row['request_group_id'] ?? '').toString().trim();
    if (groupId.isNotEmpty) return groupId;
    final id = (row['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
    return '${row['branch_name'] ?? ''}-${row['created_at'] ?? ''}';
  }

  static String _normalizeBranch(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static bool _shouldDisplayAdditionalRealtimeRow(Map<String, dynamic> row) {
    final status = (row['status'] ?? '').toString();
    if (_isPendingAdditionalStatus(status)) return true;

    final value = status.toLowerCase().trim();
    final dates = <dynamic>[
      if (value == 'sent_to_store' || value == 'rejected')
        row['inventory_approved_at'],
      if (value == 'done' || value == 'rejected') row['done_at'],
      row['created_at'],
    ];

    for (final raw in dates) {
      final parsed = DateTime.tryParse((raw ?? '').toString())?.toLocal();
      if (parsed == null) continue;

      if (_isInCurrentOperationDate(parsed)) {
        return true;
      }
    }

    return false;
  }
}

class _AllocationImportRow {
  final String branch;
  final String itemCode;
  final String itemName;
  final num extraQty;
  final num shortage;

  const _AllocationImportRow({
    required this.branch,
    required this.itemCode,
    required this.itemName,
    required this.extraQty,
    required this.shortage,
  });
}
