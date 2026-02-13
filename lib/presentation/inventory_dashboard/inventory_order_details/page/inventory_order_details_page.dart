import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../home/widgets/items_table.dart';
import '../bloc/inventory_order_details_bloc.dart';
import '../bloc/inventory_order_details_bloc_factory.dart';
import '../bloc/inventory_order_details_event.dart';
import '../bloc/inventory_order_details_state.dart';

class InventoryOrderDetailsPage extends StatelessWidget {
  final String branchName; // branch name OR '__ALL__'
  final String runDate;

  const InventoryOrderDetailsPage({
    super.key,
    required this.branchName,
    required this.runDate,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final bloc = InventoryOrderDetailsBlocFactory.create();
        bloc.add(SetRunDate(runDate));
        bloc.add(LoadItems(branchName: branchName, pageIndex: 0));
        return bloc;
      },
      child: _View(branchName: branchName, runDate: runDate),
    );
  }
}

class _View extends StatelessWidget {
  final String branchName;
  final String runDate;

  const _View({required this.branchName, required this.runDate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          '${branchName == "__ALL__" ? "ALL BRANCHES" : branchName} • $runDate',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child:
            BlocBuilder<InventoryOrderDetailsBloc, InventoryOrderDetailsState>(
              builder: (context, s) {
                final isLoading =
                    s.status == InventoryOrderDetailsStatus.loading;

                return Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'Page: ${s.pageIndex + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: s.pageIndex <= 0 || isLoading
                              ? null
                              : () => context
                                    .read<InventoryOrderDetailsBloc>()
                                    .add(
                                      LoadItems(
                                        branchName: branchName,
                                        pageIndex: s.pageIndex - 1,
                                      ),
                                    ),
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('Prev'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: isLoading
                              ? null
                              : () => context
                                    .read<InventoryOrderDetailsBloc>()
                                    .add(
                                      LoadItems(
                                        branchName: branchName,
                                        pageIndex: s.pageIndex + 1,
                                      ),
                                    ),
                          icon: const Icon(Icons.chevron_right),
                          label: const Text('Next'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (s.status == InventoryOrderDetailsStatus.failure &&
                        s.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          s.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    Expanded(
                      child: ItemsTable(
                        rows: s.rows,
                        isLoading: isLoading,
                        onCreateOrder: () {},
                        onEditQty: (rowIndex, qty, reason) {},
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
