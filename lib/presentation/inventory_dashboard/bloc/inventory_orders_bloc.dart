import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/usecases/generate_all_orders.dart';
import '../../../domain/usecases/get_order_job.dart';
import '../../../domain/usecases/load_headers_page.dart';
import '../../../domain/usecases/step_generate_all_orders.dart';
import 'inventory_orders_event.dart';
import 'inventory_orders_state.dart';

class InventoryOrdersBloc
    extends Bloc<InventoryOrdersEvent, InventoryOrdersState> {
  final LoadHeadersPage loadHeadersPage;
  final GenerateAllOrders generateAllOrders; // start
  final StepGenerateAllOrders stepGenerateAllOrders; // step
  final GetOrderJob getOrderJob;

  InventoryOrdersBloc({
    required this.loadHeadersPage,
    required this.generateAllOrders,
    required this.stepGenerateAllOrders,
    required this.getOrderJob,
  }) : super(InventoryOrdersState.initial()) {
    on<SetRunDate>(_onSetRunDate);
    on<LoadHeaders>(_onLoadHeaders);
    on<GenerateAll>(_onGenerateAll);
  }

  Future<void> _onSetRunDate(
    SetRunDate event,
    Emitter<InventoryOrdersState> emit,
  ) async {
    emit(state.copyWith(runDate: event.runDate, pageIndex: 0));
    add(const LoadHeaders(pageIndex: 0));
  }

  Future<void> _onLoadHeaders(
    LoadHeaders event,
    Emitter<InventoryOrdersState> emit,
  ) async {
    try {
      emit(state.copyWith(status: InventoryOrdersStatus.loading, error: null));

      final rows = await loadHeadersPage.call(
        runDate: state.runDate,
        pageIndex: event.pageIndex,
        pageSize: state.pageSize,
      );

      emit(
        state.copyWith(
          status: InventoryOrdersStatus.ready,
          headers: rows,
          pageIndex: event.pageIndex,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: InventoryOrdersStatus.failure,
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> _onGenerateAll(
    GenerateAll event,
    Emitter<InventoryOrdersState> emit,
  ) async {
    try {
      print('[INV] GenerateAll pressed. runDate=${state.runDate}');

      emit(
        state.copyWith(
          status: InventoryOrdersStatus.generating,
          error: null,
          progress: 0,
          progressMessage: 'Starting...',
          totalBranches: 0,
          doneBranches: 0,
        ),
      );

      final jobId = await generateAllOrders.call(runDate: state.runDate);
      print('[INV] Start RPC returned jobId=$jobId');

      emit(state.copyWith(jobId: jobId));

      for (var i = 0; i < 2000; i++) {
        await Future.delayed(const Duration(milliseconds: 300));

        print('[INV] Step call #$i jobId=$jobId');
        await stepGenerateAllOrders.call(jobId: jobId, chunkSize: 10);

        final job = await getOrderJob.call(jobId);
        if (job == null) {
          print('[INV] Job not found yet');
          continue;
        }

        final status = (job['status'] ?? '').toString();
        final msg = (job['message'] ?? '').toString();

        final progressRaw = job['progress_percent'];
        final progress = progressRaw is int
            ? progressRaw
            : int.tryParse(progressRaw?.toString() ?? '0') ?? 0;

        final totalBRaw = job['total_branches'];
        final totalB = totalBRaw is int
            ? totalBRaw
            : int.tryParse(totalBRaw?.toString() ?? '0') ?? 0;

        final doneBRaw = job['done_branches'];
        final doneB = doneBRaw is int
            ? doneBRaw
            : int.tryParse(doneBRaw?.toString() ?? '0') ?? 0;

        print(
          '[INV] status=$status progress=$progress msg="$msg" done=$doneB total=$totalB',
        );

        emit(
          state.copyWith(
            progress: progress.clamp(0, 100),
            progressMessage: msg.isEmpty ? null : msg,
            totalBranches: totalB,
            doneBranches: doneB,
          ),
        );

        if (status == 'done') {
          print('[INV] Job done. Reload headers.');
          emit(state.copyWith(status: InventoryOrdersStatus.ready));
          add(const LoadHeaders(pageIndex: 0));
          return;
        }

        if (status == 'failed') {
          print('[INV] Job failed: $msg');
          emit(
            state.copyWith(
              status: InventoryOrdersStatus.failure,
              error: msg.isEmpty ? 'Job failed' : msg,
            ),
          );
          return;
        }
      }

      emit(
        state.copyWith(
          status: InventoryOrdersStatus.failure,
          error: 'Timeout while generating orders',
        ),
      );
    } catch (e, st) {
      print('[INV] Exception: $e');
      print('[INV] Stack: $st');
      emit(
        state.copyWith(
          status: InventoryOrdersStatus.failure,
          error: e.toString(),
        ),
      );
    }
  }
}
