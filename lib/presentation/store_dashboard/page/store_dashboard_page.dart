import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/print_additional_service.dart';
import '../../../data/datasources/remote/store_remote_ds.dart';
import '../../../data/repositories/store_repository_impl.dart';
import '../../../domain/repositories/store_repository.dart';
import '../bloc/store_bloc.dart';
import '../bloc/store_event.dart';
import '../bloc/store_state.dart';
import '../widgets/ProcessingAdditionalDialog.dart';
import '../widgets/store_dashboard_body.dart';

class StoreDashboardPage extends StatelessWidget {
  final String runDate;
  final int pendingStockCheckCount;
  final int overdueStockCheckCount;
  final VoidCallback? onOpenStockCheck;

  const StoreDashboardPage({
    super.key,
    required this.runDate,
    this.pendingStockCheckCount = 0,
    this.overdueStockCheckCount = 0,
    this.onOpenStockCheck,
  });

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    final remote = StoreRemoteDs(client);
    final StoreRepository repo = StoreRepositoryImpl(remote);

    return BlocProvider(
      create: (_) => StoreBloc(repo)..add(LoadStoreDashboard(runDate)),
      child: StoreDashboardView(
        runDate: runDate,
        pendingStockCheckCount: pendingStockCheckCount,
        overdueStockCheckCount: overdueStockCheckCount,
        onOpenStockCheck: onOpenStockCheck,
      ),
    );
  }
}

class StoreDashboardView extends StatefulWidget {
  final String runDate;
  final int pendingStockCheckCount;
  final int overdueStockCheckCount;
  final VoidCallback? onOpenStockCheck;

  const StoreDashboardView({
    super.key,
    required this.runDate,
    required this.pendingStockCheckCount,
    required this.overdueStockCheckCount,
    required this.onOpenStockCheck,
  });

  @override
  State<StoreDashboardView> createState() => _StoreDashboardViewState();
}

class _StoreDashboardViewState extends State<StoreDashboardView> {
  RealtimeChannel? channel;

  bool firstLoad = true;

  @override
  void initState() {
    super.initState();
    _startRealtime();
  }

  void _startRealtime() {
    final client = Supabase.instance.client;
    final bloc = context.read<StoreBloc>();

    channel = client
        .channel('store-dashboard-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_submissions',
          callback: (_) {
            bloc.add(LoadStoreDashboard(widget.runDate, silent: true));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'additional_requests',
          callback: (_) {
            bloc.add(LoadStoreDashboard(widget.runDate, silent: true));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'additional_order_inventory',
          callback: (_) {
            bloc.add(LoadStoreDashboard(widget.runDate, silent: true));
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),

      body: BlocListener<StoreBloc, StoreState>(
        listenWhen: (previous, current) =>
            previous.processingBatch != current.processingBatch ||
            previous.printBatch != current.printBatch,

        listener: (context, state) async {
          /// =========================
          /// 🖨 PRINT FLOW
          /// =========================
          /// 🖨 PRINT FLOW
          if (state.printBatch.isNotEmpty) {
            final bloc = context.read<StoreBloc>();
            await PrintAdditionalService.printBatch(state.printBatch);
            if (!context.mounted) return;

            bloc.add(ClearPrintBatch());
          }

          /// =========================
          /// 📋 DIALOG FLOW
          /// =========================
          if (state.processingBatch.isNotEmpty) {
            final bloc = context.read<StoreBloc>();

            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => BlocProvider.value(
                value: bloc,
                child: ProcessingAdditionalDialog(data: state.processingBatch),
              ),
            );

            context.read<StoreBloc>().add(ClearProcessingBatch());
          }
        },

        child: BlocBuilder<StoreBloc, StoreState>(
          builder: (context, state) {
            final bool isSubmitted =
                state.selectedBranch != null &&
                state.submittedBranches.contains(state.selectedBranch);

            if (firstLoad && state.branches.isNotEmpty) {
              firstLoad = false;
            }

            return Stack(
              children: [
                Column(
                  children: [
                    if (widget.pendingStockCheckCount > 0)
                      _StoreStockCheckNotice(
                        pendingCount: widget.pendingStockCheckCount,
                        overdueCount: widget.overdueStockCheckCount,
                        onTap: widget.onOpenStockCheck,
                      ),
                    Expanded(
                      child: StoreDashboardBody(
                        state: state,
                        isSubmitted: isSubmitted,
                      ),
                    ),
                  ],
                ),

                if (state.isLoading && state.selectedBranch == null)
                  Container(
                    color: Colors.black12,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StoreStockCheckNotice extends StatelessWidget {
  final int pendingCount;
  final int overdueCount;
  final VoidCallback? onTap;

  const _StoreStockCheckNotice({
    required this.pendingCount,
    required this.overdueCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final overdue = overdueCount > 0;
    final color = overdue ? const Color(0xFFDC2626) : const Color(0xFF2563EB);
    final bg = overdue ? const Color(0xFFFFF1F2) : const Color(0xFFEFF6FF);
    final border = overdue ? const Color(0xFFFCA5A5) : const Color(0xFFBFDBFE);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border, width: 1.3),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: .12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Icon(
                    overdue
                        ? Icons.notification_important_rounded
                        : Icons.inventory_2_rounded,
                    color: color,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        overdue
                            ? 'Store Stock Check overdue'
                            : 'Store Stock Check pending',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        overdue
                            ? '$pendingCount item(s) pending - $overdueCount overdue. Open Store Inbox and complete them.'
                            : '$pendingCount item(s) need system and actual quantity confirmation.',
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Text(
                        pendingCount.toString(),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, color: color, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
