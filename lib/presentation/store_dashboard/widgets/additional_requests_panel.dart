import 'package:daily_order/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/additional_request_group.dart';
import '../bloc/store_bloc.dart';
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

    /// SORT
    list.sort((a, b) {
      if (a.status == b.status) {
        return b.createdAt.compareTo(a.createdAt);
      }

      if (a.status == "sent_to_store") return -1;
      if (b.status == "sent_to_store") return 1;

      if (a.status == "rejected") return -1;
      if (b.status == "rejected") return 1;

      return 0;
    });

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundWidget,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: const Text(
                    "Additional Requests",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondaryColor,
                    ),
                  ),
                ),

                /// HISTORY BUTTON
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
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                return AdditionalRequestTile(request: list[i]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
