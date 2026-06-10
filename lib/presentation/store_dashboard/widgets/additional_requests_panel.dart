import 'package:daily_order/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/additional_request_group.dart';
import '../bloc/store_bloc.dart';
import '../bloc/store_event.dart';
import '../bloc/store_state.dart';
import 'ProcessingAdditionalDialog.dart';
import 'additional_history_dialog.dart';
import 'additional_request_tile.dart';

class AdditionalPanel extends StatefulWidget {
  final List<AdditionalRequestGroup> requests;

  const AdditionalPanel({super.key, required this.requests});

  @override
  State<AdditionalPanel> createState() => _AdditionalPanelState();
}

class _AdditionalPanelState extends State<AdditionalPanel> {
  @override
  Widget build(BuildContext context) {
    List<AdditionalRequestGroup> list = [...widget.requests];

    list.sort((a, b) {
      final aUrgent = a.contactLogistic == 'urgent' && a.status != 'done';
      final bUrgent = b.contactLogistic == 'urgent' && b.status != 'done';

      if (aUrgent && !bUrgent) return -1;
      if (!aUrgent && bUrgent) return 1;

      if (a.storeStatus == 'processing' && b.storeStatus != 'processing')
        return -1;
      if (b.storeStatus == 'processing' && a.storeStatus != 'processing')
        return 1;

      if (a.status == "sent_to_store" && b.status != "sent_to_store") return -1;
      if (b.status == "sent_to_store" && a.status != "sent_to_store") return 1;

      /// 🔴 rejected next
      if (a.status == "rejected" && b.status != "rejected") return -1;
      if (b.status == "rejected" && a.status != "rejected") return 1;

      return b.createdAt.compareTo(a.createdAt);
    });

    final state = context.watch<StoreBloc>().state;
    final processingCount = state.additionalRequests
        .where((e) => e.storeStatus == 'processing')
        .length;
    return MultiBlocListener(
      listeners: [
        /// 🔴 ERROR LISTENER
        BlocListener<StoreBloc, StoreState>(
          listenWhen: (prev, curr) =>
              prev.errorMessage != curr.errorMessage &&
              curr.errorMessage != null,
          listener: (context, state) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: Colors.white,
                title: const Text("Notice"),
                content: Text(
                  state.errorMessage!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "OK",
                      style: TextStyle(color: AppColors.secondaryColor),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        BlocListener<StoreBloc, StoreState>(
          listenWhen: (prev, curr) =>
              prev.processingBatch != curr.processingBatch &&
              curr.processingBatch.isNotEmpty,
          listener: (context, state) {
            if (Navigator.of(context).canPop()) return;

            showDialog(
              context: context,
              builder: (_) => BlocProvider.value(
                value: context.read<StoreBloc>(),
                child: ProcessingAdditionalDialog(data: state.processingBatch),
              ),
            );
          },
        ),
      ],
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundWidget,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    icon: state.isPrintingMain
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.print, color: Colors.white),
                    label: Text(
                      state.isPrintingMain
                          ? "Printing..."
                          : "Print Pending Additional",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondaryColor,
                    ),
                    onPressed: state.isPrintingMain
                        ? null
                        : () {
                            final bloc = context.read<StoreBloc>();

                            final hasPending = bloc.state.additionalRequests
                                .any((e) => e.status == 'sent_to_store');

                            if (!hasPending) {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text("Notice"),
                                  content: const Text(
                                    "No pending additional requests",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("OK"),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }

                            bloc.add(CollectAndPrintAdditional());
                          },
                  ),

                  const SizedBox(width: 10),

                  /// 🟢 CONFIRM
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ElevatedButton.icon(
                        icon: state.isOpeningDialog
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check, color: Colors.white),
                        label: Text(
                          state.isOpeningDialog
                              ? "Loading..."
                              : "Additional Confirm",
                          style: const TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        onPressed: state.isOpeningDialog
                            ? null
                            : () {
                                final bloc = context.read<StoreBloc>();

                                final hasProcessing = bloc
                                    .state
                                    .additionalRequests
                                    .any((e) => e.storeStatus == 'processing');

                                if (!hasProcessing) {
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      backgroundColor: Colors.white,
                                      title: const Text("Notice"),
                                      content: const Text(
                                        "Please print first",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text(
                                            "OK",
                                            style: TextStyle(
                                              color: AppColors.secondaryColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  return;
                                }

                                bloc.add(OpenProcessingDialog());
                              },
                      ),

                      /// 🔵 BADGE
                      if (processingCount > 0)
                        Positioned(
                          right: -6,
                          top: -6,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            child: Text(
                              "$processingCount",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Spacer(),

                  /// 🟣 HISTORY
                  ElevatedButton.icon(
                    icon: const Icon(Icons.history, color: AppColors.white),
                    label: const Text(
                      "Additional Order History",
                      style: TextStyle(color: AppColors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      final bloc = context.read<StoreBloc>();

                      showDialog(
                        context: context,
                        builder: (dialogContext) {
                          return BlocProvider.value(
                            value: bloc,
                            child: const AdditionalHistoryDialog(),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: const Divider(color: AppColors.primaryColor),
            ),

            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.playlist_remove,
                            size: 70,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No Additional Requests',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        return AdditionalRequestTile(request: list[i]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
